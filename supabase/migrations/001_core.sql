-- Invoicedey core data model. All tenant-owned data is protected by organization membership.
create extension if not exists pgcrypto;

create type public.invoice_status as enum ('draft', 'sent', 'viewed', 'partially_paid', 'paid', 'overdue', 'void');
create type public.payment_status as enum ('pending', 'succeeded', 'failed', 'refunded');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text,
  created_at timestamptz not null default now()
);
create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  currency char(3) not null default 'USD',
  invoice_prefix text not null default 'INV',
  tax_registration_number text,
  address jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.organization_members (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'admin', 'member', 'accountant')),
  primary key (organization_id, user_id)
);
create table public.clients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  email text,
  billing_address jsonb not null default '{}'::jsonb,
  tax_id text,
  created_at timestamptz not null default now()
);
create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid not null references public.clients(id),
  invoice_number text not null,
  status public.invoice_status not null default 'draft',
  currency char(3) not null,
  issue_date date not null,
  due_date date not null,
  tax_rate numeric(7,4) not null default 0 check (tax_rate >= 0 and tax_rate <= 100),
  subtotal_minor bigint not null default 0 check (subtotal_minor >= 0),
  tax_minor bigint not null default 0 check (tax_minor >= 0),
  total_minor bigint not null default 0 check (total_minor >= 0),
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, invoice_number)
);
create table public.invoice_line_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  position integer not null,
  description text not null,
  quantity numeric(12,4) not null check (quantity > 0),
  unit_amount_minor bigint not null check (unit_amount_minor >= 0),
  line_total_minor bigint not null check (line_total_minor >= 0),
  unique (invoice_id, position)
);
create table public.payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  amount_minor bigint not null check (amount_minor > 0),
  currency char(3) not null,
  status public.payment_status not null default 'pending',
  provider text,
  provider_reference text unique,
  paid_at timestamptz,
  created_at timestamptz not null default now()
);
create table public.invoice_events (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  actor_id uuid references auth.users(id),
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.clients enable row level security;
alter table public.invoices enable row level security;
alter table public.invoice_line_items enable row level security;
alter table public.payments enable row level security;
alter table public.invoice_events enable row level security;

create function public.is_org_member(org_id uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.organization_members where organization_id = org_id and user_id = auth.uid());
$$;

-- Authenticated onboarding is transactional: every new organization starts with its creator as owner.
create function public.create_organization(org_name text, org_currency char(3) default 'USD')
returns public.organizations
language plpgsql security definer set search_path = public as $$
declare created public.organizations;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  insert into public.organizations (name, currency) values (trim(org_name), org_currency) returning * into created;
  insert into public.organization_members (organization_id, user_id, role) values (created.id, auth.uid(), 'owner');
  return created;
end;
$$;

create policy "members can access their organizations" on public.organizations for all using (public.is_org_member(id)) with check (public.is_org_member(id));
create policy "members can access memberships" on public.organization_members for select using (public.is_org_member(organization_id));
create policy "members can access clients" on public.clients for all using (public.is_org_member(organization_id)) with check (public.is_org_member(organization_id));
create policy "members can access invoices" on public.invoices for all using (public.is_org_member(organization_id)) with check (public.is_org_member(organization_id));
create policy "members can access invoice line items" on public.invoice_line_items for all using (exists (select 1 from public.invoices i where i.id = invoice_id and public.is_org_member(i.organization_id))) with check (exists (select 1 from public.invoices i where i.id = invoice_id and public.is_org_member(i.organization_id)));
create policy "members can access payments" on public.payments for select using (exists (select 1 from public.invoices i where i.id = invoice_id and public.is_org_member(i.organization_id)));
create policy "members can access invoice events" on public.invoice_events for select using (exists (select 1 from public.invoices i where i.id = invoice_id and public.is_org_member(i.organization_id)));

grant execute on function public.create_organization(text, char) to authenticated;
