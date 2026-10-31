-- ============================================================
-- Ghar / Flat 6 Cleaners — ADMIN TOOLS (v5)
-- Run this ONCE in Supabase Dashboard → SQL Editor → paste ALL → Run.
-- Safe to re-run.
--
-- What this does
--   Admins can take a flatmate off cleaning or the kitchen. The kitchen
--    switch used to write to the read-only flatmates table, which
--    Supabase blocks silently, so nothing changed.
--   Admins can rename flatmates and mark them as moved out. History
--    stays, and a moved-out flatmate's login is deleted.
--   Admins can edit a user's username and linked flatmate.
-- ============================================================

begin;

alter table flatmates add column if not exists in_rotation boolean not null default true;
alter table flatmates add column if not exists archived    boolean not null default false;

-- Any argument left NULL stays as it is.
create or replace function admin_update_flatmate(p_token text, p_id bigint, p_name text default null,
  p_in_rotation boolean default null, p_in_kitchen boolean default null, p_archived boolean default null)
returns void language plpgsql security definer set search_path = public as $$
declare a users%rowtype; f flatmates%rowtype; clean_name text;
begin
  a := _require_admin(p_token);
  select * into f from flatmates where id = p_id;
  if not found then raise exception 'Flatmate not found'; end if;

  if p_name is not null then
    clean_name := btrim(p_name);
    if length(clean_name) < 2 or length(clean_name) > 80 then
      raise exception 'Flatmate name must be 2–80 characters';
    end if;
    if exists (select 1 from flatmates where lower(name) = lower(clean_name) and id <> p_id) then
      raise exception 'Flatmate already exists';
    end if;
    update flatmates set name = clean_name where id = p_id;
    insert into audit_log(action) values (a.username || ' renamed ' || f.name || ' to ' || clean_name);
  end if;

  if p_archived is true and not f.archived then
    p_in_rotation := false;
    p_in_kitchen := false;
    delete from users where flatmate_id = p_id and not is_admin;
    insert into audit_log(action) values (a.username || ' marked ' || f.name || ' as moved out');
  elsif p_archived is false and f.archived then
    insert into audit_log(action) values (a.username || ' restored ' || f.name);
  end if;

  update flatmates set
    in_rotation = coalesce(p_in_rotation, in_rotation),
    in_kitchen  = coalesce(p_in_kitchen, in_kitchen),
    archived    = coalesce(p_archived, archived)
  where id = p_id;

  if not exists (select 1 from flatmates where in_rotation and not archived) then
    raise exception 'At least one person must stay on the cleaning rota';
  end if;
  if not exists (select 1 from flatmates where in_kitchen and not archived) then
    raise exception 'At least one kitchen member is required';
  end if;

  if p_in_rotation is not null and p_in_rotation is distinct from f.in_rotation and p_archived is not true then
    insert into audit_log(action) values (a.username || (case when p_in_rotation
      then ' added ' || f.name || ' to the cleaning rota' else ' removed ' || f.name || ' from the cleaning rota' end));
  end if;
  if p_in_kitchen is not null and p_in_kitchen is distinct from f.in_kitchen and p_archived is not true then
    insert into audit_log(action) values (a.username || (case when p_in_kitchen
      then ' added ' || f.name || ' to the kitchen' else ' removed ' || f.name || ' from the kitchen' end));
  end if;
end $$;

create or replace function admin_update_user(p_token text, p_user_id bigint, p_username text, p_flatmate_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare a users%rowtype; t users%rowtype;
begin
  a := _require_admin(p_token);
  select * into t from users where id = p_user_id;
  if not found then raise exception 'User not found'; end if;
  p_username := lower(trim(p_username));
  if p_username !~ '^[a-z0-9_.-]{2,20}$' then
    raise exception 'Username must be 2–20 letters, numbers, dots, dashes or underscores';
  end if;
  if exists (select 1 from users where lower(username) = p_username and id <> p_user_id) then
    raise exception 'Username already exists';
  end if;
  -- the old sha256 hash includes the username, so renaming would lock them out
  if t.is_admin and t.pass_hash not like '$2%' and p_username <> lower(t.username) then
    raise exception 'This admin must log in once before they can be renamed';
  end if;
  if p_flatmate_id is not null and not exists (select 1 from flatmates where id = p_flatmate_id) then
    raise exception 'Flatmate not found';
  end if;
  update users set username = p_username, flatmate_id = p_flatmate_id where id = p_user_id;
  insert into audit_log(action) values (a.username || ' updated user ' || p_username);
end $$;

grant execute on function admin_update_flatmate(text, bigint, text, boolean, boolean, boolean) to anon;
grant execute on function admin_update_user(text, bigint, text, bigint) to anon;

notify pgrst, 'reload schema';

commit;
