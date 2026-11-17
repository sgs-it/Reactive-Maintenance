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
