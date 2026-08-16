-- Lets a signed-in person restore a missing profile row for their own account.
-- Safe to run more than once.
drop policy if exists "Users can insert their own missing profile" on public.profiles;

create policy "Users can insert their own missing profile"
on public.profiles
for insert
to authenticated
with check (id = (select auth.uid()));
