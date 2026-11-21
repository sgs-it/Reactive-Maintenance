import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
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
    required this.requester,
    this.initialProjectId,
    this.allowPhotos = true,
  });
  final Api api;
  final List<Data> jobs;
  final bool createJob;
  final String requester;
  final bool allowPhotos;
  final String? initialProjectId;
  @override
  State<EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<EntryForm> {
  final key = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  String? jobId;
  String priority = 'Medium';
  final otherCategoryKey = GlobalKey();
  final otherCategoryFocus = FocusNode();
  String category = 'Irrigation';
  String emirate = 'Dubai';
  DateTime? due;
  String? error;
  bool saving = false;
  Data? created;
  Uint8List? photo;
  String photoName = '';
  String mime = '';
  String reference = '';
  bool picking = false;

  bool get linked => widget.jobs.any(
    (job) => job['id'] == jobId && job['photos_linked'] == true,
  );

  Future<void> choosePhoto(ImageSource source) async {
    if (picking || saving) return;
    setState(() {
      picking = true;
      error = null;
    });
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2200,
        imageQuality: 85,
      );
      if (file == null) return;
      if (await file.length() > 10 * 1024 * 1024) {
        throw const ApiException('Choose a photo up to 10 MB.', 413);
      }
      final bytes = await file.readAsBytes();
      String type;
      if (bytes.length >= 3 &&
          listEquals(bytes.sublist(0, 3), [255, 216, 255])) {
        type = 'image/jpeg';
      } else if (bytes.length >= 8 &&
          listEquals(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10])) {
        type = 'image/png';
      } else if (bytes.length >= 12 &&
          String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
          String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
        type = 'image/webp';
      } else {
        throw const ApiException('Choose a JPEG, PNG or WebP photo.', 400);
      }
      if (!mounted) return;
      final rng = Random.secure();
      setState(() {
        photo = bytes;
        photoName = file.name;
        mime = type;
        reference = List.generate(
          24,
          (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiException
              ? e.message
              : 'Could not read this photo.',
        );
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Widget attachment() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (photo != null)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Image.memory(
            photo!,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(Icons.image_outlined),
          ),
          title: Text(photoName, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: created != null
              ? null
              : IconButton(
                  tooltip: 'Remove Photo',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => photo = null),
                ),
        ),
      if (created == null)
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: linked && !picking
                  ? () => choosePhoto(ImageSource.gallery)
                  : null,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(photo == null ? 'Attach Photo' : 'Replace Photo'),
            ),
            if (!kIsWeb)
              OutlinedButton.icon(
                onPressed: linked && !picking
                    ? () => choosePhoto(ImageSource.camera)
                    : null,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Take Photo'),
              ),
          ],
        ),
      if (!linked)
        Text(
          jobId == null
              ? 'Select a project to attach a photo.'
              : 'This project needs a CompanyCam link before you can attach a photo.',
        ),
      const SizedBox(height: 12),
    ],
  );

  @override
  void initState() {
    super.initState();
    if (widget.jobs.any(
      (project) => project['id'] == widget.initialProjectId,
    )) {
      jobId = widget.initialProjectId;
    } else if (widget.jobs.length == 1) {
      jobId = widget.jobs.single['id'] as String;
    }
  }

  @override
  void dispose() {
    otherCategoryFocus.dispose();
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  void selectCategory(String? value) {
    if (value == null) return;
    setState(() => category = value);
    if (value != 'Other') return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || category != 'Other') return;
      final field = otherCategoryKey.currentContext;
      if (field == null) return;
      otherCategoryFocus.requestFocus();
      Scrollable.ensureVisible(
        field,
        alignment: 0.35,
        duration: const Duration(milliseconds: 180),
      );
    });
  }

  Widget input(
    String name,
    String label,
    int max, {
    bool required = true,
    int lines = 1,
    Key? fieldKey,
    FocusNode? focusNode,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: fieldKey,
      focusNode: focusNode,
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
    if (saving ||
        picking ||
        (created == null && !key.currentState!.validate())) {
      return;
    }
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
    if (category != 'Other') data.remove('other_category');
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
      created ??= await widget.api.post(
        widget.createJob ? 'jobs' : 'complaints',
        data,
      );
      if (photo != null) {
        if (mounted) setState(() {});
        await widget.api.upload(
          created!['id'] as String,
          'Before',
          photo!,
          mime,
          reference,
        );
      }
      if (mounted) {
        Navigator.of(
          context,
        ).pop({...created!, 'photo_uploaded': photo != null});
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = created == null
              ? e.toString()
              : 'Request ${created!['code']} was saved. Photo upload was not confirmed. $e';
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving && created == null && !picking,
    child: AlertDialog(
      scrollable: true,
      title: Text(widget.createJob ? newJobLabel : newServiceRequestLabel),
      content: SizedBox(
        width: 465,
        child: IgnorePointer(
          ignoring: saving || picking,
          child: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (created != null)
                  attachment()
                else if (widget.createJob) ...[
                  input('site', 'Project Name', 160),
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
                    decoration: const InputDecoration(labelText: 'Project'),
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
                    onChanged: (value) => setState(() {
                      jobId = value;
                      photo = null;
                    }),
                    validator: (value) =>
                        value == null ? 'Select a project.' : null,
                  ),
                  const SizedBox(height: 12),
                  if (widget.allowPhotos) attachment(),
                  input('title', 'Request Title', 160),
                  input('description', 'Description', 4000, lines: 3),
                  TextFormField(
                    initialValue: widget.requester,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Requested By',
                    ),
                  ),
                  const SizedBox(height: 12),
                  selectField('Category', category, const [
                    'Irrigation',
                    'Trees',
                    'Softscape',
                    'Electrical',
                    'Drainage',
                    'Hardscape',
                    'Other',
                  ], selectCategory),
                  const SizedBox(height: 12),
                  if (category == 'Other')
                    input(
                      'other_category',
                      'Specify Category',
                      73,
                      fieldKey: otherCategoryKey,
                      focusNode: otherCategoryFocus,
                    ),
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
      ),
      actions: [
        TextButton(
          onPressed: saving || picking
              ? null
              : () => Navigator.pop(context, created),
          child: Text(created == null ? 'Cancel' : 'Close'),
        ),
        FilledButton(
          onPressed: saving || picking ? null : submit,
          child: saving
              ? OperationProgress(
                  created == null ? 'Saving…' : 'Uploading photo…',
                )
              : Text(
                  created != null
                      ? 'Retry Photo Upload'
                      : widget.createJob
                      ? 'Create Project'
                      : photo == null
                      ? 'Create Service Request'
                      : 'Create and Upload Photo',
                ),
        ),
      ],
    ),
  );
}

class OperationProgress extends StatelessWidget {
  const OperationProgress(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(height: 4),
        SizedBox(
          width: 98,
          child: LinearProgressIndicator(
            minHeight: 4,
            color: Theme.of(context).colorScheme.primary,
            semanticsLabel: label,
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

class ChangePasswordForm extends StatefulWidget {
  const ChangePasswordForm({super.key, required this.api});
  final Api api;

  @override
  State<ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends State<ChangePasswordForm> {
  final form = GlobalKey<FormState>();
  final current = TextEditingController();
  final replacement = TextEditingController();
  final confirmation = TextEditingController();
  bool saving = false;
  String? error;

  @override
  void dispose() {
    current.dispose();
    replacement.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.api.post('account/password', {
        'current_password': current.text,
        'new_password': replacement.text,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) {
        setState(() {
          saving = false;
          error = failure.toString();
        });
      }
    }
  }

  Widget input(
    TextEditingController controller,
    String label,
    FormFieldValidator<String> validate,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      enabled: !saving,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      maxLength: 256,
      buildCounter:
          (_, {required currentLength, required isFocused, maxLength}) => null,
      validator: validate,
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      scrollable: true,
      title: const Text('Change Password'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Changing your password signs you out on all devices.',
              ),
              const SizedBox(height: 14),
              input(
                current,
                'Current Password',
                (value) => value == null || value.trim().isEmpty
                    ? 'Enter your current password.'
                    : null,
              ),
              input(replacement, 'New Password', (value) {
                if (value == null ||
                    value.length < 14 ||
                    value != value.trim()) {
                  return 'Use at least 14 characters with no leading or trailing spaces.';
                }
                if (value == current.text) {
                  return 'Choose a different password.';
                }
                return null;
              }),
              input(
                confirmation,
                'Confirm New Password',
                (value) => value != replacement.text
                    ? 'The new passwords do not match.'
                    : null,
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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
          onPressed: saving ? null : save,
          child: Text(saving ? 'Saving…' : 'Change Password'),
        ),
      ],
    ),
  );
}

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
          feedback = 'Project access granted.';
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
    title: const Text('Grant Project Access'),
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
