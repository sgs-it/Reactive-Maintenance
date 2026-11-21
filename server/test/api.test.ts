import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import pg from 'pg';
import Excel from 'exceljs';
import { hashPassword } from '../src/auth.ts';
import { roles, uaeDate } from '../src/workflow.ts';
import type { Role } from '../src/workflow.ts';

const origin = process.env.RMCS_TEST_ORIGIN;
const testDatabase = process.env.RMCS_TEST_DATABASE_URL;

test('PostgreSQL API enforces job isolation and Engineer-only closure', { skip: !origin && !testDatabase }, async () => {
  assert(origin && testDatabase, 'Set RMCS_TEST_ORIGIN and RMCS_TEST_DATABASE_URL together.');
  const databaseUrl = new URL(testDatabase);
  assert.equal(new URL(origin).hostname, '127.0.0.1');
  assert.equal(databaseUrl.hostname, '127.0.0.1');
  assert.match(databaseUrl.pathname, /^\/rmcs_test_[a-z0-9_]+$/);
  const runId = randomUUID();
  const email = (role: Role) => `${role}+${runId}@example.test`;
  const password = randomUUID();
  const passwordHash = await hashPassword(password);
  const fixtures = new pg.Pool({ connectionString: testDatabase });
  try {
    for (const role of roles) {
      await fixtures.query('INSERT INTO users (name,email,password_hash,role) VALUES ($1,$2,$3,$4)',
        [`Test ${role}`, email(role), passwordHash, role]);
    }
  } finally {
    await fixtures.end();
  }
  const send = (path: string, token?: string, body?: object) => fetch(`${origin}/api/${path}`, {
    method: body ? 'POST' : 'GET',
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  async function login(role: Role) {
    const res = await send('login', undefined, { email: email(role), password });
    assert.equal(res.status, 200);
    return res.json() as Promise<{ token: string; user: { id: string } }>;
  }
  const [engineer, supervisor, foreman, manager, client] = await Promise.all(
    (['engineer', 'supervisor', 'foreman', 'manager', 'client'] as const).map(login),
  );
  const jobForm = { site: `Workflow QA ${randomUUID()}`, location: 'Test site', emirate: 'Dubai', client_name: 'Test client' };
  assert.equal((await send('jobs', manager.token, jobForm)).status, 201);
  for (const session of [client,foreman,supervisor]) assert.equal((await send('jobs', session.token, jobForm)).status, 403);
  const newJob = await send('jobs', engineer.token, jobForm);
  assert.equal(newJob.status, 201);
  const job = await newJob.json() as { id: string };
  for (const role of ['supervisor', 'foreman', 'manager'] as const) {
    assert.equal((await send(`jobs/${job.id}/access`, engineer.token, { email: email(role) })).status, 200);
  }
  const registration = await send('complaints', engineer.token, {
    job_id: job.id, title: 'QA sprinkler inspection', description: 'Internal description',
    category: 'Other', other_category: 'Fence repair', priority: 'High', reported_by: 'QA',
    due_on: uaeDate(new Date(Date.now() + 86_400_000)),
  });
  assert.equal(registration.status, 201);
  const complaint = await registration.json() as { id: string };
  const details = `complaints/${complaint.id}`;
  const fixtureDb = new pg.Pool({connectionString:testDatabase});
  try {
    const saved = await fixtureDb.query("SELECT category,reported_by FROM complaints WHERE id=$1", [complaint.id]);
    assert.deepEqual(saved.rows[0], { category: "Other: Fence repair", reported_by: "Test engineer" });
    await fixtureDb.query("UPDATE complaints SET due_on=(now() AT TIME ZONE 'Asia/Dubai')::date WHERE id=$1",[complaint.id]);
  } finally { await fixtureDb.end(); }
  const bulkRead = async (scope:string) => {
    const res = await send(`reports/complaints.xlsx?job=${job.id}&scope=${encodeURIComponent(scope)}`,manager.token);
    assert.equal(res.status,200);
    const book = new Excel.Workbook();
    await book.xlsx.load(await res.arrayBuffer());
    assert.equal(book.worksheets[0].actualRowCount,2);
  };
  await Promise.all([...Array.from({length:4},()=>bulkRead('Due today')),bulkRead('Unassigned'),
    ...Array.from({length:12},async()=>assert.equal((await send('workspace',supervisor.token)).status,200))]);

  const action = (session: { token: string }, name: string, fields = {}) =>
    send(`${details}/actions`, session.token, { action: name, ...fields });
  assert.equal((await send(details, client.token)).status, 404);
  assert.equal((await send('workspace')).status, 401);
  async function checkResponsibility(session: {token:string}, name:string) {
    const data = await (await send('workspace', session.token)).json() as {complaints:{id:string;responsible:string;my_responsibility:boolean}[]};
    const current = data.complaints.find(item => item.id === complaint.id);
    assert.equal(current?.responsible,name);
    assert.equal(current?.my_responsibility,true);
  }
  assert.equal((await action(supervisor, 'assign', { assigned_to: foreman.user.id })).status, 403);
  assert.equal((await action(manager, 'assign', { assigned_to: supervisor.user.id })).status, 403);
  assert.equal((await action(engineer, 'assign', { assigned_to: foreman.user.id })).status, 400);
  assert.equal((await action(engineer, 'assign', { assigned_to: supervisor.user.id })).status, 200);
  await checkResponsibility(supervisor,'Test supervisor');
  assert.equal((await action(supervisor, 'start')).status, 403);
  assert.equal((await action(supervisor, 'assign', { assigned_to: foreman.user.id })).status, 200);
  await checkResponsibility(foreman,'Test foreman');
  const tracking = await (await send(details, engineer.token)).json() as {assignments: {assignment: {to_id: string}}[]};
  assert.deepEqual(tracking.assignments.map((event: {assignment: {to_id: string}}) => event.assignment.to_id), [foreman.user.id, supervisor.user.id]);
  assert.equal((await action(manager, 'start')).status, 403);
  assert.equal((await action(foreman, 'start')).status, 200);
  assert.equal((await action(foreman, 'update', { progress: 74, remarks: 'Replaced valve.' })).status, 200);
  assert.equal((await action(foreman, 'submit')).status, 200);
  await bulkRead('Verification');
  await checkResponsibility(supervisor,'Test supervisor');
  assert.equal((await action(engineer, 'close', { remarks: 'Too early' })).status, 409);
  assert.equal((await action(supervisor, 'verify')).status, 200);
  await checkResponsibility(engineer,'Test engineer');
  assert.equal((await action(manager, 'close', { remarks: 'Unauthorized' })).status, 403);
  assert.equal((await action(supervisor, 'close', { remarks: 'Unauthorized' })).status, 403);
  assert.equal((await action(engineer, 'close', { remarks: 'Approved after inspection' })).status, 200);
  const internal = await (await send(details, engineer.token)).json() as { history: { action: string; remarks: string }[] };
  assert.deepEqual(internal.history[0].action, 'close');
  assert.deepEqual(internal.history[0].remarks, 'Approved after inspection');

  assert.equal((await send(`jobs/${job.id}/access`, engineer.token, { email: email('client') })).status, 200);
  const clientView = await (await send('workspace', client.token)).json() as { complaints: Record<string, unknown>[] };
  const solved = clientView.complaints.find((row) => row.id === complaint.id);
  assert.equal(solved?.status, 'solved');
  assert.equal(solved?.description, undefined);
  assert.equal(solved?.resolution, undefined);
  const publicDetail = await (await send(details, client.token)).json() as {photos: unknown[]; assignments: unknown[]; history?: unknown};
  assert.deepEqual(publicDetail.photos, []);
  assert.equal(publicDetail.assignments.length, 2);
  assert.equal(publicDetail.history, undefined);
  assert.equal((await send('reports/complaints.xlsx', client.token)).status, 403);
  const excel = await send('reports/complaints.xlsx?scope=Closed', manager.token);
  assert.equal(excel.status, 200);
  assert.equal(Buffer.from(await excel.arrayBuffer()).subarray(0, 2).toString(), 'PK');
  const pdf = await send('reports/complaints.pdf?scope=Closed', manager.token);
  assert.equal(pdf.status, 200);
  assert.equal(Buffer.from(await pdf.arrayBuffer()).subarray(0, 4).toString(), '%PDF');

  const managedEmail = `managed+${runId}@example.test`;
  const accountForm = { name: 'Managed staff', email: managedEmail, role: 'supervisor', password };
  assert.equal((await send('accounts', supervisor.token, accountForm)).status, 403);
  assert.equal((await send('accounts', engineer.token, {
    ...accountForm, email: `engineer-managed+${runId}@example.test`,
  })).status, 403);
  for (const session of [foreman, client]) {
    assert.equal((await send('accounts', session.token, accountForm)).status, 403);
  }
  const engineerAccounts = await (await send('accounts', engineer.token)).json() as { can_add_user: boolean };
  assert.equal(engineerAccounts.can_add_user, false);
  const managerAccounts = await (await send('accounts', manager.token)).json() as { can_add_user: boolean };
  assert.equal(managerAccounts.can_add_user, true);
  const newAccount = await send('accounts', manager.token, accountForm);
  assert.equal(newAccount.status, 201);
  const { account } = await newAccount.json() as { account: { id: string } };
  const accountPath = `accounts/${account.id}`;
  const accessPath = `${accountPath}/jobs/${job.id}`;
  const update = { name: accountForm.name, role: accountForm.role, active: false };
  assert.equal((await send(accountPath, engineer.token, update)).status, 404);
  const authorized = await send('login', undefined, { email: managedEmail, password });
  assert.equal(authorized.status, 200);
  const { token: managedToken } = await authorized.json() as { token: string };
  const visibleFrom = new Date(Date.now() + 86_400_000).toISOString();
  const visibleUntil = new Date(Date.now() + 172_800_000).toISOString();
  assert.equal((await send(accessPath, manager.token, { granted: true, visible_from: visibleFrom, visible_until: visibleUntil })).status, 200);
  assert.equal((await send(details, managedToken)).status, 404);
  const beforeAccess = await (await send('workspace', managedToken)).json() as { next_access_change: string; jobs: unknown[] };
  assert.equal(beforeAccess.next_access_change, visibleFrom);
  assert.equal(beforeAccess.jobs.length, 0);
  assert.equal((await send(accessPath, manager.token, { granted: true, visible_until: visibleUntil })).status, 200);
  assert.equal((await send(details, managedToken)).status, 200);
  assert.equal((await send(accessPath, manager.token, { granted: false })).status, 200);
  assert.equal((await send(details, managedToken)).status, 404);
  assert.equal((await send(accountPath, manager.token, update)).status, 200);
  assert.equal((await send('workspace', managedToken)).status, 401);

  // Exercise two client identities and the same session on both sides of expiry.
  const control = new pg.Pool({connectionString:testDatabase});
  try {
    const otherEmail = `second-client+${runId}@example.test`;
    await control.query("INSERT INTO users(name,email,password_hash,role) VALUES('Other client',$1,$2,'client')", [otherEmail,passwordHash]);
    const second = await (await send('login', undefined, {email:otherEmail,password})).json() as {token:string};
    const photoIds = await control.query(`INSERT INTO photos(complaint_id,uploader_id,uploader_role,stage,provider_id,approved_at)
      VALUES($1,$2,'engineer','Before',$3,now()),($1,$2,'engineer','Progress',$4,NULL) RETURNING id`,
      [complaint.id,engineer.user.id,randomUUID(),randomUUID()]);
    const shared = await (await send(details,client.token)).json() as {photos:{id:string}[]};
    assert.deepEqual(shared.photos.map(p=>p.id),[photoIds.rows[0].id]);
    assert.equal((await send(details,second.token)).status,404);
    for (const photo of photoIds.rows) assert.equal((await send(`photos/${photo.id}/image`,second.token)).status,404);
    assert.equal((await send(`photos/${photoIds.rows[1].id}/image`,client.token)).status,404);
    await control.query("UPDATE job_access SET visible_until=now()-interval '1 second' WHERE job_id=$1 AND user_id=$2",[job.id,client.user.id]);
    assert.equal((await send(details,client.token)).status,404);
    await control.query('UPDATE job_access SET visible_until=NULL WHERE job_id=$1 AND user_id=$2',[job.id,client.user.id]);
    for (const [scope,count] of [['Closed',1],['Active',0],['Due today',0],['Verification',0],['Unassigned',0]] as const) {
      const response = await send(`reports/complaints.xlsx?job=${job.id}&scope=${encodeURIComponent(scope)}`,manager.token);
      assert.equal(response.status,200);
      const book = new Excel.Workbook();
      await book.xlsx.load(await response.arrayBuffer());
      assert.equal(book.worksheets[0].actualRowCount-1,count);
    }
  } finally { await control.end(); }

  for (const session of [client, manager, supervisor, foreman]) {
    assert.equal((await send('complaints', session.token, {job_id:job.id,title:'New request',description:'Field issue',
      category:'Trees',priority:'Medium',due_on:uaeDate()})).status,201);
  }

  const clientSecondSession = await login('client');
  const replacement = `Changed-${randomUUID()}`;
  const passwordChange = (current_password: string, new_password: string) =>
    send('account/password', client.token, { current_password, new_password });
  assert.equal((await passwordChange('wrong', replacement)).status, 400);
  assert.equal((await passwordChange(password, 'short')).status, 400);
  assert.equal((await passwordChange(password, replacement)).status, 200);
  assert.equal((await send('workspace', client.token)).status, 401);
  assert.equal((await send('workspace', clientSecondSession.token)).status, 401);
  assert.equal((await send('login', undefined, {
    email: email('client'), password,
  })).status, 401);
  const signedIn = await send('login', undefined, { email: email('client'), password: replacement });
  assert.equal(signedIn.status, 200);
  const updated = await signedIn.json() as { token: string; user: { id: string } };
  assert.equal(updated.user.id, client.user.id);
  assert.equal((await send(details, updated.token)).status, 200);
  assert.equal((await send('logout', updated.token, {})).status, 200);
});
