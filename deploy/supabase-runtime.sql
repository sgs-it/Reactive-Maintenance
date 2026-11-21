-- Apply as postgres after server/schema.sql has been installed in the rmcs schema.
-- Assign the generated login credential in a separate operation.
CREATE ROLE rmcs_runtime NOLOGIN;
ALTER ROLE rmcs_runtime SET search_path TO rmcs, pg_catalog;

REVOKE ALL ON SCHEMA rmcs FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA rmcs TO rmcs_runtime;

GRANT SELECT ON ALL TABLES IN SCHEMA rmcs TO rmcs_runtime;
GRANT INSERT (name,email,role,auth_user_id,managed_by) ON rmcs.users TO rmcs_runtime;
GRANT UPDATE (name,role,active) ON rmcs.users TO rmcs_runtime;
GRANT INSERT ON rmcs.sessions, rmcs.jobs, rmcs.job_access, rmcs.complaints,
  rmcs.complaint_history, rmcs.photos, rmcs.photo_uploads TO rmcs_runtime;
GRANT UPDATE ON rmcs.jobs, rmcs.complaints, rmcs.photos, rmcs.photo_uploads TO rmcs_runtime;
GRANT UPDATE (visible_from,visible_until), DELETE ON rmcs.job_access TO rmcs_runtime;
GRANT DELETE ON rmcs.sessions, rmcs.photo_uploads TO rmcs_runtime;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA rmcs TO rmcs_runtime;

CREATE POLICY rmcs_runtime_read_users ON rmcs.users
  FOR SELECT TO rmcs_runtime USING (true);
CREATE POLICY rmcs_runtime_insert_managed_users ON rmcs.users
  FOR INSERT TO rmcs_runtime WITH CHECK (managed_by IS NOT NULL AND auth_user_id IS NOT NULL);
CREATE POLICY rmcs_runtime_update_managed_users ON rmcs.users
  FOR UPDATE TO rmcs_runtime USING (managed_by IS NOT NULL) WITH CHECK (managed_by IS NOT NULL);
CREATE POLICY rmcs_runtime_sessions ON rmcs.sessions TO rmcs_runtime USING (true) WITH CHECK (true);
CREATE POLICY rmcs_runtime_jobs ON rmcs.jobs TO rmcs_runtime USING (true) WITH CHECK (true);
CREATE POLICY rmcs_runtime_job_access ON rmcs.job_access TO rmcs_runtime USING (true) WITH CHECK (true);
CREATE POLICY rmcs_runtime_requests ON rmcs.complaints TO rmcs_runtime USING (true) WITH CHECK (true);
CREATE POLICY rmcs_runtime_request_history ON rmcs.complaint_history TO rmcs_runtime USING (true) WITH CHECK (true);
CREATE POLICY rmcs_runtime_photos ON rmcs.photos TO rmcs_runtime USING (true) WITH CHECK (true);
CREATE POLICY rmcs_runtime_uploads ON rmcs.photo_uploads TO rmcs_runtime USING (true) WITH CHECK (true);

CREATE SCHEMA rmcs_auth;
REVOKE ALL ON SCHEMA rmcs_auth FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA rmcs_auth TO rmcs_runtime;

-- These projections run as their owner and expose only access metadata for RMCS users.
CREATE VIEW rmcs_auth.users WITH (security_barrier = true) AS
  SELECT a.id, a.email, a.email_confirmed_at, a.banned_until
  FROM auth.users a JOIN rmcs.users u ON u.auth_user_id = a.id;
CREATE VIEW rmcs_auth.sessions WITH (security_barrier = true) AS
  SELECT s.id, s.user_id, s.not_after
  FROM auth.sessions s JOIN rmcs.users u ON u.auth_user_id = s.user_id;
CREATE VIEW rmcs_auth.mfa_factors WITH (security_barrier = true) AS
  SELECT f.user_id, f.status
  FROM auth.mfa_factors f JOIN rmcs.users u ON u.auth_user_id = f.user_id;
CREATE VIEW rmcs_auth.confirmed_users WITH (security_barrier = true) AS
  SELECT id, lower(email) AS email FROM auth.users
  WHERE email IS NOT NULL AND email_confirmed_at IS NOT NULL
    AND (banned_until IS NULL OR banned_until <= now())
    AND NOT is_anonymous;
REVOKE ALL ON ALL TABLES IN SCHEMA rmcs_auth FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA rmcs_auth TO rmcs_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON rmcs.project_photo_uploads TO rmcs_runtime;
CREATE POLICY rmcs_runtime_project_uploads ON rmcs.project_photo_uploads TO rmcs_runtime USING (true) WITH CHECK (true);
