import Excel from 'exceljs';
import PDFDocument from 'pdfkit';
import type { ServerResponse } from 'node:http';
import { requireRole, workspace } from './operations.ts';
import { RequestError, uaeDate } from './workflow.ts';
import type { User } from './workflow.ts';

const labels: Record<string, string> = {
  open: 'Open', assigned: 'Assigned', in_progress: 'In Progress', on_hold: 'On Hold',
  verification: 'Pending Verification', rework: 'Rework Required', engineer_review: 'Pending Engineer Review', closed: 'Closed',
};

const scopes: Record<string, string> = {
  All: 'All Statuses', Open: labels.open, 'In progress': labels.in_progress,
  Closed: labels.closed, Active: 'All Unclosed', Overdue: 'Overdue', 'My assigned': 'Assigned to Me',
};

export async function report(user: User, format: string, filters: URLSearchParams, res: ServerResponse) {
  requireRole(user, ['engineer', 'manager', 'supervisor']);
  const scope = filters.get('scope') ?? 'All';
  if (!Object.hasOwn(scopes, scope)) {
    throw new RequestError(400, 'Choose a valid report scope.');
  }
  const query = (filters.get('search') ?? '').trim().toLowerCase();
  const jobId = filters.get('job');
  const assignee = filters.get('assignee');
  const date = uaeDate();
  const data = await workspace(user);
  const jobs = new Map(data.jobs.map((job) => [job.id, job]));
  const rows = data.complaints.filter((row) => {
    const job = jobs.get(row.job_id);
    if (jobId && row.job_id !== jobId) return false;
    if (assignee && row.assigned_to !== (assignee === 'unassigned' ? null : assignee)) return false;
    if (scope === 'Active' && row.status === 'closed') return false;
    if (scope === 'Open' && row.status !== 'open') return false;
    if (scope === 'Closed' && row.status !== 'closed') return false;
    if (scope === 'Overdue' && !row.overdue) return false;
    if (scope === 'In progress' && row.status !== 'in_progress') return false;
    if (scope === 'My assigned' && (row.assigned_to !== user.id || row.status === 'closed')) return false;
    return [row.code, row.title, row.category, job?.site, job?.location, job?.code, job?.client_name]
      .some((value) => String(value ?? '').toLowerCase().includes(query));
  });
  const filename = `RMCS-service-requests-${scopes[scope].toLowerCase().replaceAll(' ', '-')}-${date}.${format}`;
  const headers = { 'Content-Disposition': `attachment; filename="${filename}"`, 'Cache-Control': 'no-store' };

  if (format === 'xlsx') {
    const book = new Excel.Workbook();
    const sheet = book.addWorksheet('Service Requests', { views: [{ state: 'frozen', ySplit: 1 }] });
    sheet.columns = [
      { header: 'Request Number', width: 17 }, { header: 'Site', width: 24 }, { header: 'Client', width: 24 },
      { header: 'Service Request', width: 45 }, { header: 'Category', width: 17 }, { header: 'Priority', width: 12 },
      { header: 'Status', width: 27 }, { header: 'Assigned To', width: 24 }, { header: 'Received (UAE)', width: 17 },
      { header: 'Due Date (UAE)', width: 18 }, { header: 'Closed (UAE)', width: 16 },
      { header: 'Calendar Days', width: 16 }, { header: 'Overdue', width: 11 },
    ];
    sheet.getRow(1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF176245' } };
    sheet.getRow(1).font = { bold: true, color: { argb: 'FFFFFFFF' } };
    for (const row of rows) {
      const job = jobs.get(row.job_id);
      sheet.addRow([row.code, job?.site, job?.client_name, row.title, row.category, row.priority, labels[row.status],
        row.assignee ?? '', uaeDate(new Date(row.received_at)), row.due_on,
        row.closed_at ? uaeDate(new Date(row.closed_at)) : '', row.days_open, row.overdue ? 'Yes' : 'No']);
    }
    sheet.autoFilter = 'A1:M1';
    const file = await book.xlsx.writeBuffer();
    res.writeHead(200, { ...headers, 'Content-Type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
    return res.end(Buffer.from(file));
  }

  const document = new PDFDocument({ size: 'A4', margin: 46, info: { Title: 'RMCS Service Request Report' } });
  res.writeHead(200, { ...headers, 'Content-Type': 'application/pdf' });
  document.pipe(res);
  document.fillColor('#176245').font('Helvetica-Bold').fontSize(21).text('RMCS Service Request Report');
  document.moveDown(.35).fillColor('#52665d').font('Helvetica').fontSize(11)
    .text(`${date} UAE  |  ${scopes[scope]}  |  ${rows.length} ${rows.length === 1 ? 'service request' : 'service requests'}`);
  document.moveDown();
  for (const row of rows) {
    if (document.y > 721) document.addPage();
    const job = jobs.get(row.job_id);
    document.fillColor('#173029').font('Helvetica-Bold').fontSize(11).text(`${row.code}  |  ${row.title}`);
    document.fillColor('#52665d').font('Helvetica').fontSize(10)
      .text(`${job?.site ?? ''}  |  ${row.priority}  |  ${labels[row.status]}  |  Due ${row.due_on}`);
    document.moveDown(.6);
  }
  document.end();
}
