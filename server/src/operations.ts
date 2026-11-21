import { db, transaction } from './db.ts';
import { clientStatus, nextStatus, RequestError, uaeDate } from './workflow.ts';
import type { Status, User } from './workflow.ts';
import type { Pool, PoolClient } from 'pg';

export type Input = Record<string, unknown>;
export function field(input: Input, name: string, max: number, required = true) {
  const value = input[name];
  if (value === undefined && !required) return '';
  if (typeof value !== 'string' || value.trim().length > max || (required && !value.trim())) {
    throw new RequestError(400, `Enter a valid ${name.replaceAll('_', ' ')}.`);
  }
  return value.trim();
}

function dueDate(input: Input) {
  const value = field(input, 'due_on', 10);
  const date = new Date(value + 'T00:00:00Z');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || !Number.isFinite(date.getTime()) ||
      date.toISOString().slice(0, 10) !== value || value < uaeDate()) {
    throw new RequestError(400, 'Enter a valid target date on or after today (UAE).');
  }
  return value;
}

export function requireRole(user: User, allowed: User['role'][]) {
  if (!allowed.includes(user.role)) throw new RequestError(403, 'Your role does not allow this action.');
}

export function uuid(value: string) {
  if (!/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(value)) {
    throw new RequestError(404, 'Record not found.');
  }
  return value;
}

export async function jobFor(user: User, jobId: string, connection: Pool | PoolClient = db) {
  const { rows: [job] } = await connection.query<{ id: string; code: string; site: string; companycam_project_id: string | null }>(`
    SELECT j.* FROM jobs j JOIN active_job_access a ON a.job_id=j.id
    WHERE j.id=$1 AND a.user_id=$2`, [uuid(jobId), user.id]);
  if (!job) throw new RequestError(404, 'Job not found.');
  return job;
}

export async function createJob(user: User, input: Input) {
  requireRole(user, ['engineer', 'manager']);
  const site = field(input, 'site', 160);
  const location = field(input, 'location', 240);
  const emirate = field(input, 'emirate', 60);
  const client = field(input, 'client_name', 160);
  return transaction(async (connection) => {
    const { rows: [job] } = await connection.query(`
      INSERT INTO jobs (code,site,location,emirate,client_name,created_by)
      VALUES ($1 || nextval('job_number'),$2,$3,$4,$5,$6) RETURNING id,code`,
    [`JOB-${uaeDate().slice(0, 4)}-`, site, location, emirate, client, user.id]);
    await connection.query('INSERT INTO job_access (job_id,user_id) VALUES ($1,$2)', [job.id, user.id]);
    return job;
  });
}

export async function grantJobAccess(user: User, jobId: string, input: Input) {
  requireRole(user, ['engineer', 'manager']);
  const email = field(input, 'email', 254).toLowerCase();
  await jobFor(user, jobId);
  const { rowCount } = await db.query(`
    INSERT INTO job_access (job_id,user_id,visible_until)
    SELECT own.job_id,u.id,own.visible_until FROM users u
    JOIN active_job_access own ON own.job_id=$1 AND own.user_id=$3
    WHERE u.email=$2 AND u.active
    ON CONFLICT DO NOTHING`, [jobId, email, user.id]);
  if (!rowCount) {
    const { rowCount: existing } = await db.query(`
      SELECT 1 FROM job_access a JOIN users u ON u.id=a.user_id
      WHERE a.job_id=$1 AND u.email=$2 AND u.active`, [jobId, email]);
    if (!existing) throw new RequestError(404, 'No active account uses that email.');
  }
  return { granted: true };
}

export async function createComplaint(user: User, input: Input) {
  requireRole(user, ['foreman', 'supervisor', 'engineer', 'manager', 'client']);
  const jobId = field(input, 'job_id', 36);
  const priority = field(input, 'priority', 12);
  if (!['Critical', 'High', 'Medium', 'Low'].includes(priority)) throw new RequestError(400, 'Choose a priority.');
  return transaction(async (connection) => {
    await jobFor(user, jobId, connection);
    const { rows: [complaint] } = await connection.query(`
      INSERT INTO complaints (code,job_id,title,description,category,priority,reported_by,required_action,due_on,created_by)
      VALUES ($1 || nextval('complaint_number'),$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id,code`, [
      `RM-${uaeDate().slice(0, 4)}-`, jobId, field(input, 'title', 160), field(input, 'description', 4000),
      input.category === 'Other' ? 'Other: ' + field(input, 'other_category', 73) : field(input, 'category', 80), priority, user.name,
      field(input, 'required_action', 2000, false), dueDate(input), user.id,
    ]);
    await connection.query(`INSERT INTO complaint_history (complaint_id,actor_id,action,status)
      VALUES ($1,$2,'register','open')`, [complaint.id, user.id]);
    return complaint;
  });
}

export async function changeComplaint(user: User, id: string, input: Input) {
  const action = field(input, 'action', 20);
  return transaction(async (connection) => {
    const { rows: [complaint] } = await connection.query<{
      id: string; job_id: string; status: Status; assigned_to: string | null; progress: number;
    }>(`SELECT c.id,c.job_id,c.status,c.assigned_to,c.progress FROM complaints c
      JOIN active_job_access a ON a.job_id=c.job_id WHERE c.id=$1 AND a.user_id=$2 FOR UPDATE OF c`, [uuid(id), user.id]);
    if (!complaint) throw new RequestError(404, 'Service request not found.');
    const status = nextStatus(action, complaint.status, user, complaint.assigned_to);
    const remarks = field(input, 'remarks', 2000, ['update', 'hold', 'rework', 'close', 'reopen'].includes(action));
    let assignment = null;
    let assignee = complaint.assigned_to;
    let progress = complaint.progress;
    if (action === 'assign') {
      assignee = uuid(field(input, 'assigned_to', 36));
      const role = user.role === 'engineer' ? 'supervisor' : 'foreman';
      const { rows: [target] } = await connection.query(`SELECT u.name FROM active_job_access a JOIN users u ON u.id=a.user_id
        WHERE a.job_id=$1 AND a.user_id=$2 AND u.active AND u.role=$3`, [complaint.job_id, assignee, role]);
      if (!target) throw new RequestError(400, `Choose a ${role} with current project access.`);
      assignment = { from_id: user.id, from_name: user.name, from_role: user.role,
        to_id: assignee, to_name: target.name, to_role: role };

    }
    if (action === 'update') {
      const value = input.progress;
      if (typeof value !== 'number' || !Number.isInteger(value) || value < 0 || value > 100) {
        throw new RequestError(400, 'Progress must be a whole percentage from 0 to 100.');
      }
      progress = value;
    }
    if (action === 'submit') progress = 100;
    if (action === 'rework' || action === 'reopen') progress = Math.min(progress, 99);
    await connection.query(`UPDATE complaints SET status=$2,progress=$3,assigned_to=$4,
      closed_at=CASE WHEN $2='closed' THEN now() END,
      closed_by=CASE WHEN $2='closed' THEN $5::uuid END,
      resolution=CASE WHEN $2='closed' THEN $6::text END WHERE id=$1`,
    [id, status, progress, assignee, user.id, remarks]);
    await connection.query(`INSERT INTO complaint_history (complaint_id,actor_id,action,status,remarks,assignment)
      VALUES ($1,$2,$3,$4,$5,$6)`, [id, user.id, action, status, remarks, assignment]);
    return { id, status };
  });
}

export async function workspace(user: User) {
  const { rows: [schedule] } = await db.query<{ next_access_change: Date | null }>(`
    SELECT min(boundary) AS next_access_change FROM job_access a
    CROSS JOIN LATERAL (VALUES (a.visible_from),(a.visible_until)) times(boundary)
    WHERE a.user_id=$1 AND boundary > now()`, [user.id]);
  const { rows: jobs } = await db.query(`SELECT j.id,j.code,j.site,j.location,j.emirate,j.client_name,
    (j.companycam_project_id IS NOT NULL) AS photos_linked
    FROM jobs j JOIN active_job_access a ON a.job_id=j.id WHERE a.user_id=$1 ORDER BY j.created_at DESC`, [user.id]);
  const { rows: complaints } = await db.query(`
    SELECT c.id,c.code,c.job_id,c.title,c.category,c.priority,c.description,c.reported_by,c.required_action,
      c.status,c.progress,c.received_at,c.due_on::text,c.assigned_to,u.name AS assignee,
      c.created_by=$1 AS requested_by_me,
      EXISTS(SELECT 1 FROM complaint_history h WHERE h.complaint_id=c.id AND h.action='assign' AND h.actor_id=$1) AS assigned_by_me,
      EXISTS(SELECT 1 FROM complaint_history h WHERE h.complaint_id=c.id AND h.assignment->>'to_id'=($1::uuid)::text) AS received_by_me,
      CASE c.status WHEN 'closed' THEN NULL WHEN 'verification' THEN chain.assignment->>'to_name'
        WHEN 'engineer_review' THEN chain.assignment->>'from_name' ELSE u.name END AS responsible,
      CASE c.status WHEN 'closed' THEN NULL WHEN 'verification' THEN chain.assignment->>'to_id'
        WHEN 'engineer_review' THEN chain.assignment->>'from_id' ELSE u.id::text END=($1::uuid)::text AS my_responsibility,
      CASE c.status WHEN 'verification' THEN 'supervisor' WHEN 'engineer_review' THEN 'engineer'
        WHEN 'open' THEN 'engineer' ELSE u.role END AS responsible_role,
      c.closed_at,c.resolution,
      GREATEST(0, (COALESCE(c.closed_at,now()) AT TIME ZONE 'Asia/Dubai')::date -
        (c.received_at AT TIME ZONE 'Asia/Dubai')::date) AS days_open,
      (c.status <> 'closed' AND c.due_on < (now() AT TIME ZONE 'Asia/Dubai')::date) AS overdue,
      (c.status <> 'closed' AND c.due_on = (now() AT TIME ZONE 'Asia/Dubai')::date) AS due_today,
      (c.status <> 'closed' AND c.due_on = (now() AT TIME ZONE 'Asia/Dubai')::date + 1) AS due_tomorrow
    FROM complaints c JOIN active_job_access a ON a.job_id=c.job_id
    LEFT JOIN LATERAL (SELECT h.assignment FROM complaint_history h WHERE h.complaint_id=c.id
      AND h.assignment->>'from_role'='engineer' ORDER BY h.id DESC LIMIT 1) chain ON true
    LEFT JOIN users u ON u.id=c.assigned_to
    WHERE a.user_id=$1 ORDER BY c.received_at DESC`, [user.id]);
  if (user.role === 'client') {
    return { ...schedule, jobs: jobs.map(({ photos_linked, ...job }) => job), complaints: complaints.map(
      ({ id, code, job_id, title, category, status, received_at, closed_at, days_open, responsible, responsible_role, requested_by_me }) =>
        ({ id, code, job_id, title, category, status: clientStatus(status), received_at, closed_at, days_open, responsible, responsible_role, requested_by_me }),
    ) };
  }
  const { rows: staff } = await db.query<{ id: string; name: string }>(`
    SELECT DISTINCT u.id,u.name
    FROM active_job_access own
    JOIN active_job_access colleague ON colleague.job_id=own.job_id
    JOIN users u ON u.id=colleague.user_id
    WHERE own.user_id=$1 AND u.active AND u.role <> 'client'
    ORDER BY u.name,u.id`, [user.id]);
  const failures = ['engineer','manager'].includes(user.role) ? (await db.query(`
    SELECT c.id, count(*)::int AS failures FROM complaint_history h
    JOIN complaints c ON c.id=h.complaint_id
    JOIN active_job_access a ON a.job_id=c.job_id AND a.user_id=$1
    WHERE h.action='upload_failure' AND h.created_at > now()-interval '24 hours'
    GROUP BY c.id HAVING count(*) >= 2`, [user.id])).rows : [];
  return { ...schedule, jobs, complaints, staff, upload_alerts: failures };
}

export async function complaintDetails(user: User, id: string) {
  const { rows: [complaint] } = await db.query(`
    SELECT c.id,c.job_id,c.status,(j.companycam_project_id IS NOT NULL) AS photos_linked
    FROM complaints c JOIN jobs j ON j.id=c.job_id JOIN active_job_access a ON a.job_id=c.job_id
    WHERE c.id=$1 AND a.user_id=$2`, [uuid(id), user.id]);
  if (!complaint) throw new RequestError(404, 'Service request not found.');
  const { rows: assignments } = await db.query(`SELECT h.created_at, h.actor_id, u.name AS actor, h.assignment
    FROM complaint_history h JOIN users u ON u.id=h.actor_id
    WHERE h.complaint_id=$1 AND h.action='assign' ORDER BY h.id DESC`, [id]);
  if (user.role === 'client') {
    const { rows: photos } = await db.query(`
      SELECT id,stage,created_at FROM photos WHERE complaint_id=$1 AND approved_at IS NOT NULL
        AND $2='closed' AND stage IN ('Before','After') ORDER BY created_at DESC`, [id, complaint.status]);
    return { photos, assignments };
  }
  const [{ rows: history }, { rows: staff }, { rows: photos }] = await Promise.all([
    db.query(`SELECT h.action,h.status,h.remarks,h.created_at,u.name AS actor
      FROM complaint_history h JOIN users u ON u.id=h.actor_id WHERE h.complaint_id=$1 ORDER BY h.id DESC`, [id]),
    db.query(`SELECT u.id,u.name,u.role FROM users u JOIN active_job_access a ON a.user_id=u.id
      WHERE a.job_id=$1 AND u.active AND u.role <> 'client' ORDER BY u.name`, [complaint.job_id]),
    db.query(`SELECT p.id,p.stage,p.uploader_role,p.approved_at,p.created_at,u.name AS uploader
      FROM photos p JOIN users u ON u.id=p.uploader_id WHERE p.complaint_id=$1 ORDER BY p.created_at DESC`, [id]),
  ]);
  return { history, staff, assignments, photos, photos_linked: complaint.photos_linked };
}
