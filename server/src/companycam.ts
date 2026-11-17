import { createHash } from 'node:crypto';
import { db, transaction } from './db.ts';
import { jobFor, requireRole, uuid } from './operations.ts';
import { RequestError } from './workflow.ts';
import type { User } from './workflow.ts';

const apiOrigin = 'https://app.companycam.com/public_api/v1';
const maxPhotoBytes = 10 * 1024 * 1024;
const imageTypes: Record<string, string> = {
  'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp',
};

class ProviderError extends RequestError {
  providerStatus: number;
  constructor(providerStatus: number) {
    super(502, 'CompanyCam could not complete this request.');
    this.providerStatus = providerStatus;
  }
}

function key() {
  const value = process.env.COMPANYCAM_KEY;
  if (!value) throw new RequestError(503, 'CompanyCam is not configured on this server.');
  return value;
}

async function companyCam<T>(path: string, body?: object): Promise<T> {
  const result = await fetch(apiOrigin + path, {
    method: body ? 'POST' : 'GET',
    headers: {
      Authorization: `Bearer ${key()}`, Accept: 'application/json',
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
    redirect: 'error',
    signal: AbortSignal.timeout(15_000),
  }).catch(() => { throw new ProviderError(0); });
  if (!result.ok) {
    await result.body?.cancel();
    throw new ProviderError(result.status);
  }
  const { data } = await result.json() as { data: T };
  if (!data) throw new ProviderError(0);
  return data;
}

function storageUrl(input: string) {
  const url = new URL(input);
  if (url.protocol !== 'https:' || url.port || url.username || url.password ||
      !/(^|\.)(companycam\.com|companycam\.net|amazonaws\.com|cloudfront\.net)$/i.test(url.hostname)) {
    throw new ProviderError(0);
  }
  return url;
}

export async function linkProject(user: User, jobId: string) {
  requireRole(user, ['engineer']);
  key();
  return transaction(async (connection) => {
    await jobFor(user, jobId, connection);
    const { rows: [job] } = await connection.query(`
      SELECT id,code,site,location,emirate,companycam_project_id FROM jobs WHERE id=$1 FOR UPDATE`, [jobId]);
    if (job.companycam_project_id) return { linked: true };
    const project = await companyCam<{ id: string }>('/projects', {
      project: {
        name: `${job.code} · ${job.site} [${job.id}]`,
        street_address_1: job.location,
        city: job.emirate,
        state: job.emirate,
        postal_code: '00000',
        country: 'AE',
      },
    });
    if (!/^\d+$/.test(project.id)) throw new ProviderError(0);
    await connection.query('UPDATE jobs SET companycam_project_id=$2 WHERE id=$1', [jobId, project.id]);
    return { linked: true };
  });
}

type Photo = { id: string; project_id: string; uris: { type: string; url: string }[] };

async function prepareUpload(bytes: Buffer, mime: string, requestId: string) {
  const upload = await companyCam<{ upload_id: string; upload_url: string; method: string; headers: Record<string, string> }>('/uploads', {
    upload: {
      filename: `rmcs-${requestId}.${imageTypes[mime]}`,
      content_type: mime,
      checksum: createHash('md5').update(bytes).digest('base64'),
    },
  });
  if (upload.method.toUpperCase() !== 'PUT') throw new ProviderError(0);
  const result = await fetch(storageUrl(upload.upload_url), {
    method: 'PUT', headers: upload.headers, body: new Uint8Array(bytes),
    signal: AbortSignal.timeout(30_000), redirect: 'error',
  }).catch(() => { throw new ProviderError(0); });
  await result.body?.cancel();
  if (!result.ok) throw new ProviderError(result.status);
  return upload.upload_id;
}

export async function uploadPhoto(user: User, complaintId: string, stage: string, mime: string,
                                  requestId: string, read: (limit: number) => Promise<Buffer>) {
  requireRole(user, ['engineer', 'manager', 'supervisor', 'foreman']);
  if (!/^[a-f0-9]{48}$/.test(requestId)) throw new RequestError(400, 'Missing photo upload reference.');
  if (!['Before', 'Progress', 'After'].includes(stage) || !Object.hasOwn(imageTypes, mime)) {
    throw new RequestError(400, 'Choose a Before, Progress or After photo in JPEG, PNG or WebP format.');
  }
  const { rows: [complaint] } = await db.query(`
    SELECT c.code,c.status,j.companycam_project_id FROM complaints c JOIN jobs j ON j.id=c.job_id
    JOIN job_access a ON a.job_id=j.id WHERE c.id=$1 AND a.user_id=$2`, [uuid(complaintId), user.id]);
  if (!complaint) throw new RequestError(404, 'Service request not found.');
  if (complaint.status === 'closed') throw new RequestError(409, 'Reopen the request before adding photos.');
  if (!complaint.companycam_project_id) throw new RequestError(409, 'Link this RM job to CompanyCam before uploading.');
  key();
  const bytes = await read(maxPhotoBytes);
  const valid = mime === 'image/jpeg' ? bytes.subarray(0, 3).equals(Buffer.from([255, 216, 255]))
    : mime === 'image/png' ? bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
    : bytes.subarray(0, 4).toString() === 'RIFF' && bytes.subarray(8, 12).toString() === 'WEBP';
  if (!valid) throw new RequestError(400, 'The file does not match its image format.');
  const checksum = createHash('sha256').update(bytes).digest('hex');
  const identity = [complaintId, user.id, stage, checksum];
  const claim = await db.query(`INSERT INTO photo_uploads(request_id,complaint_id,uploader_id,stage,checksum)
    VALUES ($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING`, [requestId, ...identity]);
  if (!claim.rowCount) {
    const { rows: [existing] } = await db.query(`SELECT photo_id FROM photo_uploads
      WHERE complaint_id=$1 AND uploader_id=$2 AND stage=$3 AND checksum=$4`, identity);
    if (existing?.photo_id) return { id: existing.photo_id };
    throw new RequestError(409, 'This upload is pending confirmation. Refresh or ask an administrator to check CompanyCam.');
  }
  let registering = false;
  try {
    const uploadId = await prepareUpload(bytes, mime, requestId);
    registering = true;
    const photo = await companyCam<Photo>(`/projects/${encodeURIComponent(complaint.companycam_project_id)}/photos`, {
      photo: { upload_id: uploadId, description: `${complaint.code} · ${stage} · RMCS upload ${requestId}` },
    });
    if (!/^\d+$/.test(photo.id) || photo.project_id !== complaint.companycam_project_id) throw new ProviderError(0);
    return await transaction(async (connection) => {
      const { rows: [saved] } = await connection.query(`
        INSERT INTO photos(complaint_id,uploader_id,uploader_role,stage,provider_id) VALUES ($1,$2,$3,$4,$5) RETURNING id`,
      [complaintId, user.id, user.role, stage, photo.id]);
      await connection.query('UPDATE photo_uploads SET photo_id=$2 WHERE request_id=$1', [requestId, saved.id]);
      return saved;
    });
  } catch (error) {
    if (!registering || (error instanceof ProviderError && error.providerStatus >= 400 && error.providerStatus < 500)) {
      await db.query('DELETE FROM photo_uploads WHERE request_id=$1 AND photo_id IS NULL', [requestId]);
    }
    throw error;
  }
}

export async function fetchPhoto(user: User, id: string) {
  const { rows: [row] } = await db.query(`
    SELECT p.provider_id,j.companycam_project_id FROM photos p JOIN complaints c ON c.id=p.complaint_id
    JOIN jobs j ON j.id=c.job_id JOIN job_access a ON a.job_id=j.id
    WHERE p.id=$1 AND a.user_id=$2 AND
      ($3 <> 'client' OR (p.approved_at IS NOT NULL AND c.status='closed' AND p.stage IN ('Before','After')))`,
  [uuid(id), user.id, user.role]);
  if (!row) throw new RequestError(404, 'Photo not found.');
  const photo = await companyCam<Photo>(`/photos/${encodeURIComponent(row.provider_id)}`);
  if (photo.project_id !== row.companycam_project_id) throw new RequestError(404, 'Photo not found.');
  const image = photo.uris?.find(({ type }) => type === 'original') ?? photo.uris?.[0];
  if (!image?.url) throw new RequestError(409, 'CompanyCam is still processing this photo.');
  const result = await fetch(storageUrl(image.url), { signal: AbortSignal.timeout(15_000), redirect: 'error' })
    .catch(() => { throw new ProviderError(0); });
  const mime = result.headers.get('content-type')?.split(';')[0] ?? '';
  if (!result.ok || !Object.hasOwn(imageTypes, mime) || !result.body) {
    await result.body?.cancel();
    throw new ProviderError(result.status);
  }
  return { mime, body: result.body };
}

export async function approvePhoto(user: User, id: string) {
  requireRole(user, ['engineer']);
  return transaction(async (connection) => {
    const { rows: [photo] } = await connection.query(`UPDATE photos p SET approved_by=$2,approved_at=now()
      FROM complaints c JOIN job_access a ON a.job_id=c.job_id
      WHERE p.id=$1 AND p.complaint_id=c.id AND a.user_id=$2 AND p.approved_at IS NULL
        AND p.stage IN ('Before','After') RETURNING c.id AS complaint_id,c.status,p.stage`, [uuid(id), user.id]);
    if (!photo) throw new RequestError(404, 'No unapproved Before or After photo was found.');
    await connection.query(`INSERT INTO complaint_history(complaint_id,actor_id,action,status,remarks)
      VALUES ($1,$2,'approve_photo',$3,$4)`, [photo.complaint_id, user.id, photo.status, photo.stage]);
    return { approved: true };
  });
}
