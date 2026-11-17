import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'main.dart';
import 'complaint.dart';
import 'forms.dart';
import 'download.dart';
import 'web_dashboard.dart';
import 'ui_labels.dart';
import 'report_analytics.dart';

const _reportStatuses = [
  ('All', 'All Statuses'),
  ('Open', 'Open'),
  ('In progress', 'In Progress'),
  ('Closed', 'Closed'),
  ('Active', 'All Unclosed'),
];

class Workspace extends StatefulWidget {
  const Workspace({
    super.key,
    required this.api,
    required this.user,
    required this.onSignOut,
  });
  final Api api;
  final Data user;
  final VoidCallback onSignOut;
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  Data? snapshot;
  String? error;
  String search = '';
  String filter = 'All';
  String reportStatus = 'All';
  String? jobFilter;
  String? staffFilter;
  int tab = 0;
  bool busy = false;
  String? selectedComplaint;
  final webSearch = TextEditingController();
  bool get client => widget.user['role'] == 'client';
  bool get canReport =>
      ['engineer', 'manager', 'supervisor'].contains(widget.user['role']);
  List<Data> get jobs => records(snapshot ?? {}, 'jobs');
  List<Data> get complaints => records(snapshot ?? {}, 'complaints');
  Map<String, String> get assignees => {
    for (final row in complaints)
      if (row['assigned_to'] case final String id)
        id: textOf(row, 'assignee', 'Staff'),
    for (final person in records(snapshot ?? {}, 'staff'))
      textOf(person, 'id'): textOf(person, 'name'),
  };

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    webSearch.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.get('workspace');
      if (mounted) {
        setState(() {
          snapshot = result;
          if (staffFilter != null &&
              staffFilter != 'unassigned' &&
              !assignees.containsKey(staffFilter)) {
            staffFilter = null;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Data jobFor(Data complaint) => jobs.firstWhere(
    (job) => job['id'] == complaint['job_id'],
    orElse: () => {},
  );

  Future<void> open(Data complaint) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ComplaintPage(
          api: widget.api,
          user: widget.user,
          complaint: complaint,
          job: jobFor(complaint),
        ),
      ),
    );
    if (mounted) await refresh();
  }

  Future<void> create({bool job = false}) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => EntryForm(api: widget.api, jobs: jobs, createJob: job),
    );
    if (changed == true && mounted) {
      setState(() {
        tab = job ? 2 : 1;
        filter = 'All';
        search = '';
        webSearch.clear();
        jobFilter = null;
        staffFilter = null;
      });
      await refresh();
    }
  }

  Future<void> linkPhotos(Data job) async {
    if (busy) return;
    setState(() => busy = true);
    String message;
    try {
      await widget.api.post('jobs/${job['id']}/companycam', {});
      message = 'CompanyCam project linked.';
    } catch (failure) {
      message = failure.toString();
    }
    if (!mounted) return;
    setState(() => busy = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    await refresh();
  }

  Future<void> export(String format, {String? scope}) async {
    try {
      final report = await widget.api.report(format, {
        'scope': scope ?? filter,
        'search': search.trim(),
        'job': ?jobFilter,
        'assignee': ?staffFilter,
      });
      if (mounted) downloadReport(report.bytes, format, report.filename);
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.toString())));
      }
    }
  }

  void showQueue(String value, {String? jobId}) {
    setState(() {
      tab = 1;
      filter = value;
      search = '';
      webSearch.clear();
      jobFilter = jobId;
      staffFilter = null;
    });
  }

  bool matches(Data row, [String? scope]) {
    if (staffFilter != null && staffKey(row) != staffFilter) return false;
    return matchesScope(row, scope ?? filter);
  }

  bool matchesScope(Data row, String scope) {
    if (jobFilter != null && row['job_id'] != jobFilter) return false;
    final selected = switch (scope) {
      'My assigned' =>
        row['assigned_to'] == widget.user['id'] && !resolved(row),
      'Active' => !resolved(row),
      'Open' => row['status'] == 'open',
      'In progress' => row['status'] == 'in_progress',
      'Overdue' => row['overdue'] == true,
      'Closed' || 'Solved' => resolved(row),
      _ => true,
    };
    final term = search.trim().toLowerCase();
    final job = jobFor(row);
    return selected &&
        [
          row['code'],
          row['title'],
          row['category'],
          job['site'],
          job['location'],
          job['code'],
          job['client_name'],
        ].any(
          (value) => value?.toString().toLowerCase().contains(term) ?? false,
        );
  }

  String staffKey(Data row) => (row['assigned_to'] as String?) ?? 'unassigned';

  Widget staffPicker({String? scope}) {
    final matching = complaints.where(
      (row) => matchesScope(row, scope ?? filter),
    );
    final counts = <String, int>{};
    for (final row in matching) {
      counts.update(staffKey(row), (count) => count + 1, ifAbsent: () => 1);
    }
    final people = assignees.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    final names = <String, int>{};
    for (final person in people) {
      names.update(person.value, (count) => count + 1, ifAbsent: () => 1);
    }
    final choices = [
      (
        'all',
        'All Assignees',
        counts.values.fold(0, (total, count) => total + count),
      ),
      for (final person in people)
        (
          person.key,
          names[person.value] == 1
              ? person.value
              : '${person.value} · ${person.key.split('-').last.substring(0, 6)}',
          counts[person.key] ?? 0,
        ),
      ('unassigned', 'Unassigned', counts['unassigned'] ?? 0),
    ];
    return DropdownButtonFormField<String>(
      key: ValueKey(staffFilter),
      initialValue: staffFilter ?? 'all',
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Assigned To',
        prefixIcon: Icon(Icons.person_outline_rounded, size: 19),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: [
        for (final (id, label, count) in choices)
          DropdownMenuItem(
            value: id,
            child: Text('$label ($count)', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) => setState(() {
        staffFilter = value == 'all' ? null : value;
        selectedComplaint = null;
      }),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, space) {
      if (kIsWeb) return webWorkspace(space.maxWidth >= 1060);
      final wide = space.maxWidth >= 960;
      final visibleTabs = [0, 1, 2, if (!client) 3, 4];
      final name = textOf(widget.user, 'name');
      final avatar = CircleAvatar(
        radius: 18,
        backgroundColor: const Color(0xffdff0e0),
        child: Text(
          name
              .split(' ')
              .where((part) => part.isNotEmpty)
              .take(2)
              .map((part) => part[0])
              .join(),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: green,
          ),
        ),
      );
      final label = client && tab == 0
          ? 'Client Portal'
          : workspaceDestinations[tab].$2;
      return Scaffold(
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                height: 65,
                backgroundColor: Colors.white,
                selectedIndex: visibleTabs.indexOf(tab),
                onDestinationSelected: (index) =>
                    setState(() => tab = visibleTabs[index]),
                destinations: [
                  for (final index in visibleTabs)
                    NavigationDestination(
                      icon: Icon(workspaceDestinations[index].$1),
                      label: workspaceDestinations[index].$2,
                    ),
                ],
              ),
        body: SafeArea(
          child: Row(
            children: [
              if (wide)
                Container(
                  width: 226,
                  color: const Color(0xff102e23),
                  padding: const EdgeInsets.fromLTRB(18, 24, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 9),
                        child: Brand(inverse: true),
                      ),
                      const SizedBox(height: 9),
                      const Padding(
                        padding: EdgeInsets.only(left: 9),
                        child: Text(
                          'Reactive Maintenance Control',
                          style: TextStyle(
                            color: Color(0xffb8cec0),
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(height: 38),
                      for (final index in visibleTabs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: ListTile(
                            selected: index == tab,
                            selectedTileColor: const Color(0xff28513d),
                            iconColor: const Color(0xffb4cbbd),
                            textColor: const Color(0xffe0ebe3),
                            selectedColor: Colors.white,
                            dense: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9),
                            ),
                            leading: Icon(
                              workspaceDestinations[index].$1,
                              size: 21,
                            ),
                            title: Text(workspaceDestinations[index].$2),
                            onTap: () => setState(() => tab = index),
                          ),
                        ),
                      const Spacer(),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        leading: avatar,
                        title: Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          roleLabels[widget.user['role']] ?? '',
                          style: const TextStyle(
                            color: Color(0xffb8cec0),
                            fontSize: 11,
                          ),
                        ),
                        onTap: () => setState(() => tab = 4),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      height: 65,
                      color: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 17),
                      child: Row(
                        children: [
                          if (wide)
                            Text(
                              label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            )
                          else
                            const Brand(),
                          const Spacer(),
                          if (Api.demo)
                            const Padding(
                              padding: EdgeInsets.only(right: 12),
                              child: Text(
                                'Demo',
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                            ),
                          IconButton(
                            tooltip: 'Refresh',
                            onPressed: busy ? null : refresh,
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => setState(() => tab = 4),
                            customBorder: const CircleBorder(),
                            child: avatar,
                          ),
                        ],
                      ),
                    ),
                    if (busy)
                      const LinearProgressIndicator(minHeight: 2)
                    else
                      const Divider(height: 1, color: line),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: refresh,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            wide ? 29 : 16,
                            22,
                            wide ? 29 : 16,
                            34,
                          ),
                          children: [
                            if (error != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Panel(
                                  child: Row(
                                    children: [
                                      Expanded(child: Text(error!)),
                                      TextButton(
                                        onPressed: refresh,
                                        child: const Text('Retry'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (snapshot != null || tab == 4)
                              switch (tab) {
                                0 => overview(wide, name),
                                1 => register(wide),
                                2 => jobList(),
                                3 => alerts(),
                                _ => profile(),
                              },
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget webWorkspace(bool desktop) {
    final name = textOf(widget.user, 'name');
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0])
        .join();
    final role = roleLabels[widget.user['role']] ?? '';
    final board = tab == 0 || tab == 1;
    final avatar = CircleAvatar(
      radius: 17,
      backgroundColor: const Color(0xffd8efe6),
      foregroundColor: webGreen,
      child: Text(
        initials,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xffedf3f5),
      body: SafeArea(
        child: Row(
          children: [
            if (desktop)
              WebSidebar(
                selected: tab,
                client: client,
                reports: canReport,
                onSelect: (value) => setState(() => tab = value),
                onSignOut: widget.onSignOut,
              ),
            Expanded(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xfff6f8fb),
                      Color(0xffedf3f5),
                      Color(0xffe4efef),
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      height: 64,
                      padding: EdgeInsets.symmetric(
                        horizontal: desktop ? 21 : 15,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .85),
                        border: const Border(
                          bottom: BorderSide(color: webLine),
                        ),
                      ),
                      child: Row(
                        children: [
                          if (!desktop) ...[
                            const Brand(),
                            if (client)
                              const Padding(
                                padding: EdgeInsets.only(left: 9),
                                child: Text(
                                  'Client Portal',
                                  style: TextStyle(
                                    color: webMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                          const Spacer(),
                          if (desktop)
                            SizedBox(
                              width: 280,
                              height: 38,
                              child: webSearchBox(),
                            ),
                          if (Api.demo)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                'Demo',
                                style: TextStyle(color: webMuted, fontSize: 11),
                              ),
                            ),
                          if (desktop && !client)
                            IconButton(
                              tooltip: 'Alerts',
                              onPressed: () => setState(() => tab = 3),
                              icon: const Icon(
                                Icons.notifications_none_rounded,
                                color: webInk,
                              ),
                            ),
                          if (desktop) ...[
                            IconButton(
                              tooltip: 'Refresh',
                              onPressed: busy ? null : refresh,
                              icon: const Icon(
                                Icons.refresh_rounded,
                                color: webInk,
                                size: 19,
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => setState(() => tab = 4),
                              child: Row(
                                children: [
                                  avatar,
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          color: webInk,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      Text(
                                        role,
                                        style: const TextStyle(
                                          color: webMuted,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 5),
                                  const Icon(
                                    Icons.expand_more_rounded,
                                    color: webInk,
                                    size: 17,
                                  ),
                                ],
                              ),
                            ),
                          ] else
                            PopupMenuButton<int>(
                              tooltip: 'Open Menu',
                              icon: const Icon(
                                Icons.menu_rounded,
                                color: webInk,
                              ),
                              onSelected: (value) {
                                if (value == 6) {
                                  widget.onSignOut();
                                  return;
                                }
                                setState(() => tab = value);
                              },
                              itemBuilder: (_) => [
                                for (final index in [
                                  0,
                                  2,
                                  1,
                                  if (!client) 3,
                                  if (canReport) 5,
                                  4,
                                ])
                                  PopupMenuItem(
                                    value: index,
                                    child: Text(
                                      workspaceDestinations[index].$2,
                                    ),
                                  ),
                                const PopupMenuItem(
                                  value: 6,
                                  child: Text(signOutLabel),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    if (busy) const LinearProgressIndicator(minHeight: 2),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: refresh,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            desktop ? 20 : 13,
                            desktop ? 15 : 12,
                            desktop ? 20 : 13,
                            28,
                          ),
                          children: [
                            if (error != null)
                              WebCard(
                                child: Row(
                                  children: [
                                    Expanded(child: Text(error!)),
                                    TextButton(
                                      onPressed: refresh,
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              ),
                            if (snapshot != null || tab == 4)
                              if (board)
                                webBoard(desktop)
                              else
                                switch (tab) {
                                  2 => jobList(),
                                  3 => alerts(),
                                  5 => webReports(),
                                  _ => profile(),
                                },
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget webSearchBox() => TextField(
    controller: webSearch,
    style: const TextStyle(color: webInk, fontSize: 13),
    decoration: InputDecoration(
      hintText: 'Search jobs, sites, or requests',
      hintStyle: const TextStyle(color: webMuted, fontSize: 12),
      prefixIcon: const Icon(Icons.search_rounded, size: 19, color: webInk),
      suffixIcon: search.isEmpty
          ? null
          : IconButton(
              tooltip: 'Clear Search',
              icon: const Icon(Icons.close, size: 16),
              onPressed: () {
                webSearch.clear();
                setState(() => search = '');
              },
            ),
      fillColor: const Color(0xfff1f5f9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
    ),
    onChanged: (value) => setState(() {
      search = value;
      if (tab != 0 && tab != 1) tab = 1;
    }),
  );

  Widget webBoard(bool desktop) {
    final active = complaints.where((row) => !resolved(row)).length;
    final progress = complaints
        .where((row) => row['status'] == 'in_progress')
        .length;
    final overdue = complaints.where((row) => row['overdue'] == true).length;
    final done = complaints.length - active;
    final assignmentFilter = !client && (tab == 1 || staffFilter != null)
        ? staffPicker()
        : null;
    final rows = complaints.where(matches).toList();
    final selected = rows.isEmpty
        ? null
        : rows.firstWhere(
            (row) => row['id'] == selectedComplaint,
            orElse: () => rows.first,
          );
    final filters = [
      for (final (id, label) in [
        ('All', 'All Statuses'),
        ('Open', 'Open'),
        if (!client) ('Active', 'All Unclosed'),
        ('In progress', 'In Progress'),
        if (!client) ('Overdue', 'Overdue'),
        (client ? 'Solved' : 'Closed', 'Closed'),
        if (!client) ('My assigned', 'Assigned to Me'),
      ])
        (id, label, complaints.where((row) => matches(row, id)).length),
    ];
    void selectFilter(String value) => setState(() {
      filter = value;
      selectedComplaint = null;
    });
    final metrics = [
      (
        'Unclosed Requests',
        active,
        Icons.chat_bubble_outline_rounded,
        const Color(0xff00864c),
        const Color(0xffe5f7f0),
        'Active',
      ),
      (
        'In Progress',
        progress,
        Icons.build_outlined,
        const Color(0xff086ed8),
        const Color(0xffeaf3ff),
        'In progress',
      ),
      if (!client)
        (
          'Overdue',
          overdue,
          Icons.alarm_rounded,
          const Color(0xffcf3946),
          const Color(0xffffedf0),
          'Overdue',
        ),
      (
        'Closed',
        done,
        Icons.check_rounded,
        const Color(0xff039054),
        const Color(0xffe6f8ef),
        client ? 'Solved' : 'Closed',
      ),
    ];
    final engineer = widget.user['role'] == 'engineer';
    final primary = engineer
        ? WebAction(
            label: newJobLabel,
            icon: Icons.add,
            onTap: () => create(job: true),
          )
        : !client && jobs.isNotEmpty
        ? WebAction(
            label: newServiceRequestLabel,
            icon: Icons.add,
            onTap: () => create(),
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (client && !desktop)
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xff004135), Color(0xff008054)],
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Stack(
              children: [
                const Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: LandscapeBands(tint: Color(0xff5bdfa5)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tab == 1 ? 'My Service Requests' : 'My Jobs',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.4,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Track maintenance requests and resolutions at your sites.',
                        style: TextStyle(
                          color: Color(0xffe1f4e9),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          DashboardHeading(
            tab == 1 ? 'Service Requests' : 'Dashboard',
            client
                ? 'Maintenance requests at your assigned sites.'
                : 'Reactive maintenance · Service requests, jobs and resolution tracking',
            action: tab == 1 && !client && jobs.isNotEmpty
                ? WebAction(
                    label: newServiceRequestLabel,
                    icon: Icons.add,
                    onTap: () => create(),
                  )
                : primary,
          ),
        if (tab == 0 && (desktop || !client)) ...[
          const SizedBox(height: 15),
          MetricCards(
            columns: desktop ? metrics.length : 2,
            metrics: [
              for (final (label, value, icon, accent, tint, scope) in metrics)
                MetricTile(
                  label: label,
                  value: value,
                  icon: icon,
                  accent: accent,
                  tint: tint,
                  selected: filter == scope,
                  onTap: () => selectFilter(scope),
                ),
            ],
          ),
        ],
        if (engineer && tab == 0 && !desktop && jobs.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => create(),
              icon: const Icon(Icons.add, size: 17),
              label: const Text(newServiceRequestLabel),
            ),
          ),
        const SizedBox(height: 14),
        if (desktop)
          WebWorkbench(
            queue: WebQueue(
              rows: rows,
              active: complaints.where((row) => matches(row, 'Active')).length,
              filter: filter,
              filters: filters,
              selected: selected?['id'] as String?,
              client: client,
              jobFor: jobFor,
              onSelect: (row) =>
                  setState(() => selectedComplaint = row['id'] as String),
              onFilter: selectFilter,
              onExport: canReport ? export : null,
              onClearJob: () => setState(() => jobFilter = null),
              jobLabel: jobLabel,
              assignmentFilter: assignmentFilter,
              assignee: staffFilter,
            ),
            detail: selected == null
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Select a service request to view its details.',
                      style: TextStyle(color: webMuted),
                    ),
                  )
                : ComplaintPage(
                    key: ValueKey(selected['id']),
                    api: widget.api,
                    user: widget.user,
                    complaint: selected,
                    job: jobFor(selected),
                    embedded: true,
                    onChanged: refresh,
                  ),
          )
        else ...[
          SizedBox(height: 42, child: webSearchBox()),
          const SizedBox(height: 9),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final (id, label, count) in filters)
                FilterPill(
                  label: '$label ($count)',
                  selected: filter == id,
                  onTap: () => selectFilter(id),
                ),
              if (jobLabel != null)
                InputChip(
                  label: Text(jobLabel!),
                  onDeleted: () => setState(() => jobFilter = null),
                ),
            ],
          ),
          const SizedBox(height: 9),
          if (assignmentFilter != null) ...[
            assignmentFilter,
            const SizedBox(height: 9),
          ],
          if (rows.isEmpty)
            const WebCard(
              child: Text('No service requests match these filters.'),
            ),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: mobileWebRow(row),
            ),
        ],
      ],
    );
  }

  String? get jobLabel {
    for (final job in jobs) {
      if (job['id'] == jobFilter) return textOf(job, 'site');
    }
    return null;
  }

  Widget mobileWebRow(Data row) => WebCard(
    padding: EdgeInsets.zero,
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => open(row),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      textOf(row, 'code'),
                      style: const TextStyle(
                        color: webGreen,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (!client) ...[
                    PriorityTag(textOf(row, 'priority')),
                    const SizedBox(width: 5),
                  ],
                  StatusTag(row: row),
                ],
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      textOf(row, 'title'),
                      style: const TextStyle(
                        color: webInk,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: webMuted),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 15, color: webGreen),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      textOf(jobFor(row), 'site'),
                      style: const TextStyle(color: webMuted, fontSize: 12),
                    ),
                  ),
                ],
              ),
              if (client) ...[
                const SizedBox(height: 10),
                ClientStageLine(textOf(row, 'status')),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Widget webReports() {
    final rows = complaints.where((row) => matches(row, reportStatus)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DashboardHeading(
          'Reports',
          'Review service requests by status and assignee, then export the filtered results.',
        ),
        const SizedBox(height: 15),
        WebCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Service Request Report',
                style: TextStyle(
                  color: webInk,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Status',
                style: TextStyle(color: webInk, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final (scope, label) in _reportStatuses)
                    FilterPill(
                      label: label,
                      selected: reportStatus == scope,
                      onTap: () => setState(() => reportStatus = scope),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 350),
                child: staffPicker(scope: reportStatus),
              ),
              if (jobLabel != null || search.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    if (jobLabel != null)
                      InputChip(
                        label: Text(jobLabel!),
                        onDeleted: () => setState(() => jobFilter = null),
                      ),
                    if (search.isNotEmpty)
                      InputChip(
                        label: Text('Search: $search'),
                        onDeleted: () => setState(() {
                          search = '';
                          webSearch.clear();
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Text(
                '${rows.length} matching ${rows.length == 1 ? 'service request' : 'service requests'}',
                style: const TextStyle(color: webMuted),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 7,
                children: [
                  WebAction(
                    label: downloadExcelLabel,
                    icon: Icons.download_rounded,
                    onTap: () => export('xlsx', scope: reportStatus),
                  ),
                  OutlinedButton(
                    onPressed: () => export('pdf', scope: reportStatus),
                    child: const Text(downloadPdfLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ReportAnalytics(
          key: ValueKey((reportStatus, staffFilter, jobFilter, search)),
          rows: rows,
          selectedAssignee: staffFilter,
          onAssigneeSelected: (value) => setState(() {
            staffFilter = value;
            selectedComplaint = null;
          }),
        ),
      ],
    );
  }

  Widget overview(bool wide, String name) {
    final active = complaints.where((row) => !resolved(row)).length;
    final progress = complaints
        .where((row) => row['status'] == 'in_progress')
        .length;
    final overdue = complaints.where((row) => row['overdue'] == true).length;
    final stats = [
      (
        'Unclosed Requests',
        active,
        Icons.assignment_outlined,
        const Color(0xffe2f1e4),
        green,
        'Active',
      ),
      (
        'In Progress',
        progress,
        Icons.timelapse_rounded,
        const Color(0xffe1eff8),
        const Color(0xff225e83),
        'In progress',
      ),
      (
        'Closed',
        complaints.length - active,
        Icons.task_alt_rounded,
        const Color(0xffecf4de),
        green,
        client ? 'Solved' : 'Closed',
      ),
      if (!client)
        (
          'Overdue',
          overdue,
          Icons.warning_amber_rounded,
          const Color(0xfffff1da),
          const Color(0xff9a5815),
          'Overdue',
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeading(
          client ? 'Your maintenance requests' : 'Dashboard',
          client
              ? 'Track maintenance at your assigned locations.'
              : 'Welcome, ${name.split(' ').first}.',
          action: wide && !client
              ? FilledButton.icon(
                  onPressed: jobs.isEmpty ? null : () => create(),
                  icon: const Icon(Icons.add),
                  label: const Text(newServiceRequestLabel),
                )
              : null,
        ),
        const SizedBox(height: 20),
        if (!client) ...[
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              gradient: const LinearGradient(
                colors: [Color(0xff13392a), Color(0xff257453)],
              ),
            ),
            child: Stack(
              children: [
                const Positioned.fill(
                  child: CustomPaint(painter: GardenLines()),
                ),
                Padding(
                  padding: EdgeInsets.all(wide ? 27 : 19),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Maintenance at a glance',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '$active active ${active == 1 ? 'service request' : 'service requests'} across ${jobs.length} assigned ${jobs.length == 1 ? 'job' : 'jobs'}.',
                        style: const TextStyle(
                          color: Color(0xffe1f2e6),
                          fontSize: 14,
                        ),
                      ),
                      if (!wide && jobs.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed: () => create(),
                          icon: const Icon(Icons.add),
                          label: const Text(newServiceRequestLabel),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        LayoutBuilder(
          builder: (context, space) {
            final columns = space.maxWidth >= 660 ? stats.length : 2;
            return Wrap(
              spacing: 11,
              runSpacing: 11,
              children: [
                for (final (label, count, icon, fill, color, value) in stats)
                  SizedBox(
                    width: (space.maxWidth - 11 * (columns - 1)) / columns,
                    child: Panel(
                      onTap: () => showQueue(value),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: fill,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(icon, color: color, size: 19),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            '$count',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 27,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            label,
                            style: const TextStyle(color: muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Recent Service Requests',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
              ),
            ),
            TextButton(
              onPressed: () => showQueue('All'),
              child: const Text('View All Requests'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        queue(complaints.take(5).toList(), wide),
      ],
    );
  }

  Widget register(bool wide) {
    final shown = complaints.where(matches).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeading(
          'Service Requests',
          '${shown.length} ${shown.length == 1 ? 'request' : 'requests'}',
          action: client || jobs.isEmpty
              ? null
              : FilledButton.icon(
                  onPressed: () => create(),
                  icon: const Icon(Icons.add),
                  label: Text(newServiceRequestLabel),
                ),
        ),
        const SizedBox(height: 17),
        TextFormField(
          key: ValueKey(jobFilter),
          initialValue: search,
          decoration: const InputDecoration(
            hintText: 'Search by request number, site, or title',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => search = value),
        ),
        const SizedBox(height: 10),
        if (!client) ...[staffPicker(), const SizedBox(height: 10)],
        Wrap(
          spacing: 7,
          runSpacing: 3,
          children: [
            for (final (value, label) in [
              ('All', 'All Statuses'),
              if (!client) ('My assigned', 'Assigned to Me'),
              ('Open', 'Open'),
              ('Active', 'All Unclosed'),
              ('In progress', 'In Progress'),
              if (!client) ('Overdue', 'Overdue'),
              (client ? 'Solved' : 'Closed', 'Closed'),
            ])
              ChoiceChip(
                label: Text(label),
                selected: filter == value,
                onSelected: (_) => setState(() => filter = value),
              ),
            if (jobFilter != null)
              InputChip(
                label: Text(
                  jobs.firstWhere((job) => job['id'] == jobFilter)['site']
                      as String,
                ),
                onDeleted: () => setState(() => jobFilter = null),
              ),
            if (kIsWeb &&
                [
                  'engineer',
                  'manager',
                  'supervisor',
                ].contains(widget.user['role']))
              PopupMenuButton<String>(
                tooltip: 'Download Service Request Report',
                onSelected: export,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'xlsx', child: Text(downloadExcelLabel)),
                  PopupMenuItem(value: 'pdf', child: Text(downloadPdfLabel)),
                ],
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 9, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.file_download_outlined, size: 17),
                      SizedBox(width: 5),
                      Text('Export'),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        queue(shown, wide),
      ],
    );
  }

  Widget queue(List<Data> rows, bool wide) {
    if (rows.isEmpty) {
      return const Panel(
        child: Text(
          'No service requests match this view.',
          style: TextStyle(color: muted),
        ),
      );
    }
    return Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          if (wide)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 18, 12),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      'Service Request',
                      style: TextStyle(
                        color: muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Site',
                      style: TextStyle(
                        color: muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 145,
                    child: Text(
                      'Status',
                      style: TextStyle(
                        color: muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(width: 22),
                ],
              ),
            ),
          for (final (index, row) in rows.indexed) ...[
            if (wide || index > 0) const Divider(height: 1, color: line),
            InkWell(
              onTap: () => open(row),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 39,
                      height: 39,
                      decoration: BoxDecoration(
                        color: const Color(0xffe8f2e8),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        categoryIcon(textOf(row, 'category')),
                        size: 20,
                        color: green,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            textOf(row, 'code'),
                            style: const TextStyle(
                              fontSize: 11,
                              color: muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            textOf(row, 'title'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (!wide)
                            Text(
                              textOf(jobFor(row), 'site'),
                              style: const TextStyle(
                                color: muted,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                            ),
                        ],
                      ),
                    ),
                    if (wide)
                      Expanded(
                        flex: 3,
                        child: Text(
                          textOf(jobFor(row), 'site'),
                          style: const TextStyle(color: muted),
                        ),
                      ),
                    SizedBox(
                      width: wide ? 145 : 96,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: StatusTag(row: row),
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: muted, size: 20),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget jobList() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PageHeading(
        'Jobs',
        'Locations you can access.',
        action: widget.user['role'] == 'engineer'
            ? FilledButton.icon(
                onPressed: () => create(job: true),
                icon: const Icon(Icons.add),
                label: const Text(newJobLabel),
              )
            : null,
      ),
      const SizedBox(height: 17),
      if (jobs.isEmpty)
        const Panel(child: Text('No jobs have been assigned to this account.')),
      for (final job in jobs)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Panel(
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, color: green),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        textOf(job, 'site'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${job['code']} · ${job['location']}',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (widget.user['role'] == 'engineer' &&
                    job['photos_linked'] != true)
                  IconButton(
                    tooltip: 'Link CompanyCam Project',
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    onPressed: busy ? null : () => linkPhotos(job),
                  ),
                if (widget.user['role'] == 'engineer')
                  IconButton(
                    tooltip: 'Grant Job Access',
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => AccessForm(api: widget.api, job: job),
                    ),
                  ),
                IconButton(
                  tooltip: 'View Job Requests',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => showQueue('All', jobId: job['id'] as String),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget alerts() {
    final attention = complaints
        .where(
          (row) =>
              row['overdue'] == true ||
              (row['assigned_to'] == widget.user['id'] && !resolved(row)) ||
              ([
                    'supervisor',
                    'engineer',
                    'manager',
                  ].contains(widget.user['role']) &&
                  row['status'] == 'verification') ||
              (widget.user['role'] == 'engineer' &&
                  row['status'] == 'engineer_review'),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeading(
          'Alerts',
          'Assignments, overdue work and pending reviews.',
        ),
        const SizedBox(height: 16),
        queue(attention, false),
      ],
    );
  }

  Widget profile() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const PageHeading('Profile', 'Your RMCS account'),
      const SizedBox(height: 18),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              textOf(widget.user, 'name'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
            const SizedBox(height: 5),
            Text(
              textOf(widget.user, 'email'),
              style: const TextStyle(color: muted),
            ),
            Text(
              roleLabels[widget.user['role']] ?? '',
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout),
              label: const Text(signOutLabel),
            ),
          ],
        ),
      ),
    ],
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, this.subtitle, {super.key, this.action});
  final String title;
  final String subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 27,
                letterSpacing: -.65,
              ),
            ),
            if (subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  subtitle,
                  style: const TextStyle(color: muted, fontSize: 14),
                ),
              ),
          ],
        ),
      ),
      if (action != null) ...[const SizedBox(width: 10), action!],
    ],
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(15),
    this.onTap,
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(13),
      side: const BorderSide(color: line),
    ),
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class StatusTag extends StatelessWidget {
  const StatusTag({super.key, required this.row});
  final Data row;
  @override
  Widget build(BuildContext context) {
    final status = textOf(row, 'status');
    final (background, foreground) = switch (status) {
      'closed' || 'solved' => (const Color(0xffe3f3e5), green),
      'in_progress' ||
      'assigned' => (const Color(0xffe4f1fa), const Color(0xff1b5e86)),
      'verification' ||
      'engineer_review' ||
      'on_hold' ||
      'pending' => (const Color(0xfffff1d7), const Color(0xff855315)),
      'rework' => (const Color(0xfffce8e4), const Color(0xff9f3931)),
      _ => (const Color(0xffedf1ee), muted),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          statusLabels[status] ?? status,
          style: TextStyle(
            color: foreground,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

IconData categoryIcon(String category) => switch (category) {
  'Irrigation' => Icons.water_drop_outlined,
  'Trees' || 'Softscape' => Icons.eco_outlined,
  'Electrical' => Icons.lightbulb_outline,
  'Drainage' => Icons.water_outlined,
  'Hardscape' => Icons.grid_view_rounded,
  _ => Icons.handyman_outlined,
};
