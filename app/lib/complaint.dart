import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'forms.dart';
import 'main.dart';
import 'workspace.dart';
import 'web_dashboard.dart';

const actionLabels = {
  'assign': 'Assign Request',
  'start': 'Start Work',
  'update': 'Update Progress',
  'hold': 'Put on Hold',
  'submit': 'Submit for Verification',
  'verify': 'Verify Work',
  'rework': 'Return for Rework',
  'close': 'Close Request',
  'reopen': 'Reopen Request',
};

const activityLabels = {
  'register': 'Request Created',
  'assign': 'Request Assigned',
  'start': 'Work Started',
  'update': 'Progress Updated',
  'hold': 'Work Put on Hold',
  'submit': 'Submitted for Verification',
  'verify': 'Work Verified',
  'rework': 'Returned for Rework',
  'close': 'Request Closed',
  'reopen': 'Request Reopened',
  'approve_photo': 'Photo Approved for Client',
};

class ComplaintPage extends StatefulWidget {
  const ComplaintPage({
    super.key,
    required this.api,
    required this.user,
    required this.complaint,
    required this.job,
    this.embedded = false,
    this.onChanged,
  });
  final Api api;
  final Data user;
  final Data complaint;
  final Data job;
  final bool embedded;
  final VoidCallback? onChanged;
  @override
  State<ComplaintPage> createState() => _ComplaintPageState();
}

class _ComplaintPageState extends State<ComplaintPage> {
  late Data row = widget.complaint;
  Data? detail;
  String? error;
  bool loading = true;
  String group = 'All staff';
  late bool linked = widget.job['photos_linked'] == true;
  final previews = <String, Future<Uint8List>>{};
  String get id => row['id'] as String;
  String get role => widget.user['role'] as String;
  bool get client => role == 'client';
  bool get reviewer => ['supervisor', 'engineer', 'manager'].contains(role);

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(ComplaintPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.complaint, widget.complaint)) {
      row = widget.complaint;
    }
    if (oldWidget.job['photos_linked'] != widget.job['photos_linked']) {
      linked = widget.job['photos_linked'] == true;
    }
  }

  Future<void> load({bool full = false}) async {
    try {
      final data = await widget.api.get('complaints/$id');
      Data? latest;
      if (full) {
        final workspace = await widget.api.get('workspace');
        latest = records(
          workspace,
          'complaints',
        ).firstWhere((item) => item['id'] == id);
      }
      if (mounted) {
        setState(() {
          detail = data;
          if (data['photos_linked'] is bool) {
            linked = data['photos_linked'] as bool;
          }
          if (latest != null) row = latest;
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  List<String> get actions {
    if (client || detail == null) return [];
    final mine = row['assigned_to'] == widget.user['id'];
    final status = textOf(row, 'status');
    return [
      if (mine && ['assigned', 'on_hold', 'rework'].contains(status)) 'start',
      if (mine && status == 'in_progress') ...['update', 'submit', 'hold'],
      if (reviewer &&
          [
            'open',
            'assigned',
            'in_progress',
            'on_hold',
            'rework',
          ].contains(status))
        'assign',
      if (reviewer && status == 'verification') ...['verify', 'rework'],
      if (role == 'engineer' && status == 'engineer_review') ...[
        'close',
        'rework',
      ],
      if (role == 'engineer' && status == 'closed') 'reopen',
    ];
  }

  Future<void> openAction(String action) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => ActionForm(
        api: widget.api,
        id: id,
        action: action,
        staff: records(detail ?? {}, 'staff'),
        initialProgress: row['progress'] as int? ?? 0,
      ),
    );
    if (changed == true && mounted) {
      await load(full: true);
      if (mounted) widget.onChanged?.call();
    }
  }

  Future<void> addPhoto() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => UploadForm(api: widget.api, id: id),
    );
    if (changed == true && mounted) await load();
  }

  Future<void> approve(Data photo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve Photo for Client'),
        content: const Text(
          'Clients with access to this job can view this photo when the request is closed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve Photo'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await widget.api.post('photos/${photo['id']}/approve', {});
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return webDetails();
    if (kIsWeb) {
      return Scaffold(
        backgroundColor: const Color(0xffedf3f5),
        appBar: AppBar(title: const Text('Request Details')),
        body: ListView(
          padding: const EdgeInsets.all(13),
          children: [webDetails()],
        ),
      );
    }
    return nativeDetails();
  }

  Widget webDetails() {
    final site = textOf(widget.job, 'site');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WebCard(
          integrated: widget.embedded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xffd4f4e3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3,
                            ),
                            child: Text(
                              textOf(row, 'code'),
                              style: const TextStyle(
                                color: webGreen,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          textOf(row, 'title'),
                          style: const TextStyle(
                            color: webInk,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.45,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (actions.length > 1)
                    PopupMenuButton<String>(
                      tooltip: 'More Actions',
                      icon: const Icon(Icons.more_vert_rounded, color: webInk),
                      onSelected: openAction,
                      itemBuilder: (_) => [
                        for (final action in actions.skip(1))
                          PopupMenuItem(
                            value: action,
                            child: Text(actionLabels[action]!),
                          ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 9,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.place_rounded,
                        size: 16,
                        color: webGreen,
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          site,
                          style: const TextStyle(
                            color: webInk,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  StatusTag(row: row),
                  if (row['priority'] != null)
                    PriorityTag(textOf(row, 'priority')),
                ],
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (error != null)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        error!,
                        style: const TextStyle(color: webMuted),
                      ),
                    ),
                    TextButton(
                      onPressed: () => load(full: true),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              if (client) ...[
                const SizedBox(height: 14),
                ClientStageLine(textOf(row, 'status')),
                const SizedBox(height: 10),
                Text(
                  'Received ${uaeTimestamp(row['received_at'])}',
                  style: const TextStyle(color: webMuted, fontSize: 12),
                ),
                if (resolved(row))
                  Text(
                    'Closed ${uaeTimestamp(row['closed_at'])}',
                    style: const TextStyle(color: webMuted, fontSize: 12),
                  ),
              ] else ...[
                const Divider(color: webLine, height: 21),
                webColumns(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const DetailTitle(Icons.subject_rounded, 'Description'),
                      const SizedBox(height: 6),
                      Text(
                        textOf(row, 'description'),
                        style: const TextStyle(
                          color: webInk,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      if (textOf(row, 'required_action').isNotEmpty &&
                          row['required_action'] != row['description']) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Required Action',
                          style: TextStyle(
                            color: webInk,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          textOf(row, 'required_action'),
                          style: const TextStyle(color: webMuted, fontSize: 12),
                        ),
                      ],
                      if (resolved(row) && row['resolution'] != null) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Resolution',
                          style: TextStyle(
                            color: webInk,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          textOf(row, 'resolution'),
                          style: const TextStyle(color: webMuted, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                  deadline(),
                  firstFlex: 60,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 5,
                  children: [
                    if (textOf(row, 'category').isNotEmpty)
                      detailValue('Category', textOf(row, 'category')),
                    if (textOf(row, 'reported_by').isNotEmpty)
                      detailValue('Reported By', textOf(row, 'reported_by')),
                    detailValue('Received', uaeTimestamp(row['received_at'])),
                    detailValue(
                      resolved(row) ? 'Resolution days' : 'Days open',
                      textOf(row, 'days_open'),
                    ),
                  ],
                ),
                const Divider(color: webLine, height: 22),
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline_rounded,
                      color: webGreen,
                      size: 21,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Assigned To',
                            style: TextStyle(
                              color: webMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            textOf(row, 'assignee', 'Unassigned'),
                            style: const TextStyle(
                              color: webInk,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (actions.isNotEmpty)
                      WebAction(
                        label: actionLabels[actions.first]!,
                        icon: Icons.arrow_forward_rounded,
                        onTap: () => openAction(actions.first),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 11),
        if (client)
          gallery()
        else
          webColumns(gallery(), siteSummary(), firstFlex: 65),
        if (!client) ...[
          const SizedBox(height: 11),
          webColumns(activity(), visibility(), firstFlex: 58),
        ],
      ],
    );
  }

  Widget detailValue(String label, String value) => Text.rich(
    TextSpan(
      style: const TextStyle(color: webMuted, fontSize: 11),
      children: [
        TextSpan(
          text: '$label  ',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        TextSpan(text: value),
      ],
    ),
  );

  Widget webColumns(Widget left, Widget right, {required int firstFlex}) =>
      LayoutBuilder(
        builder: (context, size) => size.maxWidth < 420
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [left, const SizedBox(height: 10), right],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: firstFlex, child: left),
                  const SizedBox(width: 10),
                  Expanded(flex: 100 - firstFlex, child: right),
                ],
              ),
      );

  Widget deadline() {
    final due = DateTime.tryParse(textOf(row, 'due_on'));
    final now = DateTime.now().toUtc().add(const Duration(hours: 4));
    final days = due == null
        ? null
        : DateTime.utc(
            due.year,
            due.month,
            due.day,
          ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
    final closed = resolved(row);
    final late = !closed && days != null && days < 0;
    final color = late ? const Color(0xffab2b36) : webGreen;
    final label = closed
        ? 'Closed'
        : days == null
        ? 'No target date'
        : days == 0
        ? 'Due today'
        : late
        ? '${days.abs()} ${days == -1 ? 'day' : 'days'} overdue'
        : '$days ${days == 1 ? 'day' : 'days'} remaining';
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: late ? const Color(0xffffedef) : const Color(0xffe7f8ef),
        border: Border.all(
          color: late ? const Color(0xfff4d4d9) : const Color(0xffd0eedf),
        ),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: LandscapeBands(tint: color)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DetailTitle(
                  closed ? Icons.task_alt_rounded : Icons.timer_outlined,
                  'Due Date',
                  color: color,
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: color,
                  ),
                ),
                if (closed || due != null)
                  Text(
                    closed
                        ? uaeTimestamp(row['closed_at'])
                        : '${row['due_on']} UAE',
                    style: const TextStyle(color: webMuted, fontSize: 11),
                  ),
                if (!closed) ...[
                  const SizedBox(height: 7),
                  LinearProgressIndicator(
                    value: ((row['progress'] as int?) ?? 0) / 100,
                    color: color,
                    backgroundColor: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    minHeight: 5,
                    semanticsLabel: 'Work progress',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget siteSummary() => WebCard(
    inset: widget.embedded,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DetailTitle(Icons.location_on_outlined, 'Site Details'),
        const SizedBox(height: 7),
        Text(
          textOf(widget.job, 'site'),
          style: const TextStyle(
            color: webInk,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          [
            textOf(widget.job, 'location'),
            textOf(widget.job, 'emirate'),
          ].where((part) => part.isNotEmpty).join(' · '),
          style: const TextStyle(color: webMuted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Text(
          textOf(widget.job, 'client_name'),
          style: const TextStyle(color: webMuted, fontSize: 11),
        ),
      ],
    ),
  );

  Widget activity() {
    final events = records(detail ?? {}, 'history');
    return WebCard(
      inset: widget.embedded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DetailTitle(
            Icons.format_list_bulleted_rounded,
            'Activity History',
          ),
          const SizedBox(height: 7),
          if (events.isEmpty)
            Text(
              loading ? 'Loading activity…' : 'No recorded activity.',
              style: const TextStyle(color: webMuted, fontSize: 12),
            ),
          for (final (index, event) in events.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    index == 0
                        ? Icons.radio_button_checked_rounded
                        : Icons.check_circle_rounded,
                    size: 15,
                    color: webGreen,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${activityLabels[event['action']] ?? event['action']} · ${event['actor']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            color: webInk,
                          ),
                        ),
                        if (textOf(event, 'remarks').isNotEmpty)
                          Text(
                            textOf(event, 'remarks'),
                            style: const TextStyle(fontSize: 11, color: webInk),
                          ),
                        Text(
                          uaeTimestamp(event['created_at']),
                          style: const TextStyle(color: webMuted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget visibility() {
    final approved = records(
      detail ?? {},
      'photos',
    ).where((photo) => photo['approved_at'] != null).length;
    return WebCard(
      inset: widget.embedded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DetailTitle(Icons.visibility_outlined, 'Client Visibility'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xffe8f7ef),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.photo_library_outlined,
                  size: 15,
                  color: webGreen,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$approved approved ${approved == 1 ? 'photo' : 'photos'}',
                    style: const TextStyle(
                      color: webGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            resolved(row)
                ? 'Clients with job access see the resolution status and approved photos.'
                : 'Approved photos become visible to clients with job access after closure.',
            style: const TextStyle(color: webMuted, fontSize: 11, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget nativeDetails() => Scaffold(
    appBar: AppBar(title: const Text('Request Details')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 26),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 9,
                        runSpacing: 7,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Icon(
                            categoryIcon(textOf(row, 'category')),
                            size: 21,
                            color: green,
                          ),
                          Text(
                            textOf(row, 'code'),
                            style: const TextStyle(
                              color: muted,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          StatusTag(row: row),
                          if (row['priority'] != null)
                            Text(
                              '${row['priority']} priority',
                              style: const TextStyle(
                                fontSize: 12,
                                color: muted,
                              ),
                            ),
                          if (row['overdue'] == true)
                            const Text(
                              'Overdue',
                              style: TextStyle(
                                color: Color(0xffa52b24),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        textOf(row, 'title'),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${widget.job['site']} · ${widget.job['location']}',
                        style: const TextStyle(color: muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (loading) const LinearProgressIndicator(),
                if (error != null)
                  Panel(
                    child: Row(
                      children: [
                        Expanded(child: Text(error!)),
                        TextButton(
                          onPressed: () => load(full: true),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                if (actions.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (index, action) in actions.indexed)
                        if (index == 0)
                          FilledButton(
                            onPressed: () => openAction(action),
                            child: Text(actionLabels[action]!),
                          )
                        else
                          OutlinedButton(
                            onPressed: () => openAction(action),
                            child: Text(actionLabels[action]!),
                          ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Request Information',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 9),
                      info('Category', textOf(row, 'category')),
                      info('Received', uaeTimestamp(row['received_at'])),
                      if (!client) ...[
                        info('Reported By', textOf(row, 'reported_by')),
                        info(
                          'Assigned To',
                          textOf(row, 'assignee', 'Unassigned'),
                        ),
                        info('Due Date (UAE)', textOf(row, 'due_on')),
                        info('Description', textOf(row, 'description')),
                        info('Required Action', textOf(row, 'required_action')),
                        info('Progress', '${row['progress']}%'),
                        LinearProgressIndicator(
                          value: (row['progress'] as int? ?? 0) / 100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        if (resolved(row))
                          info('Resolution', textOf(row, 'resolution')),
                      ],
                      if (resolved(row))
                        info('Closed', uaeTimestamp(row['closed_at'])),
                      info(
                        resolved(row) ? 'Resolution days' : 'Days open',
                        textOf(row, 'days_open'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                gallery(),
                if (!client && detail != null) ...[
                  const SizedBox(height: 12),
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Activity',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        for (final event in records(detail!, 'history'))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.history,
                              color: green,
                              size: 20,
                            ),
                            title: Text(
                              '${activityLabels[event['action']] ?? event['action']} · ${event['actor']}',
                            ),
                            subtitle: Text(
                              [
                                uaeTimestamp(event['created_at']),
                                textOf(event, 'remarks'),
                              ].where((s) => s.isNotEmpty).join('\n'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget info(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(color: muted, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget gallery() {
    final photos = records(detail ?? {}, 'photos')
        .where(
          (photo) =>
              group == 'All staff' ||
              roleLabels[photo['uploader_role']] == group,
        )
        .toList();
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                client ? 'Approved Photos' : 'CompanyCam Photos',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (!client && linked && !resolved(row))
              TextButton.icon(
                onPressed: addPhoto,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Add Photo'),
              ),
          ],
        ),
        const SizedBox(height: 7),
        if (!client && linked) ...[
          selectField('Uploaded by', group, [
            'All staff',
            for (final entry in roleLabels.entries)
              if (entry.key != 'client') entry.value,
          ], (value) => setState(() => group = value!)),
          const SizedBox(height: 10),
        ],
        if (photos.isEmpty)
          Text(
            !client && !linked
                ? 'CompanyCam is not linked to this job yet.'
                : 'No photos in this view.',
            style: const TextStyle(color: muted),
          ),
        if (photos.isNotEmpty)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final photo in photos)
                SizedBox(
                  width: 155,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FutureBuilder<Uint8List>(
                        future: previews.putIfAbsent(
                          photo['id'] as String,
                          () => widget.api.photo(photo['id'] as String),
                        ),
                        builder: (context, state) => ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            height: 100,
                            width: 155,
                            child: state.hasData
                                ? InkWell(
                                    onTap: () => showDialog<void>(
                                      context: context,
                                      builder: (_) => Dialog(
                                        child: InteractiveViewer(
                                          child: Image.memory(state.data!),
                                        ),
                                      ),
                                    ),
                                    child: Image.memory(
                                      state.data!,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : ColoredBox(
                                    color: canvas,
                                    child: Center(
                                      child: state.hasError
                                          ? const Icon(
                                              Icons.broken_image_outlined,
                                              color: muted,
                                            )
                                          : const CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        textOf(photo, 'stage'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (!client)
                        Text(
                          textOf(photo, 'uploader'),
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                      if (!client && photo['approved_at'] != null)
                        const Text(
                          'Client approved',
                          style: TextStyle(fontSize: 12, color: green),
                        ),
                      if (role == 'engineer' &&
                          photo['approved_at'] == null &&
                          photo['stage'] != 'Progress')
                        TextButton(
                          onPressed: () => approve(photo),
                          child: const Text('Approve Photo'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
    return kIsWeb
        ? WebCard(inset: widget.embedded, child: content)
        : Panel(child: content);
  }
}

class DetailTitle extends StatelessWidget {
  const DetailTitle(this.icon, this.label, {super.key, this.color = webInk});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );
}

String uaeTimestamp(Object? input) {
  final value = DateTime.tryParse(
    input?.toString() ?? '',
  )?.toUtc().add(const Duration(hours: 4));
  if (value == null) return '';
  final stamp = value.toIso8601String();
  return '${stamp.substring(0, 10)} · ${stamp.substring(11, 16)} UAE';
}

class ActionForm extends StatefulWidget {
  const ActionForm({
    super.key,
    required this.api,
    required this.id,
    required this.action,
    required this.staff,
    required this.initialProgress,
  });
  final Api api;
  final String id;
  final String action;
  final List<Data> staff;
  final int initialProgress;
  @override
  State<ActionForm> createState() => _ActionFormState();
}

class _ActionFormState extends State<ActionForm> {
  final remarks = TextEditingController();
  String? assigned;
  String? error;
  late int progress = widget.initialProgress;
  bool saving = false;
  bool get requiresRemarks =>
      ['update', 'hold', 'rework', 'close', 'reopen'].contains(widget.action);

  @override
  void dispose() {
    remarks.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (saving) return;
    if ((requiresRemarks && remarks.text.trim().isEmpty) ||
        (widget.action == 'assign' && assigned == null)) {
      setState(
        () => error = widget.action == 'assign'
            ? 'Choose a staff member.'
            : 'Enter your remarks.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.api.post('complaints/${widget.id}/actions', {
        'action': widget.action,
        'remarks': remarks.text,
        if (widget.action == 'assign') 'assigned_to': assigned,
        if (widget.action == 'update') 'progress': progress,
      });
      if (mounted) Navigator.pop(context, true);
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
      title: Text(actionLabels[widget.action]!),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.action == 'assign') ...[
              DropdownButtonFormField<String>(
                initialValue: assigned,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Assign To'),
                items: [
                  for (final person in widget.staff)
                    DropdownMenuItem(
                      value: person['id'] as String,
                      child: Text(
                        '${person['name']} · ${roleLabels[person['role']]}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => assigned = value),
              ),
              const SizedBox(height: 12),
            ],
            if (widget.action == 'update') ...[
              Text('Progress · $progress%'),
              Slider(
                value: progress.toDouble(),
                min: 0,
                max: 100,
                divisions: 100,
                label: '$progress%',
                onChanged: (value) => setState(() => progress = value.round()),
              ),
            ],
            TextField(
              controller: remarks,
              maxLength: 2000,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: widget.action == 'close'
                    ? 'Resolution Notes'
                    : requiresRemarks
                    ? 'Remarks'
                    : 'Remarks (optional)',
              ),
            ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Color(0xffa52b24))),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : submit,
          child: Text(saving ? 'Saving…' : actionLabels[widget.action]!),
        ),
      ],
    ),
  );
}

class UploadForm extends StatefulWidget {
  const UploadForm({super.key, required this.api, required this.id});
  final Api api;
  final String id;
  @override
  State<UploadForm> createState() => _UploadFormState();
}

class _UploadFormState extends State<UploadForm> {
  String stage = 'Before';
  XFile? image;
  String? requestId;
  String? error;
  bool busy = false;

  Future<void> pick(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2200,
        imageQuality: 85,
      );
      if (mounted && file != null) {
        setState(() {
          image = file;
          requestId = null;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = 'Could not open the photo picker.');
    }
  }

  Future<void> upload() async {
    final photo = image;
    if (photo == null || busy) return;
    final random = Random.secure();
    requestId ??= List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (await photo.length() > 10 * 1024 * 1024) {
        throw const ApiException('Choose a photo under 10 MB.', 413);
      }
      final mime =
          photo.mimeType ??
          (photo.name.toLowerCase().endsWith('.png')
              ? 'image/png'
              : 'image/jpeg');
      await widget.api.upload(
        widget.id,
        stage,
        await photo.readAsBytes(),
        mime,
        requestId!,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Add Photo'),
      content: SizedBox(
        width: 390,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            selectField(
              'Photo Stage',
              stage,
              const ['Before', 'Progress', 'After'],
              (value) {
                if (!busy) {
                  setState(() {
                    stage = value!;
                    requestId = null;
                  });
                }
              },
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!kIsWeb)
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => pick(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Take Photo'),
                  ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => pick(ImageSource.gallery),
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Select Photo'),
                ),
              ],
            ),
            if (image != null)
              Text(image!.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (error != null)
              Text(error!, style: const TextStyle(color: Color(0xffa52b24))),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: image == null || busy ? null : upload,
          child: Text(busy ? 'Uploading…' : 'Upload Photo'),
        ),
      ],
    ),
  );
}
