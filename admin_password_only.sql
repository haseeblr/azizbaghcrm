-- ============================================================
-- Ghar / Flat 6 Cleaners — ADMIN-ONLY PASSWORDS (v4)
-- Run this ONCE in Supabase Dashboard → SQL Editor → paste ALL → Run,
-- BEFORE deploying the matching index.html. Run it on a database that
-- already has security_upgrade_v3.sql applied. Safe to re-run.
--
-- What this does
--   Flatmates (non-admins) log in with their username only.
--   Their stored passwords are ERASED — this cannot be undone.
--   Admins still need their password, with the same rate limiting.
--   Making someone an admin now requires setting a password for
--    them and logs them out, so nobody becomes an admin through a
--    session that was opened without a password.
--   Fixes a login bypass: a NULL password used to be accepted for
--    any account, including admins.
-- ============================================================

begin;

-- Stored instead of a hash for accounts with no password. It can never
-- match a bcrypt or sha256 hash, so no password verifies against it.
update users set pass_hash = '!', must_change = false
 where not is_admin;

-- ---------- password check ----------
-- NULL-safe: crypt()/digest() return NULL for a NULL password, and
-- "NULL <> hash" is not true, so a plain mismatch test lets NULL through.
create or replace function _password_ok(p_user users, p_password text)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if p_password is null or p_password = '' then
    return false;
  end if;
  if p_user.pass_hash like '$2%' then
    return extensions.crypt(p_password, p_user.pass_hash) = p_user.pass_hash;
  end if;
  -- legacy sha256 from v2
  return encode(extensions.digest(p_user.username || ':' || p_password, 'sha256'), 'hex') = p_user.pass_hash;
end $$;

revoke all on function _password_ok(users, text) from public, anon, authenticated;

-- ---------- auth functions ----------

-- NOTE auth failures are RETURNED as {error ...} rather than raised,
-- because a raised exception would roll back the login_attempts insert
-- and defeat the rate limiting.
create or replace function auth_login(p_username text, p_password text)
returns json language plpgsql security definer set search_path = public as $$
declare u users%rowtype; tok text; fails int;
begin
  p_username = lower(trim(p_username));

  select count(*) into fails from login_attempts
   where username = p_username and ts > now() - interval '15 minutes';
  if fails >= 5 then
    return json_build_object('error', 'Too many failed attempts — try again in 15 minutes');
  end if;

  select * into u from users where lower(username) = p_username;
  if not found then
    insert into login_attempts(username) values (p_username);
    return json_build_object('error', 'Wrong username or password');
  end if;

  -- only admins have passwords; flatmates are let in on their username
  if u.is_admin then
    if not _password_ok(u, p_password) then
      insert into login_attempts(username) values (p_username);
      return json_build_object('error', 'Wrong username or password');
    end if;
    if u.pass_hash not like '$2%' then
      -- legacy sha256 from v2: upgrade to bcrypt in place
      update users set pass_hash = extensions.crypt(p_password, extensions.gen_salt('bf')) where id = u.id;
    end if;
  end if;

  delete from login_attempts where username = p_username;
  delete from sessions where expires_at < now();

  tok = encode(extensions.gen_random_bytes(32), 'hex');
  insert into sessions(token, user_id) values (tok, u.id);

  return json_build_object('token', tok, 'user', json_build_object(
    'id', u.id, 'username', u.username, 'flatmate_id', u.flatmate_id,
    'is_admin', u.is_admin, 'must_change', u.must_change));
end $$;

create or replace function auth_change_password(p_token text, p_old text, p_new text)
returns void language plpgsql security definer set search_path = public as $$
declare u users%rowtype;
begin
  u = _session_user(p_token);
  if not u.is_admin then
    raise exception 'Only admins have passwords';
  end if;
  if not _password_ok(u, p_old) then
    raise exception 'Current password is wrong';
  end if;
  perform _check_password(u.username, p_new);
  update users set pass_hash = extensions.crypt(p_new, extensions.gen_salt('bf')), must_change = false
   where id = u.id;
  insert into audit_log(action) values (u.username || ' changed their password');
end $$;

-- ---------- admin functions (token verified server-side) ----------

create or replace function admin_create_user(p_token text, p_username text,
  p_password text, p_flatmate_id int, p_is_admin boolean)
returns void language plpgsql security definer set search_path = public as $$
declare a users%rowtype; h text = '!';
begin
  a = _require_admin(p_token);
  p_username = lower(trim(p_username));
  p_is_admin = coalesce(p_is_admin, false);
  if p_username !~ '^[a-z0-9_.-]{2,20}$' then
    raise exception 'Username must be 2–20 letters, numbers, dots, dashes or underscores';
  end if;
  if exists (select 1 from users where lower(username) = p_username) then
    raise exception 'Username already exists';
  end if;
  if p_is_admin then
    perform _check_password(p_username, p_password);
    h = extensions.crypt(p_password, extensions.gen_salt('bf'));
  end if;
  insert into users(username, pass_hash, flatmate_id, is_admin, must_change)
  values (p_username, h, p_flatmate_id, p_is_admin, p_is_admin);
  insert into audit_log(action) values (a.username || ' created user ' || p_username);
end $$;

create or replace function admin_reset_password(p_token text, p_user_id bigint, p_password text)
returns void language plpgsql security definer set search_path = public as $$
declare a users%rowtype; t users%rowtype;
begin
  a = _require_admin(p_token);
  select * into t from users where id = p_user_id;
  if not found then raise exception 'User not found'; end if;
  if not t.is_admin then raise exception 'Only admins have passwords'; end if;
  perform _check_password(t.username, p_password);
  update users set pass_hash = extensions.crypt(p_password, extensions.gen_salt('bf')), must_change = true
   where id = p_user_id;
  delete from sessions where user_id = p_user_id; -- log them out everywhere
  insert into audit_log(action) values (a.username || ' reset password for ' || t.username);
end $$;

-- p_password is new, so the old 3-argument version has to go or the two
-- overloads would sit side by side.
drop function if exists admin_set_admin(text, bigint, boolean);

create or replace function admin_set_admin(p_token text, p_user_id bigint, p_is_admin boolean,
  p_password text default null)
returns void language plpgsql security definer set search_path = public as $$
declare a users%rowtype; t users%rowtype;
begin
  a = _require_admin(p_token);
  select * into t from users where id = p_user_id;
  if not found then raise exception 'User not found'; end if;
  if p_is_admin = t.is_admin then return; end if;
  if p_is_admin then
    perform _check_password(t.username, p_password);
    update users set is_admin = true, must_change = true,
      pass_hash = extensions.crypt(p_password, extensions.gen_salt('bf'))
     where id = p_user_id;
    delete from sessions where user_id = p_user_id; -- their open session had no password
  else
    if (select count(*) from users where is_admin) = 1 then
      raise exception 'Cannot remove the last admin';
    end if;
    update users set is_admin = false, must_change = false, pass_hash = '!'
     where id = p_user_id;
  end if;
  insert into audit_log(action) values (a.username || (case when p_is_admin
    then ' made admin ' else ' removed admin from ' end) || t.username);
end $$;

grant execute on function admin_set_admin(text, bigint, boolean, text) to anon;

commit;
