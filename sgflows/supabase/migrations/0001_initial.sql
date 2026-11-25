-- SignalFlow initial schema (safe to run on a project with partial/older tables).
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  plan text not null default 'free' check (plan in ('free','premium')),
  stripe_customer_id text,
  stripe_subscription_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Create the table if new, then add newer columns to an older existing table.
create table if not exists public.signals (
  id uuid primary key default gen_random_uuid(),
  external_id text unique,
  symbol text not null,
  direction text not null check (direction in ('BUY','SELL')),
  entry numeric not null,
  stop_loss numeric not null,
  take_profit numeric not null,
  rr numeric,
  status text not null default 'active',
  is_published boolean not null default false,
  published_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.signals add column if not exists external_id text;
alter table public.signals add column if not exists rr numeric;
alter table public.signals add column if not exists status text not null default 'active';
alter table public.signals add column if not exists is_published boolean not null default false;
alter table public.signals add column if not exists published_at timestamptz not null default now();
alter table public.signals add column if not exists created_at timestamptz not null default now();
create unique index if not exists signals_external_id_uidx on public.signals(external_id) where external_id is not null;
create index if not exists signals_published_idx on public.signals(is_published,published_at desc);

create table if not exists public.ad_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider_session_id text not null unique,
  status text not null default 'pending' check(status in ('pending','completed','expired')),
  expires_at timestamptz not null,
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.signal_access (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  signal_id uuid references public.signals(id) on delete set null,
  ad_session_id uuid references public.ad_sessions(id) on delete set null,
  accessed_at timestamptz not null default now()
);

create index if not exists signal_access_user_day_idx on public.signal_access(user_id,accessed_at desc);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,email) values(new.id,new.email)
  on conflict(id) do update set email=excluded.email;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.signals enable row level security;
alter table public.ad_sessions enable row level security;
alter table public.signal_access enable row level security;

drop policy if exists "profile owner reads own profile" on public.profiles;
create policy "profile owner reads own profile" on public.profiles
for select to authenticated using(auth.uid()=id);
-- Other tables are accessed through trusted server-side APIs using the service role.
