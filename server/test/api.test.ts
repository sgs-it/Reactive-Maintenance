import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { uaeDate } from '../src/workflow.ts';

const origin = process.env.RMCS_TEST_ORIGIN;

test('PostgreSQL API enforces job isolation and Engineer-only closure', { skip: !origin }, async () => {
  const send = (path: string, token?: string, body?: object) => fetch(`${origin}/api/${path}`, {
    method: body ? 'POST' : 'GET',
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  async function login(role: string) {
    const res = await send('login', undefined, { email: `${role}@rmcs.demo`, password: 'rmcs-demo-2026' });
    assert.equal(res.status, 200);
    return res.json() as Promise<{ token: string; user: { id: string } }>;
  }
  const [engineer, supervisor, foreman, manager, client] = await Promise.all(
    ['engineer', 'supervisor', 'foreman', 'manager', 'client'].map(login),
  );
  const jobForm = { site: `Workflow QA ${randomUUID()}`, location: 'Test site', emirate: 'Dubai', client_name: 'Test client' };
  assert.equal((await send('jobs', manager.token, jobForm)).status, 403);
  const newJob = await send('jobs', engineer.token, jobForm);
  assert.equal(newJob.status, 201);
  const job = await newJob.json() as { id: string };
  for (const role of ['supervisor', 'foreman', 'manager']) {
    assert.equal((await send(`jobs/${job.id}/access`, engineer.token, { email: `${role}@rmcs.demo` })).status, 200);
  }
  const registration = await send('complaints', engineer.token, {
    job_id: job.id, title: 'QA sprinkler inspection', description: 'Internal description',
    category: 'Irrigation', priority: 'High', reported_by: 'QA',
    due_on: uaeDate(new Date(Date.now() + 86_400_000)),
  });
  assert.equal(registration.status, 201);
  const complaint = await registration.json() as { id: string };
  const details = `complaints/${complaint.id}`;
  const action = (session: { token: string }, name: string, fields = {}) =>
    send(`${details}/actions`, session.token, { action: name, ...fields });
  assert.equal((await send(details, client.token)).status, 404);
  assert.equal((await action(supervisor, 'assign', { assigned_to: foreman.user.id })).status, 200);
  assert.equal((await action(manager, 'start')).status, 403);
  assert.equal((await action(foreman, 'start')).status, 200);
  assert.equal((await action(foreman, 'update', { progress: 74, remarks: 'Replaced valve.' })).status, 200);
  assert.equal((await action(foreman, 'submit')).status, 200);
  assert.equal((await action(engineer, 'close', { remarks: 'Too early' })).status, 409);
  assert.equal((await action(supervisor, 'verify')).status, 200);
  assert.equal((await action(manager, 'close', { remarks: 'Unauthorized' })).status, 403);
  assert.equal((await action(supervisor, 'close', { remarks: 'Unauthorized' })).status, 403);
  assert.equal((await action(engineer, 'close', { remarks: 'Approved after inspection' })).status, 200);
  const internal = await (await send(details, engineer.token)).json() as { history: { action: string; remarks: string }[] };
  assert.deepEqual(internal.history[0].action, 'close');
  assert.deepEqual(internal.history[0].remarks, 'Approved after inspection');

  assert.equal((await send(`jobs/${job.id}/access`, engineer.token, { email: 'client@rmcs.demo' })).status, 200);
  const clientView = await (await send('workspace', client.token)).json() as { complaints: Record<string, unknown>[] };
  const solved = clientView.complaints.find((row) => row.id === complaint.id);
  assert.equal(solved?.status, 'solved');
  assert.equal(solved?.description, undefined);
  assert.equal(solved?.resolution, undefined);
  assert.deepEqual(await (await send(details, client.token)).json(), { photos: [] });
  assert.equal((await send('reports/complaints.xlsx', client.token)).status, 403);
  const excel = await send('reports/complaints.xlsx?scope=Closed', manager.token);
  assert.equal(excel.status, 200);
  assert.equal(Buffer.from(await excel.arrayBuffer()).subarray(0, 2).toString(), 'PK');
  const pdf = await send('reports/complaints.pdf?scope=Closed', manager.token);
  assert.equal(pdf.status, 200);
  assert.equal(Buffer.from(await pdf.arrayBuffer()).subarray(0, 4).toString(), '%PDF');
});
