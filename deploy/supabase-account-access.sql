-- Upgrade an existing managed RMCS backend.
ALTER TABLE rmcs.users ADD COLUMN managed_by uuid REFERENCES rmcs.users(id);
CREATE INDEX users_by_manager ON rmcs.users(managed_by) WHERE managed_by IS NOT NULL;
ALTER TABLE rmcs.job_access ADD COLUMN visible_from timestamptz;
ALTER TABLE rmcs.job_access ADD COLUMN visible_until timestamptz;

CREATE VIEW rmcs.active_job_access WITH (security_invoker = true) AS
  SELECT job_id,user_id,visible_from,visible_until FROM rmcs.job_access
  WHERE (visible_from IS NULL OR visible_from <= now())
    AND (visible_until IS NULL OR visible_until > now());
REVOKE ALL ON rmcs.active_job_access FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON rmcs.active_job_access TO rmcs_runtime;
GRANT INSERT (name,email,role,auth_user_id,managed_by) ON rmcs.users TO rmcs_runtime;
GRANT UPDATE (name,role,active) ON rmcs.users TO rmcs_runtime;
GRANT UPDATE (visible_from,visible_until), DELETE ON rmcs.job_access TO rmcs_runtime;

CREATE POLICY rmcs_runtime_insert_managed_users ON rmcs.users
  FOR INSERT TO rmcs_runtime WITH CHECK (managed_by IS NOT NULL AND auth_user_id IS NOT NULL);
CREATE POLICY rmcs_runtime_update_managed_users ON rmcs.users
  FOR UPDATE TO rmcs_runtime USING (managed_by IS NOT NULL) WITH CHECK (managed_by IS NOT NULL);

CREATE VIEW rmcs_auth.confirmed_users WITH (security_barrier = true) AS
  SELECT id, lower(email) AS email FROM auth.users
  WHERE email IS NOT NULL AND email_confirmed_at IS NOT NULL
    AND (banned_until IS NULL OR banned_until <= now())
    AND NOT is_anonymous;
REVOKE ALL ON rmcs_auth.confirmed_users FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON rmcs_auth.confirmed_users TO rmcs_runtime;
