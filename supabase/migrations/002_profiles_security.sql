-- Apply after 001_core.sql. Profiles contain account metadata and must not be public.
alter table public.profiles enable row level security;

create policy "users can read their own profile"
on public.profiles for select using (auth.uid() = id);

create policy "users can create their own profile"
on public.profiles for insert with check (auth.uid() = id);

create policy "users can update their own profile"
on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);
