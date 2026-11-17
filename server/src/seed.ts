import { hashPassword } from './auth.ts';
import { db, migrate, transaction } from './db.ts';
import { createJob, createComplaint, changeComplaint, grantJobAccess } from './operations.ts';
import { roles, uaeDate } from './workflow.ts';
import type { User } from './workflow.ts';

if (!process.env.DATABASE_URL) throw new Error('Set DATABASE_URL before provisioning accounts.');
await migrate();
try {
  if (process.argv[2] === 'demo') {
    const url = new URL(process.env.DATABASE_URL);
    if (process.env.RMCS_DEMO !== 'true' || !['localhost', '127.0.0.1'].includes(url.hostname) ||
        url.pathname !== '/rmcs_demo') throw new Error('Demo data requires RMCS_DEMO=true and a local rmcs_demo database.');
    const [{ count }] = (await db.query('SELECT count(*) FROM users')).rows;
    if (Number(count)) throw new Error('Demo seeding requires an empty database.');
    const password = await hashPassword('rmcs-demo-2026');
    const accounts = await transaction(async (connection) => {
      const people = [];
      for (const [index, name] of ['Omar Saleh', 'Sara Khan', 'Ahmed Faisal', 'Maya Thomas', 'Leila Karim'].entries()) {
        const role = roles[index];
        const { rows: [account] } = await connection.query<User>(
          'INSERT INTO users(name,email,password_hash,role) VALUES($1,$2,$3,$4) RETURNING id,name,email,role',
          [name, `${role}@rmcs.demo`, password, role],
        );
        people.push(account);
      }
      return people;
    });
    const [foreman, supervisor, engineer, manager, client] = accounts;
    const siteData = [
      ['Verdant Gardens', 'Zone A · Al Barsha', 'Dubai', 'Verdant Communities'],
      ['Creek View Park', 'Zone B · Creek Harbour', 'Dubai', 'Creek View Estates'],
      ['Riverside Walk', 'Zone C · Al Jaddaf', 'Dubai', 'Riverside Properties'],
    ];
    const jobs = [];
    for (const [site, location, emirate, client_name] of siteData) {
      const job = await createJob(engineer, { site, location, emirate, client_name });
      jobs.push(job);
      for (const staff of [foreman, supervisor, manager]) await grantJobAccess(engineer, job.id, { email: staff.email });
    }
    await grantJobAccess(engineer, jobs[0].id, { email: client.email });
    const examples = [
      [0, 'Irrigation line leakage', 'High', 'Irrigation', 'Inspect the lawn sprinkler line and replace the damaged connection.', 2],
      [1, 'Fallen tree branch', 'Critical', 'Trees', 'Remove the branch and inspect the surrounding trees for damage.', 1],
      [2, 'Damaged landscape lighting', 'Medium', 'Electrical', 'Test the pathway light and replace the damaged fixture.', 0],
      [0, 'Overgrown shrubs near entrance', 'Low', 'Softscape', 'Trim the shrubs around the entrance to clear the walkway.', 3],
      [1, 'Water pooling by footpath', 'Medium', 'Drainage', 'Clear the drain inlet and verify flow.', 4],
      [2, 'Broken planter edging', 'High', 'Hardscape', 'Replace the cracked edging and make the path safe.', 5],
      [0, 'Uneven paving at the lawn', 'Medium', 'Hardscape', 'Reset loose pavers and check levels along the path.', 5],
    ] as const;
    for (const [site, title, priority, category, description, stage] of examples.toReversed()) {
      const { id } = await createComplaint(engineer, {
        job_id: jobs[site].id, title, priority, category, description,
        reported_by: 'Site operations', due_on: uaeDate(new Date(Date.now() + 3 * 86_400_000)),
        required_action: description,
      });
      if (stage >= 1) await changeComplaint(supervisor, id, { action: 'assign', assigned_to: foreman.id });
      if (stage >= 2) await changeComplaint(foreman, id, { action: 'start' });
      if (stage === 2) await changeComplaint(foreman, id, { action: 'update', progress: 70, remarks: 'Leak isolated and replacement fitting installed.' });
      if (stage >= 3) await changeComplaint(foreman, id, { action: 'submit' });
      if (stage >= 4) await changeComplaint(supervisor, id, { action: 'verify', remarks: 'Completion checked on site.' });
      if (stage >= 5) await changeComplaint(engineer, id, { action: 'close', remarks: 'Work inspected and accepted.' });
    }
    await db.query(`UPDATE complaints SET due_on=(now() AT TIME ZONE 'Asia/Dubai')::date-1 WHERE priority='Critical'`);
    console.log('Created five demo users and seven fictional complaints.');
  } else {
    const { RMCS_USER_EMAIL: email, RMCS_USER_NAME: name, RMCS_USER_ROLE: role, RMCS_USER_PASSWORD: password } = process.env;
    if (!email?.includes('@') || !name?.trim() || !roles.some((value) => value === role) ||
        !password || password.length < 14 || password.length > 256 || password !== password.trim()) {
      throw new Error('Set RMCS_USER_EMAIL, RMCS_USER_NAME, RMCS_USER_ROLE and a password of 14–256 characters.');
    }
    await db.query('INSERT INTO users(name,email,password_hash,role) VALUES($1,$2,$3,$4)',
      [name.trim(), email.trim().toLowerCase(), await hashPassword(password), role]);
    console.log('Account created.');
  }
} finally {
  await db.end();
}
