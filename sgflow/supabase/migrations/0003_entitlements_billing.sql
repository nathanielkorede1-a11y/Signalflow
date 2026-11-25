-- SignalFlow v3: UTC daily quotas, auditable access, Stripe event idempotency.
-- Run after 0001_initial.sql and 0002_hardening.sql.

-- Ensure billing fields exist on databases created from an earlier partial schema.
alter table public.profiles add column if not exists plan text not null default 'free';
alter table public.profiles add column if not exists stripe_customer_id text;
alter table public.profiles add column if not exists stripe_subscription_id text;
alter table public.profiles add column if not exists updated_at timestamptz not null default now();

-- The former unique index allowed only one access row/day for every plan,
-- which made the Premium five-signal allowance impossible.
drop index if exists public.signal_access_one_free_unlock_per_day;

create table if not exists public.daily_signal_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_day date not null,
  used integer not null default 0 check (used >= 0 and used <= 5),
  updated_at timestamptz not null default now(),
  primary key(user_id, usage_day)
);
alter table public.daily_signal_usage enable row level security;

create table if not exists public.stripe_events (
  event_id text primary key,
  event_type text not null,
  processed_at timestamptz not null default now()
);
alter table public.stripe_events enable row level security;

-- Grant one Premium signal atomically. Locking the profile row serializes
-- concurrent requests for the same account; all quota days use UTC.
create or replace function public.grant_premium_signal_access(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_plan text; v_day date := (now() at time zone 'UTC')::date; v_used integer; v_signal_id uuid;
begin
 select plan into v_plan from public.profiles where id=p_user_id for update;
 if not found then return jsonb_build_object('ok',false,'reason','profile_not_found'); end if;
 if v_plan <> 'premium' then return jsonb_build_object('ok',false,'reason','premium_required'); end if;
 select used into v_used from public.daily_signal_usage where user_id=p_user_id and usage_day=v_day;
 v_used := coalesce(v_used,0);
 if v_used >= 5 then return jsonb_build_object('ok',false,'reason','daily_limit_reached'); end if;
 select s.id into v_signal_id from public.signals s where s.is_published=true and not exists (select 1 from public.signal_access a where a.user_id=p_user_id and a.signal_id=s.id and a.accessed_at >= (((now() at time zone 'UTC')::date)::timestamp at time zone 'UTC')) order by s.published_at desc limit 1;
 if v_signal_id is null then return jsonb_build_object('ok',false,'reason','no_published_signal'); end if;
 insert into public.daily_signal_usage(user_id,usage_day,used) values(p_user_id,v_day,1)
 on conflict(user_id,usage_day) do update set used=public.daily_signal_usage.used+1,updated_at=now();
 insert into public.signal_access(user_id,signal_id) values(p_user_id,v_signal_id);
 return jsonb_build_object('ok',true,'signal_id',v_signal_id,'used',v_used+1);
end; $$;

-- Replace earlier ad completion RPC with a quota-ledger implementation.
create or replace function public.complete_ad_unlock(p_provider_session_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_session public.ad_sessions%rowtype; v_plan text; v_day date := (now() at time zone 'UTC')::date; v_used integer; v_signal_id uuid;
begin
 select * into v_session from public.ad_sessions where provider_session_id=p_provider_session_id for update;
 if not found then return jsonb_build_object('ok',false,'reason','session_invalid_or_expired'); end if;
 if v_session.status='completed' then return jsonb_build_object('ok',true,'duplicate',true); end if;
 if v_session.status <> 'pending' or v_session.expires_at <= now() then
  return jsonb_build_object('ok',false,'reason','session_invalid_or_expired');
 end if;
 select plan into v_plan from public.profiles where id=v_session.user_id for update;
 if v_plan='premium' then return jsonb_build_object('ok',false,'reason','premium_account'); end if;
 select used into v_used from public.daily_signal_usage where user_id=v_session.user_id and usage_day=v_day;
 v_used:=coalesce(v_used,0);
 if v_used>=1 then return jsonb_build_object('ok',false,'reason','daily_allowance_used'); end if;
 select id into v_signal_id from public.signals where is_published=true order by published_at desc limit 1;
 if v_signal_id is null then return jsonb_build_object('ok',false,'reason','no_published_signal'); end if;
 insert into public.daily_signal_usage(user_id,usage_day,used) values(v_session.user_id,v_day,1)
 on conflict(user_id,usage_day) do update set used=public.daily_signal_usage.used+1,updated_at=now();
 update public.ad_sessions set status='completed',completed_at=now() where id=v_session.id and status='pending';
 insert into public.signal_access(user_id,signal_id,ad_session_id) values(v_session.user_id,v_signal_id,v_session.id);
 return jsonb_build_object('ok',true,'signal_id',v_signal_id,'used',1);
exception when unique_violation then return jsonb_build_object('ok',false,'reason','session_already_used');
end; $$;

revoke all on function public.grant_premium_signal_access(uuid) from public, anon, authenticated;
revoke all on function public.complete_ad_unlock(text) from public, anon, authenticated;
grant execute on function public.grant_premium_signal_access(uuid) to service_role;
grant execute on function public.complete_ad_unlock(text) to service_role;
