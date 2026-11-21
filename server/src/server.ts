import { createServer } from 'node:http';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { authenticate, changePassword, login } from './auth.ts';
import { createAccount, listAccounts, setAccountJob, updateAccount } from './accounts.ts';
import { checkAuthConfiguration } from './supabase-auth.ts';
import { db, migrate } from './db.ts';
import {
  changeComplaint, complaintDetails, createComplaint, createJob, field,
  grantJobAccess, workspace,
} from './operations.ts';
import type { Input } from './operations.ts';
import { RequestError } from './workflow.ts';
import { approvePhoto, fetchPhoto, linkProject, uploadPhoto } from './companycam.ts';
import { report } from './reports.ts';

const port = Number(process.env.PORT ?? 8080);
const host = process.env.HOST ?? '127.0.0.1';
const web = resolve(process.env.WEB_ROOT ?? fileURLToPath(new URL('../../app/build/web', import.meta.url)));
const loginAttempts = new Map<string, { count: number; reset: number }>();
const loginWindow = 60_000;
const contentTypes: Record<string, string> = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json', '.wasm': 'application/wasm', '.css': 'text/css',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.webp': 'image/webp',
  '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.otf': 'font/otf', '.ttf': 'font/ttf',
};

async function read(req: IncomingMessage, limit: number): Promise<Buffer> {
  let size = 0;
  const chunks = [];
  if (Number(req.headers['content-length']) > limit) throw new RequestError(413, 'This request is too large.');
  for await (const chunk of req) {
    size += chunk.length;
    if (size > limit) throw new RequestError(413, 'This request is too large.');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

async function json(req: IncomingMessage): Promise<Input> {
  const bytes = await read(req, 24_000);
  try {
    const value: unknown = JSON.parse(bytes.toString('utf8'));
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid object');
    return value as Input;
  } catch {
    throw new RequestError(400, 'Send a valid JSON object.');
  }
}

function passwordInput(input: Input, key: string) {
  const value = input[key];
  if (typeof value !== 'string' || value.length === 0 || value.length > 256) {
    throw new RequestError(400, 'Enter a valid password.');
  }
  return value;
}

function respond(res: ServerResponse, value: unknown, status = 200) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(value));
}

function throttle(req: IncomingMessage) {
  const now = Date.now();
  const ip = req.socket.remoteAddress ?? 'local';
  const current = loginAttempts.get(ip);
  if (!current || current.reset < now) {
    for (const [address, attempt] of loginAttempts) {
      if (attempt.reset < now) loginAttempts.delete(address);
    }
    loginAttempts.set(ip, { count: 1, reset: now + loginWindow });
  } else {
    current.count++;
    if (current.count > 25) throw new RequestError(429, 'Too many sign-in attempts. Try again in one minute.');
  }
}

async function serveWeb(path: string, req: IncomingMessage, res: ServerResponse) {
  if (req.method !== 'GET' && req.method !== 'HEAD') throw new RequestError(404, 'Page not found.');
  const file = resolve(web, '.' + decodeURIComponent(path === '/' ? '/index.html' : path));
  if (!file.startsWith(web + sep)) throw new RequestError(404, 'Page not found.');
  const info = await stat(file).catch(() => null);
  if (!info?.isFile()) throw new RequestError(404, 'Page not found. Build the Flutter web app first.');
  res.writeHead(200, {
    'Content-Type': contentTypes[extname(file)] ?? 'application/octet-stream',
    'Cache-Control': 'no-cache',
    'Content-Length': info.size,
  });
  if (req.method === 'HEAD') return res.end();
  createReadStream(file).on('error', () => res.destroy()).pipe(res);
}

let draining = false;
const server = createServer(async (req, res) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('X-Frame-Options', 'DENY');
  try {
    if (draining) {
      res.setHeader('Connection', 'close');
      return respond(res, { ready: false }, 503);
    }
    const url = new URL(req.url ?? '/', 'http://localhost');
    const path = url.pathname;
    const method = req.method;
    if (!path.startsWith('/api/')) return await serveWeb(path, req, res);
    if (method === 'GET' && path === '/api/health') {
      try {
        await db.query('SELECT 1');
      } catch {
        return respond(res, { ready: false }, 503);
      }
      return respond(res, { ready: true });
    }
    if (method === 'POST' && path === '/api/login') {
      throttle(req);
      const input = await json(req);
      return respond(res, await login(field(input, 'email', 254), passwordInput(input, 'password')));
    }
    const { user, tokenHash } = await authenticate(req.headers.authorization);
    if (method === 'GET' && path === '/api/accounts') return respond(res, await listAccounts(user));
    if (method === 'POST' && path === '/api/accounts') return respond(res, await createAccount(user, await json(req)), 201);
    const account = /^\/api\/accounts\/([^/]+)(?:\/jobs\/([^/]+))?$/.exec(path);
    if (method === 'POST' && account) {
      const input = await json(req);
      return respond(res, account[2]
        ? await setAccountJob(user, account[1], account[2], input)
        : await updateAccount(user, account[1], input));
    }
    if (method === 'POST' && path === '/api/account/password') {
      throttle(req);
      const input = await json(req);
      return respond(res, await changePassword(user, passwordInput(input, 'current_password'), input.new_password));
    }
    if (method === 'POST' && path === '/api/logout') {
      await db.query('DELETE FROM sessions WHERE token_hash=$1', [tokenHash]);
      return respond(res, { signed_out: true });
    }
    if (method === 'GET' && path === '/api/workspace') return respond(res, await workspace(user));
    const exportMatch = /^\/api\/reports\/complaints\.(xlsx|pdf)$/.exec(path);
    if (method === 'GET' && exportMatch) return await report(user, exportMatch[1], url.searchParams, res);
    if (method === 'POST' && path === '/api/jobs') {
      const job = await createJob(user, await json(req));
      let photosLinked = false;
      if (process.env.COMPANYCAM_KEY) {
        try {
          await linkProject(user, job.id);
          photosLinked = true;
        } catch (error) {
          console.error('CompanyCam project link pending', job.id, error instanceof RequestError ? error.message : 'unexpected error');
        }
      }
      return respond(res, { ...job, photos_linked: photosLinked }, 201);
    }
    if (method === 'POST' && path === '/api/complaints') return respond(res, await createComplaint(user, await json(req)), 201);
    const access = /^\/api\/jobs\/([^/]+)\/access$/.exec(path);
    if (method === 'POST' && access) return respond(res, await grantJobAccess(user, access[1], await json(req)));
    const link = /^\/api\/jobs\/([^/]+)\/companycam$/.exec(path);
    if (method === 'POST' && link) return respond(res, await linkProject(user, link[1]));
    const upload = /^\/api\/(complaints|jobs)\/([^/]+)\/photos\/([^/]+)$/.exec(path);
    if (method === 'POST' && upload) {
      const requestId = req.headers['idempotency-key'];
      return respond(res, await uploadPhoto(user, upload[2], upload[3], req.headers['content-type'] ?? '',
        typeof requestId === 'string' ? requestId : '', (limit) => read(req, limit), upload[1] === 'jobs'), 201);
    }
    const photo = /^\/api\/photos\/([^/]+)\/(image|approve)$/.exec(path);
    if (method === 'POST' && photo?.[2] === 'approve') return respond(res, await approvePhoto(user, photo[1]));
    if (method === 'GET' && photo?.[2] === 'image') {
      const image = await fetchPhoto(user, photo[1]);
      res.writeHead(200, { 'Content-Type': image.mime, 'Cache-Control': 'private, no-store' });
      return await pipeline(Readable.fromWeb(image.body), res);
    }
    const complaint = /^\/api\/complaints\/([^/]+)(\/actions)?$/.exec(path);
    if (method === 'GET' && complaint && !complaint[2]) return respond(res, await complaintDetails(user, complaint[1]));
    if (method === 'POST' && complaint?.[2]) return respond(res, await changeComplaint(user, complaint[1], await json(req)));
    throw new RequestError(404, 'Endpoint not found.');
  } catch (error) {
    if (res.headersSent) return res.destroy();
    if (error instanceof RequestError) return respond(res, { error: error.message }, error.status);
    console.error(error);
    return respond(res, { error: 'The server could not complete this request.' }, 500);
  }
});

if (!process.env.DATABASE_URL) throw new Error('Set DATABASE_URL before starting RMCS.');
await checkAuthConfiguration();
await migrate();
await db.query('DELETE FROM sessions WHERE expires_at < now()');
server.listen(port, host, () => console.log(`RMCS listening on http://${host}:${port}`));

// Let active requests finish before closing database connections on a rollout.
function shutdown() {
  if (draining) return;
  draining = true;
  const deadline = setTimeout(() => process.exit(1), 75_000);
  deadline.unref();
  server.close(async (error) => {
    try {
      await db.end();
      process.exitCode = error ? 1 : 0;
    } finally {
      clearTimeout(deadline);
    }
  });
}
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
