-- SignalFlow hardening. Run after 0001_initial.sql.
-- This limit applies to the free ad-unlock flow (one unlock per user per UTC day).

alter table public.signal_access
  add column if not exists access_day date
  generated always as ((accessed_at at time zone 'UTC')::date) stored;

create unique index if not exists signal_access_one_free_unlock_per_day
  on public.signal_access(user_id, access_day);

create unique index if not exists ad_sessions_provider_session_id_idx
  on public.ad_sessions(provider_session_id);

create or replace function public.complete_ad_unlock(p_provider_session_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session public.ad_sessions%rowtype;
  v_plan text;
  v_signal_id uuid;
begin
  select * into v_session
  from public.ad_sessions
  where provider_session_id = p_provider_session_id
  for update;

  if not found or v_session.status <> 'pending' or v_session.expires_at <= now() then
    return jsonb_build_object('ok', false, 'reason', 'session_invalid_or_expired');
  end if;

  select plan into v_plan from public.profiles where id = v_session.user_id for update;
  if v_plan = 'premium' then
    return jsonb_build_object('ok', false, 'reason', 'premium_account');
  end if;

  if exists (
    select 1 from public.signal_access
    where user_id = v_session.user_id
      and access_day = (now() at time zone 'UTC')::date
  ) then
    return jsonb_build_object('ok', false, 'reason', 'daily_allowance_used');
  end if;

  select id into v_signal_id from public.signals
  where is_published = true
  order by published_at desc
  limit 1;

  if v_signal_id is null then
    return jsonb_build_object('ok', false, 'reason', 'no_published_signal');
  end if;

  update public.ad_sessions
  set status = 'completed', completed_at = now()
  where id = v_session.id and status = 'pending';

  insert into public.signal_access(user_id, signal_id, ad_session_id)
  values (v_session.user_id, v_signal_id, v_session.id);

  return jsonb_build_object('ok', true, 'signal_id', v_signal_id);
exception when unique_violation then
  return jsonb_build_object('ok', false, 'reason', 'daily_allowance_used');
end;
$$;

revoke all on function public.complete_ad_unlock(text) from public, anon, authenticated;
grant execute on function public.complete_ad_unlock(text) to service_role;
