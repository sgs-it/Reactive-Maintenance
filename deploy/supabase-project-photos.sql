BEGIN;
SET LOCAL search_path TO rmcs, pg_catalog;
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
REVOKE ALL ON project_photo_uploads FROM anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON rmcs.project_photo_uploads TO rmcs_runtime;
CREATE POLICY rmcs_runtime_project_uploads ON rmcs.project_photo_uploads TO rmcs_runtime USING (true) WITH CHECK (true);
COMMIT;
