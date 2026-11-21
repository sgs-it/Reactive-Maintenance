export const roles = ['foreman', 'supervisor', 'engineer', 'manager', 'client'] as const;
export type Role = typeof roles[number];
export type User = { id: string; name: string; email: string; role: Role };
export type Status = 'open' | 'assigned' | 'in_progress' | 'on_hold' |
  'verification' | 'rework' | 'engineer_review' | 'closed';

export class RequestError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

const reviewers: Role[] = ['supervisor', 'engineer', 'manager'];
type Rule = { from: Status[]; to: Status | null; roles?: Role[]; assigned?: boolean };
const rules: Record<string, Rule> = {
  assign: { from: ['open', 'assigned', 'in_progress', 'on_hold', 'rework'], to: 'assigned', roles: ['engineer','supervisor'] },
  start: { from: ['assigned', 'rework', 'on_hold'], to: 'in_progress', assigned: true },
  update: { from: ['in_progress'], to: 'in_progress', assigned: true },
  hold: { from: ['in_progress'], to: 'on_hold', assigned: true },
  submit: { from: ['in_progress'], to: 'verification', assigned: true },
  verify: { from: ['verification'], to: 'engineer_review', roles: reviewers },
  rework: { from: ['verification', 'engineer_review'], to: 'rework', roles: reviewers },
  close: { from: ['engineer_review'], to: 'closed', roles: ['engineer'] },
  reopen: { from: ['closed'], to: 'rework', roles: ['engineer'] },
};

export function nextStatus(action: string, status: Status, actor: User, assignee: string | null): Status {
  const rule = Object.hasOwn(rules, action) ? rules[action] : undefined;
  if (!rule) throw new RequestError(400, 'Unknown service request action.');
  if (actor.role === 'client' || (rule.roles && !rule.roles.includes(actor.role)) ||
      (rule.assigned && actor.id !== assignee) ||
      (action === 'assign' && actor.role === 'supervisor' && actor.id !== assignee) ||
      (action === 'start' && actor.role === 'supervisor') ||
      (action === 'rework' && status === 'engineer_review' && actor.role !== 'engineer')) {
    throw new RequestError(403, 'Your role or assignment does not allow this action.');
  }
  if (!rule.from.includes(status)) throw new RequestError(409, 'This service request has changed. Refresh and try again.');
  return rule.to ?? (status === 'open' ? 'assigned' : status);
}

export function clientStatus(status: Status) {
  if (status === 'closed') return 'solved';
  if (status === 'on_hold') return 'pending';
  if (status === 'open' || status === 'assigned') return 'open';
  return 'in_progress';
}

export function uaeDate(date = new Date()) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Dubai', dateStyle: 'short' }).format(date);
}
