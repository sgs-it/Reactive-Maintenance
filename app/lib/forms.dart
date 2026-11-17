import 'package:flutter/material.dart';
import 'api.dart';
import 'ui_labels.dart';
import 'main.dart';

class EntryForm extends StatefulWidget {
  const EntryForm({
    super.key,
    required this.api,
    required this.jobs,
    required this.createJob,
  });
  final Api api;
  final List<Data> jobs;
  final bool createJob;
  @override
  State<EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<EntryForm> {
  final key = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  String? jobId;
  String priority = 'Medium';
  String category = 'Irrigation';
  String emirate = 'Dubai';
  DateTime? due;
  String? error;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.jobs.length == 1) jobId = widget.jobs.single['id'] as String;
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Widget input(
    String name,
    String label,
    int max, {
    bool required = true,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: fields.putIfAbsent(name, TextEditingController.new),
      decoration: InputDecoration(labelText: label),
      maxLines: lines,
      maxLength: max,
      buildCounter:
          (_, {required currentLength, required isFocused, maxLength}) => null,
      validator: (value) =>
          required && (value ?? '').trim().isEmpty ? 'Enter $label.' : null,
    ),
  );

  Future<void> submit() async {
    if (!key.currentState!.validate() || saving) return;
    if (!widget.createJob && due == null) {
      setState(() => error = 'Select a due date.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final data = <String, dynamic>{
      for (final entry in fields.entries) entry.key: entry.value.text.trim(),
    };
    if (widget.createJob) {
      data['emirate'] = emirate;
    } else {
      data.addAll({
        'job_id': jobId,
        'priority': priority,
        'category': category,
        'due_on': due!.toIso8601String().substring(0, 10),
      });
    }
    try {
      await widget.api.post(widget.createJob ? 'jobs' : 'complaints', data);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      scrollable: true,
      title: Text(widget.createJob ? newJobLabel : newServiceRequestLabel),
      content: SizedBox(
        width: 465,
        child: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.createJob) ...[
                input('site', 'Site Name', 160),
                input('location', 'Location', 240),
                input('client_name', 'Client Organization', 160),
                selectField('Emirate', emirate, const [
                  'Dubai',
                  'Abu Dhabi',
                  'Sharjah',
                  'Ajman',
                  'Umm Al Quwain',
                  'Ras Al Khaimah',
                  'Fujairah',
                ], (value) => setState(() => emirate = value!)),
              ] else ...[
                DropdownButtonFormField<String>(
                  initialValue: jobId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Job'),
                  items: [
                    for (final job in widget.jobs)
                      DropdownMenuItem(
                        value: job['id'] as String,
                        child: Text(
                          '${job['code']} · ${job['site']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => jobId = value),
                  validator: (value) => value == null ? 'Select a job.' : null,
                ),
                const SizedBox(height: 12),
                input('title', 'Request Title', 160),
                input('description', 'Description', 4000, lines: 3),
                input('reported_by', 'Reported By', 160),
                selectField('Category', category, const [
                  'Irrigation',
                  'Trees',
                  'Softscape',
                  'Electrical',
                  'Drainage',
                  'Hardscape',
                  'Other',
                ], (value) => setState(() => category = value!)),
                const SizedBox(height: 12),
                selectField('Priority', priority, const [
                  'Critical',
                  'High',
                  'Medium',
                  'Low',
                ], (value) => setState(() => priority = value!)),
                const SizedBox(height: 12),
                input(
                  'required_action',
                  'Required Action (optional)',
                  2000,
                  required: false,
                  lines: 2,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                      due == null
                          ? 'Select Due Date'
                          : due!.toIso8601String().substring(0, 10),
                    ),
                    onPressed: () async {
                      final now = DateTime.now().toUtc().add(
                        const Duration(hours: 4),
                      );
                      final today = DateTime(now.year, now.month, now.day);
                      final chosen = await showDatePicker(
                        context: context,
                        initialDate: due ?? today,
                        firstDate: today,
                        lastDate: DateTime(today.year + 5),
                      );
                      if (mounted && chosen != null) {
                        setState(() => due = chosen);
                      }
                    },
                  ),
                ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Color(0xffa52b24)),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : submit,
          child: Text(
            saving
                ? 'Saving…'
                : widget.createJob
                ? 'Create Job'
                : 'Create Service Request',
          ),
        ),
      ],
    ),
  );
}

Widget selectField(
  String label,
  String selected,
  List<String> options,
  ValueChanged<String?> change,
) => DropdownButtonFormField<String>(
  initialValue: selected,
  isExpanded: true,
  decoration: InputDecoration(labelText: label),
  items: [
    for (final value in options)
      DropdownMenuItem(value: value, child: Text(value)),
  ],
  onChanged: change,
);

class AccessForm extends StatefulWidget {
  const AccessForm({super.key, required this.api, required this.job});
  final Api api;
  final Data job;
  @override
  State<AccessForm> createState() => _AccessFormState();
}

class _AccessFormState extends State<AccessForm> {
  final email = TextEditingController();
  String? feedback;
  bool busy = false;
  bool granted = false;

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> grant() async {
    if (busy) return;
    setState(() {
      busy = true;
      feedback = null;
      granted = false;
    });
    try {
      await widget.api.post('jobs/${widget.job['id']}/access', {
        'email': email.text.trim(),
      });
      if (mounted) {
        setState(() {
          granted = true;
          feedback = 'Job access granted.';
          email.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => feedback = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Grant Job Access'),
    content: SizedBox(
      width: 395,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add an existing staff or client account to ${widget.job['site']}.',
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            onSubmitted: (_) => grant(),
            decoration: const InputDecoration(labelText: 'Email Address'),
          ),
          if (feedback != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                feedback!,
                style: TextStyle(
                  color: granted ? green : const Color(0xffa52b24),
                ),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      FilledButton(
        onPressed: busy ? null : grant,
        child: Text(busy ? 'Saving…' : 'Grant Access'),
      ),
    ],
  );
}
