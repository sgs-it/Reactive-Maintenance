import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';

const url = process.env.RMCS_TEST_DATABASE_URL;
test('Concurrent field uploads, retries, and workspace reads retain one photo per image', {skip: !url}, async t => {
  assert(url);
  const parsed = new URL(url);
  assert.equal(parsed.hostname, '127.0.0.1');
  assert.match(parsed.pathname, /^\/rmcs_test_[a-z0-9_]+$/);
  process.env.DATABASE_URL = url;
  process.env.COMPANYCAM_KEY = 'test-only';
  const {db} = await import('../src/db.ts');
  const {uploadPhoto} = await import('../src/companycam.ts');
  const {workspace} = await import('../src/operations.ts');
  t.after(()=>db.end());
  const user = {id:randomUUID(),role:'engineer' as const,name:'Field test',email:randomUUID()+'@example.test'};
  const job = randomUUID(), complaint = randomUUID();
  const project = String(BigInt('0x'+randomBytes(8).toString('hex')));
  await db.query('INSERT INTO users(id,name,email,role) VALUES($1,$2,$3,$4)',[user.id,user.name,user.email,user.role]);
  await db.query("INSERT INTO jobs(id,code,site,location,emirate,client_name,created_by,companycam_project_id) VALUES($1,$2,'A','B','Dubai','Client',$3,$4)",[job,job,user.id,project]);
  await db.query('INSERT INTO job_access(job_id,user_id) VALUES($1,$2)',[job,user.id]);
  await db.query("INSERT INTO complaints(id,code,job_id,title,description,category,priority,reported_by,due_on,created_by) VALUES($1,$2,$3,'Test','Test','Irrigation','High','Test',current_date,$4)",[complaint,complaint,job,user.id]);
  let mode: 'ok'|'prepareFailure'|'uncertain' = 'ok';
  let registrations = 0;
  const envelope = (data:unknown)=>Response.json({data});
  t.mock.method(globalThis,'fetch', async (address: string | URL) => {
    const target = String(address);
    if (target.endsWith('/uploads')) {
      if(mode==='prepareFailure') return new Response(null,{status:503});
      return envelope({upload_id:randomUUID(),upload_url:'https://storage.companycam.com/test',method:'PUT',headers:{}});
    }
    if(target==='https://storage.companycam.com/test') return new Response(null,{status:200});
    assert(target.endsWith('/projects/'+project+'/photos'));
    registrations++;
    if(mode==='uncertain') throw new Error('Interrupted after registration');
    return envelope({id:String(BigInt(project)*100n+BigInt(registrations)),project_id:project});
  });
  const upload = (seed:number) => uploadPhoto(user,complaint,'Before','image/jpeg',randomBytes(24).toString('hex'),
    async()=>Buffer.concat([Buffer.from([255,216,255]),Buffer.alloc(1024*1024,seed)]));
  mode='prepareFailure';
  await assert.rejects(upload(0)); await assert.rejects(upload(0));
  const overview = await workspace(user);
  assert('upload_alerts' in overview);
  assert.equal(overview.upload_alerts.length,1);
  mode='ok';
  const started=performance.now();
  await Promise.all([...Array.from({length:8},(_,i)=>upload(i)),...Array.from({length:16},()=>workspace(user))]);
  t.diagnostic('8 concurrent 1 MiB uploads and 16 workspace reads, simulated CompanyCam: '+Math.round(performance.now()-started)+' ms');
  await Promise.all([upload(0),upload(0)]);
  assert.equal(registrations,8);
  const projectUpload = (actor = user) => uploadPhoto(actor, job, 'Before', 'image/jpeg',
    randomBytes(24).toString('hex'), async () => Buffer.from([255,216,255,1]), true);
  await assert.rejects(projectUpload({...user, id: randomUUID()}), /not found/);
  assert.deepEqual(await projectUpload(), await projectUpload());
  assert.equal(registrations, 9);
  mode='uncertain';
  await assert.rejects(upload(9));
  await assert.rejects(upload(9), /pending confirmation/);
  assert.equal(registrations,10);
  const result=await db.query('SELECT count(*)::int AS count FROM photos WHERE complaint_id=$1',[complaint]);
  assert.equal(result.rows[0].count,8);
});
