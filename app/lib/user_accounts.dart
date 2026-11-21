import 'package:flutter/material.dart';

import 'api.dart';

class UserAccounts extends StatefulWidget {
  const UserAccounts({super.key, required this.api});

  final Api api;

  @override
  State<UserAccounts> createState() => _UserAccountsState();
}

class _UserAccountsState extends State<UserAccounts> {
  late Future<Data> accounts = widget.api.get('accounts');

  void reload() {
    final request = widget.api.get('accounts');
    setState(() {
      accounts = request;
    });
  }

  Future<void> editAccount(Data settings, [Data? account]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _AccountForm(api: widget.api, settings: settings, account: account),
    );
    if (saved == true && mounted) {
      reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(account == null ? 'User added.' : 'Account updated.'),
        ),
      );
    }
  }

  Future<void> jobAccess(Data account) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _JobAccessPage(api: widget.api, account: account),
      ),
    );
    if (mounted) reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('User Accounts')),
    body: FutureBuilder<Data>(
      future: accounts,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _LoadError(error: snapshot.error!, onRetry: reload);
        }
        final settings = snapshot.requireData;
        final users = records(settings, 'users');
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (settings['can_add_user'] == true)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: () => editAccount(settings),
                      icon: const Icon(Icons.person_add_outlined),
                      label: const Text('Add User'),
                    ),
                  ),
                const SizedBox(height: 16),
                if (users.isEmpty) const Text('You have no managed accounts.'),
                for (final user in users)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            textOf(user, 'name'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(textOf(user, 'email')),
                          Text(
                            '${roleLabels[user['role']]} · '
                            '${user['active'] == true ? 'Active' : 'Deactivated'}',
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: () => editAccount(settings, user),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Edit Account'),
                              ),
                              TextButton.icon(
                                onPressed: () => jobAccess(user),
                                icon: const Icon(Icons.badge_outlined),
                                label: const Text('Project Access'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _AccountForm extends StatefulWidget {
  const _AccountForm({required this.api, required this.settings, this.account});

  final Api api;
  final Data settings;
  final Data? account;

  @override
  State<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<_AccountForm> {
  late final name = TextEditingController(text: widget.account?['name']);
  final email = TextEditingController();
  final password = TextEditingController();
  late String role = widget.account?['role'] as String? ?? 'foreman';
  late bool active = widget.account?['active'] != false;
  late bool createCredentials =
      widget.settings['can_create_credentials'] == true;
  bool showPassword = false;
  bool saving = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> save(bool enterPassword) async {
    final address = email.text.trim();
    final initialPassword = password.text;
    final validation = name.text.trim().isEmpty
        ? 'Enter the user’s full name.'
        : widget.account == null &&
              !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address)
        ? 'Enter a valid email address.'
        : enterPassword &&
              (initialPassword.length < 14 ||
                  initialPassword.length > 256 ||
                  initialPassword != initialPassword.trim())
        ? 'Use 14–256 characters with no spaces at either end.'
        : null;
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final account = widget.account;
    try {
      await widget.api
          .post(account == null ? 'accounts' : 'accounts/${account['id']}', {
            'name': name.text.trim(),
            'role': role,
            if (account == null) 'email': address else 'active': active,
            if (enterPassword) 'password': initialPassword,
          });
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.account != null;
    final hosted = widget.settings['hosted'] == true;
    final canCreate = widget.settings['can_create_credentials'] == true;
    final enterPassword = !editing && (!hosted || createCredentials);
    return AlertDialog(
      title: Text(editing ? 'Edit Account' : 'Add User'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!editing && hosted) ...[
              if (canCreate)
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Create sign-in')),
                    ButtonSegment(value: false, label: Text('Link existing')),
                  ],
                  selected: {createCredentials},
                  onSelectionChanged: saving
                      ? null
                      : (selection) => setState(() {
                          createCredentials = selection.single;
                          password.clear();
                          showPassword = false;
                          error = null;
                        }),
                ),
              if (!canCreate)
                const Text(
                  'Creating sign-ins is unavailable. You can link a confirmed Supabase account.',
                ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: name,
              maxLength: 160,
              enabled: !saving,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                counterText: '',
              ),
            ),
            if (!editing) ...[
              const SizedBox(height: 12),
              TextField(
                controller: email,
                enabled: !saving,
                keyboardType: TextInputType.emailAddress,
                maxLength: 254,
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  counterText: '',
                  helperText: enterPassword
                      ? 'Verify the address before creating the sign-in.'
                      : 'Use the email of a confirmed Supabase account.',
                ),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: role,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Role'),
              items: [
                for (final entry in roleLabels.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: saving
                  ? null
                  : (value) => setState(() => role = value!),
            ),
            if (editing)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Account Active'),
                value: active,
                onChanged: saving
                    ? null
                    : (value) => setState(() => active = value),
              ),
            if (enterPassword) ...[
              const SizedBox(height: 12),
              TextField(
                controller: password,
                enabled: !saving,
                obscureText: !showPassword,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Initial Password',
                  helperText: 'At least 14 characters',
                  suffixIcon: IconButton(
                    tooltip: showPassword ? 'Hide password' : 'Show password',
                    onPressed: saving
                        ? null
                        : () => setState(() => showPassword = !showPassword),
                    icon: Icon(
                      showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
              ),
            ],
            if (error != null) _FormError(error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : () => save(enterPassword),
          child: Text(
            saving
                ? 'Saving…'
                : editing
                ? 'Save Changes'
                : enterPassword
                ? 'Create Account'
                : 'Link Existing Account',
          ),
        ),
      ],
    );
  }
}

class _JobAccessPage extends StatefulWidget {
  const _JobAccessPage({required this.api, required this.account});

  final Api api;
  final Data account;

  @override
  State<_JobAccessPage> createState() => _JobAccessPageState();
}

class _JobAccessPageState extends State<_JobAccessPage> {
  late Future<Data> accounts = widget.api.get('accounts');

  void reload() => setState(() => accounts = widget.api.get('accounts'));

  Future<void> edit(Data job, Data? grant) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _JobAccessForm(
        api: widget.api,
        account: widget.account,
        job: job,
        grant: grant,
      ),
    );
    if (changed == true && mounted) reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Project Access')),
    body: FutureBuilder<Data>(
      future: accounts,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _LoadError(error: snapshot.error!, onRetry: reload);
        }
        final settings = snapshot.requireData;
        final grants = {
          for (final grant in records(settings, 'grants'))
            if (grant['user_id'] == widget.account['id'])
              grant['job_id']: grant,
        };
        final jobs = records(settings, 'jobs');
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  textOf(widget.account, 'name'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                if (jobs.isEmpty)
                  const Text('You have no projects available to share.'),
                for (final job in jobs)
                  Card(
                    child: ListTile(
                      title: Text(textOf(job, 'site')),
                      subtitle: Text(
                        '${textOf(job, 'code')} · ${_status(grants[job['id']])}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => edit(job, grants[job['id']]),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );

  String _status(Data? grant) {
    if (grant == null) return 'No Access';
    final now = DateTime.now();
    if (_date(grant['visible_until'])?.isAfter(now) == false) return 'Expired';
    if (_date(grant['visible_from'])?.isAfter(now) == true) return 'Scheduled';
    return 'Access Granted';
  }
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

class _JobAccessForm extends StatefulWidget {
  const _JobAccessForm({
    required this.api,
    required this.account,
    required this.job,
    this.grant,
  });

  final Api api;
  final Data account;
  final Data job;
  final Data? grant;

  @override
  State<_JobAccessForm> createState() => _JobAccessFormState();
}

class _JobAccessFormState extends State<_JobAccessForm> {
  late DateTime? start = _date(widget.grant?['visible_from']);
  late DateTime? end = _date(widget.grant?['visible_until']);
  bool saving = false;
  String? error;

  Future<void> pick({required bool isStart}) async {
    final existing = isStart ? start : end;
    final now = DateTime.now();
    final initial = existing != null && existing.isAfter(now) ? existing : now;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (!mounted || selected == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted || time == null) return;
    final value = DateTime(
      selected.year,
      selected.month,
      selected.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (isStart) {
        start = value;
      } else {
        end = value;
      }
    });
  }

  Future<void> save({required bool grant}) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.api
          .post('accounts/${widget.account['id']}/jobs/${widget.job['id']}', {
            'granted': grant,
            'visible_from': start?.toUtc().toIso8601String(),
            'visible_until': end?.toUtc().toIso8601String(),
          });
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final limit = _date(widget.job['visible_until']);
    return AlertDialog(
      title: Text(textOf(widget.job, 'site')),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dates and times use your device time zone (${DateTime.now().timeZoneName}).',
            ),
            if (limit != null) Text('Your access ends ${format(limit)}.'),
            dateRow('Access Starts', start, 'Immediately', true),
            dateRow('Access Ends', end, 'No End Date', false),
            if (error != null) _FormError(error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (widget.grant != null)
          TextButton(
            onPressed: saving ? null : () => save(grant: false),
            child: const Text('Revoke Access'),
          ),
        FilledButton(
          onPressed: saving ? null : () => save(grant: true),
          child: Text(saving ? 'Saving…' : 'Save Access'),
        ),
      ],
    );
  }

  String format(DateTime value) {
    final labels = MaterialLocalizations.of(context);
    return '${labels.formatMediumDate(value)} · '
        '${labels.formatTimeOfDay(TimeOfDay.fromDateTime(value))}';
  }

  Widget dateRow(
    String label,
    DateTime? value,
    String fallback,
    bool isStart,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.date_range_outlined),
    title: Text(label),
    subtitle: Text(value == null ? fallback : format(value)),
    onTap: saving ? null : () => pick(isStart: isStart),
    trailing: value == null
        ? const Icon(Icons.chevron_right)
        : IconButton(
            tooltip: 'Clear Date',
            onPressed: saving
                ? null
                : () => setState(() {
                    if (isStart) {
                      start = null;
                    } else {
                      end = null;
                    }
                  }),
            icon: const Icon(Icons.clear),
          ),
  );
}

class _FormError extends StatelessWidget {
  const _FormError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FormError(error.toString()),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
