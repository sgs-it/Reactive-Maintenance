CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  email text NOT NULL UNIQUE,
  password_hash text NOT NULL,
  role text NOT NULL CHECK (role IN ('foreman','supervisor','engineer','manager','client')),
  active boolean NOT NULL DEFAULT true
);
CREATE TABLE IF NOT EXISTS sessions (
  token_hash text PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at timestamptz NOT NULL
);
ALTER TABLE users ADD COLUMN IF NOT EXISTS auth_user_id uuid UNIQUE;
ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS managed_by uuid REFERENCES users(id);
CREATE INDEX IF NOT EXISTS users_by_manager ON users(managed_by) WHERE managed_by IS NOT NULL;
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS auth_session_id uuid;
-- Preserve historical records and disable the old shared-password accounts.
UPDATE users SET active=false WHERE active AND lower(email) LIKE '%@rmcs.demo';
CREATE SEQUENCE IF NOT EXISTS job_number;
CREATE SEQUENCE IF NOT EXISTS complaint_number;
CREATE TABLE IF NOT EXISTS jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  site text NOT NULL,
  location text NOT NULL,
  emirate text NOT NULL,
  client_name text NOT NULL,
  created_by uuid NOT NULL REFERENCES users(id),
  companycam_project_id text UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS job_access (
  job_id uuid NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  PRIMARY KEY (job_id,user_id)
);
CREATE INDEX IF NOT EXISTS job_access_by_user ON job_access(user_id,job_id);
ALTER TABLE job_access ADD COLUMN IF NOT EXISTS visible_from timestamptz;
ALTER TABLE job_access ADD COLUMN IF NOT EXISTS visible_until timestamptz;
CREATE OR REPLACE VIEW active_job_access WITH (security_invoker = true) AS
  SELECT job_id,user_id,visible_from,visible_until FROM job_access
  WHERE (visible_from IS NULL OR visible_from <= now())
    AND (visible_until IS NULL OR visible_until > now());
CREATE TABLE IF NOT EXISTS complaints (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  job_id uuid NOT NULL REFERENCES jobs(id),
  title text NOT NULL,
  description text NOT NULL,
  category text NOT NULL,
  priority text NOT NULL CHECK (priority IN ('Critical','High','Medium','Low')),
  reported_by text NOT NULL,
  required_action text NOT NULL DEFAULT '',
  assigned_to uuid REFERENCES users(id),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','assigned','in_progress','on_hold','verification','rework','engineer_review','closed')),
  progress integer NOT NULL DEFAULT 0 CHECK (progress BETWEEN 0 AND 100),
  received_at timestamptz NOT NULL DEFAULT now(),
  due_on date NOT NULL,
  created_by uuid NOT NULL REFERENCES users(id),
  closed_at timestamptz,
  closed_by uuid REFERENCES users(id),
  resolution text,
  CHECK ((status = 'closed') = (closed_at IS NOT NULL AND closed_by IS NOT NULL AND resolution IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS complaints_by_job ON complaints(job_id, received_at DESC);
CREATE TABLE IF NOT EXISTS complaint_history (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  complaint_id uuid NOT NULL REFERENCES complaints(id),
  actor_id uuid NOT NULL REFERENCES users(id),
  action text NOT NULL,
  status text NOT NULL,
  remarks text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE complaint_history ADD COLUMN IF NOT EXISTS assignment jsonb;
CREATE INDEX IF NOT EXISTS history_by_complaint ON complaint_history(complaint_id, id DESC);
CREATE TABLE IF NOT EXISTS photos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  complaint_id uuid NOT NULL REFERENCES complaints(id),
  uploader_id uuid NOT NULL REFERENCES users(id),
  uploader_role text NOT NULL,
  stage text NOT NULL CHECK (stage IN ('Before','Progress','After')),
  provider_id text NOT NULL UNIQUE,
  approved_by uuid REFERENCES users(id),
  approved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS photo_uploads (
  request_id text PRIMARY KEY,
  complaint_id uuid NOT NULL REFERENCES complaints(id),
  uploader_id uuid NOT NULL REFERENCES users(id),
  stage text NOT NULL,
  checksum text NOT NULL,
  photo_id uuid REFERENCES photos(id),
  UNIQUE (complaint_id,uploader_id,stage,checksum)
);

-- RMCS authorizes users in Node. Keep these tables unavailable to Data API roles.
-- The database role that owns the tables can still access them directly.
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE job_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE complaints ENABLE ROW LEVEL SECURITY;
ALTER TABLE complaint_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE photo_uploads ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON users,sessions,jobs,job_access,active_job_access,complaints,complaint_history,photos,photo_uploads FROM PUBLIC;
REVOKE ALL ON SEQUENCE job_number,complaint_number,complaint_history_id_seq FROM PUBLIC;

DO $$
DECLARE api_role name;
BEGIN
  FOR api_role IN SELECT rolname FROM pg_roles WHERE rolname IN ('anon','authenticated','service_role')
  LOOP
    EXECUTE format('REVOKE ALL ON users,sessions,jobs,job_access,active_job_access,complaints,complaint_history,photos,photo_uploads FROM %I', api_role);
    EXECUTE format('REVOKE ALL ON SEQUENCE job_number,complaint_number,complaint_history_id_seq FROM %I', api_role);
  END LOOP;
END $$;

CREATE TABLE IF NOT EXISTS project_photo_uploads (
  request_id text PRIMARY KEY,
  job_id uuid NOT NULL REFERENCES jobs(id),
  uploader_id uuid NOT NULL REFERENCES users(id),
  stage text NOT NULL CHECK (stage IN ('Before','Progress','After')),
  checksum text NOT NULL,
  photo_id text UNIQUE,
  UNIQUE(job_id,uploader_id,stage,checksum)
);
ALTER TABLE project_photo_uploads ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON project_photo_uploads FROM PUBLIC;
