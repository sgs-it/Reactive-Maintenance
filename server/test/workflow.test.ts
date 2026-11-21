import { test } from 'node:test';
import assert from 'node:assert/strict';
import { clientStatus, nextStatus, RequestError, uaeDate } from '../src/workflow.ts';
import type { User } from '../src/workflow.ts';

const actor = (role: User['role']): User => ({ id: role, name: role, email: `${role}@example.test`, role });
const rejected = (code: number) => (error: unknown) => error instanceof RequestError && error.status === code;

test('assigned work moves through verification to Engineer closure', () => {
  const foreman = actor('foreman');
  const supervisor = actor('supervisor');
  const engineer = actor('engineer');
  let status = nextStatus('assign', 'open', engineer, null);
  status = nextStatus('assign', status, supervisor, supervisor.id);
  status = nextStatus('start', status, foreman, foreman.id);
  status = nextStatus('submit', status, foreman, foreman.id);
  assert.equal(status, 'verification');
  status = nextStatus('verify', status, supervisor, foreman.id);
  assert.equal(status, 'engineer_review');
  assert.throws(() => nextStatus('close', status, supervisor, foreman.id), rejected(403));
  assert.throws(() => nextStatus('close', status, actor('manager'), foreman.id), rejected(403));
  assert.equal(nextStatus('close', status, engineer, foreman.id), 'closed');
  assert.equal(nextStatus('reopen', 'closed', engineer, foreman.id), 'rework');
});

test('the workflow rejects out-of-order transitions and another assignee’s work', () => {
  const engineer = actor('engineer');
  assert.throws(() => nextStatus('close', 'verification', engineer, 'foreman'), rejected(409));
  assert.throws(() => nextStatus('start', 'assigned', actor('foreman'), 'other-user'), rejected(403));
  assert.throws(() => nextStatus('verify', 'verification', actor('client'), null), rejected(403));
  assert.equal(clientStatus('closed'), 'solved');
  assert.equal(clientStatus('engineer_review'), 'in_progress');
  assert.equal(uaeDate(new Date('2026-11-10T21:05:00Z')), '2026-11-11');
});
