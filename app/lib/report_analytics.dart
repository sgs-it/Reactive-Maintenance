import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api.dart';
import 'web_dashboard.dart';

const _statusColors = {
  'open': Color(0xff64748b),
  'assigned': Color(0xff0e7490),
  'in_progress': Color(0xff2563eb),
  'on_hold': Color(0xffb45309),
  'verification': Color(0xff8b5a18),
  'rework': Color(0xffbe4058),
  'engineer_review': Color(0xff7c54bc),
  'closed': Color(0xff008158),
};

class ReportAnalytics extends StatelessWidget {
  const ReportAnalytics({
    super.key,
    required this.rows,
    required this.selectedAssignee,
    required this.onAssigneeSelected,
  });

  final List<Data> rows;
  final String? selectedAssignee;
  final ValueChanged<String?> onAssigneeSelected;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const WebCard(
        child: Row(
          children: [
            Icon(Icons.bar_chart_rounded, color: webMuted),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'No service requests match these filters.',
                style: TextStyle(color: webMuted),
              ),
            ),
          ],
        ),
      );
    }

    final statuses = <String, int>{};
    final people = <String, ({String label, int count})>{};
    int overdue = 0;
    int unassigned = 0;
    int closed = 0;
    for (final row in rows) {
      final status = resolved(row)
          ? 'closed'
          : textOf(row, 'status', 'unknown');
      statuses.update(status, (count) => count + 1, ifAbsent: () => 1);
      if (status == 'closed') closed++;
      if (row['overdue'] == true) overdue++;
      final assignee = row['assigned_to'] as String? ?? 'unassigned';
      if (assignee == 'unassigned') unassigned++;
      people.update(
        assignee,
        (entry) => (label: entry.label, count: entry.count + 1),
        ifAbsent: () => (
          label: assignee == 'unassigned'
              ? 'Unassigned'
              : textOf(row, 'assignee', 'Staff'),
          count: 1,
        ),
      );
    }

    final distribution = [
      for (final status in {..._statusColors.keys, ...statuses.keys})
        if (statuses[status] case final int count)
          (
            label: statusLabels[status] ?? 'Other',
            count: count,
            color: _statusColors[status] ?? webMuted,
          ),
    ];
    final workload = people.entries.toList()
      ..sort((a, b) {
        final order = b.value.count.compareTo(a.value.count);
        return order != 0 ? order : a.value.label.compareTo(b.value.label);
      });
    final metrics = [
      (
        'Closure Rate',
        '${(100 * closed / rows.length).round()}%',
        '$closed of ${rows.length} closed',
        Icons.task_alt_rounded,
        webGreen,
        const Color(0xffeaf7f0),
      ),
      (
        'Overdue',
        '$overdue',
        'Past the due date',
        Icons.alarm_rounded,
        const Color(0xffb03a43),
        const Color(0xfffff0f1),
      ),
      (
        'Unassigned',
        '$unassigned',
        'Awaiting assignment',
        Icons.person_add_alt_1_outlined,
        const Color(0xff236bb6),
        const Color(0xffedf5ff),
      ),
    ];

    return LayoutBuilder(
      builder: (context, bounds) {
        final columns = bounds.maxWidth >= 760;
        final statusCard = _StatusCard(
          distribution: distribution,
          total: rows.length,
        );
        final assigneeCard = _AssigneeCard(
          workload: workload,
          selected: selectedAssignee,
          onSelected: onAssigneeSelected,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (title, value, detail, icon, accent, tint)
                    in metrics)
                  SizedBox(
                    width: bounds.maxWidth >= 530
                        ? (bounds.maxWidth - 20) / 3
                        : bounds.maxWidth,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Colors.white, tint]),
                        border: Border.all(color: Colors.white),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 19,
                            backgroundColor: tint,
                            child: Icon(icon, size: 21, color: accent),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    color: webInk,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  detail,
                                  style: const TextStyle(
                                    color: webMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            value,
                            style: TextStyle(
                              color: accent,
                              fontSize: 27,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (columns)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: statusCard),
                  const SizedBox(width: 12),
                  Expanded(child: assigneeCard),
                ],
              )
            else ...[
              statusCard,
              const SizedBox(height: 12),
              assigneeCard,
            ],
          ],
        );
      },
    );
  }
}

typedef _StatusSlice = ({String label, int count, Color color});

class _StatusCard extends StatefulWidget {
  const _StatusCard({required this.distribution, required this.total});

  final List<_StatusSlice> distribution;
  final int total;

  @override
  State<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends State<_StatusCard> {
  String? highlighted;

  @override
  Widget build(BuildContext context) {
    final distribution = widget.distribution;
    final selected = distribution.indexWhere(
      (slice) => slice.label == highlighted,
    );
    final total = widget.total;
    final ring = SizedBox.square(
      dimension: 168,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            child: CustomPaint(
              painter: _StatusRing(distribution, total, selected),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${selected < 0 ? total : distribution[selected].count}',
                  style: const TextStyle(
                    color: webInk,
                    fontSize: 33,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  selected < 0
                      ? 'Total Requests'
                      : '${(100 * distribution[selected].count / total).round()}% of total',
                  style: const TextStyle(
                    color: webMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final legend = Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          for (final (index, slice) in distribution.indexed)
            Semantics(
              selected: selected == index,
              label: '${slice.label}, ${slice.count} of $total requests',
              child: InkWell(
                borderRadius: BorderRadius.circular(7),
                onTap: () => setState(
                  () => highlighted = selected == index ? null : slice.label,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 9, color: slice.color),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          slice.label,
                          style: TextStyle(
                            color: webInk,
                            fontSize: 12,
                            fontWeight: selected == index
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${slice.count}',
                        style: const TextStyle(
                          color: webInk,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ChartTitle('Requests by Status', Icons.donut_large_rounded),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, bounds) => bounds.maxWidth >= 345
                ? Row(
                    children: [
                      ring,
                      const SizedBox(width: 10),
                      Expanded(child: legend),
                    ],
                  )
                : Column(children: [ring, const SizedBox(height: 12), legend]),
          ),
        ],
      ),
    );
  }
}

class _StatusRing extends CustomPainter {
  const _StatusRing(this.distribution, this.total, this.selected);

  final List<_StatusSlice> distribution;
  final int total;
  final int selected;

  @override
  void paint(Canvas canvas, Size size) {
    const fullCircle = 2 * math.pi;
    final center = size.center(Offset.zero);
    final circle = Rect.fromCircle(
      center: center,
      radius: size.shortestSide / 2 - 15,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24;
    canvas.drawCircle(center, circle.width / 2, paint..color = webLine);
    var start = -math.pi / 2;
    for (final (index, slice) in distribution.indexed) {
      final sweep = slice.count / total * fullCircle;
      final gap = distribution.length == 1 ? 0.0 : math.min(.038, sweep * .2);
      paint.color = selected < 0 || selected == index
          ? slice.color
          : slice.color.withValues(alpha: .23);
      canvas.drawArc(circle, start + gap / 2, sweep - gap, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_StatusRing oldDelegate) =>
      distribution != oldDelegate.distribution ||
      selected != oldDelegate.selected;
}

class _AssigneeCard extends StatelessWidget {
  const _AssigneeCard({
    required this.workload,
    required this.selected,
    required this.onSelected,
  });

  final List<MapEntry<String, ({String label, int count})>> workload;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final max = workload.first.value.count;
    return WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ChartTitle('Requests by Assignee', Icons.groups_outlined),
          const SizedBox(height: 12),
          Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (final entry in workload.take(6))
                  Semantics(
                    selected: entry.key == selected,
                    button: true,
                    label:
                        '${entry.value.label}, ${entry.value.count} requests',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () =>
                          onSelected(entry.key == selected ? null : entry.key),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.value.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: webInk,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${entry.value.count}',
                                  style: const TextStyle(
                                    color: webInk,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: entry.value.count,
                                    child: Container(
                                      height: 8,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: entry.key == 'unassigned'
                                              ? const [
                                                  Color(0xff64748b),
                                                  Color(0xff94a3b8),
                                                ]
                                              : const [
                                                  Color(0xff008057),
                                                  Color(0xff4cc397),
                                                ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (entry.value.count < max)
                                    Expanded(
                                      flex: max - entry.value.count,
                                      child: const SizedBox(
                                        height: 8,
                                        child: ColoredBox(
                                          color: Color(0xffe7efec),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (workload.length > 6) ...[
            const SizedBox(height: 6),
            Text(
              'Top 6 of ${workload.length}',
              style: const TextStyle(color: webMuted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChartTitle extends StatelessWidget {
  const _ChartTitle(this.title, this.icon);
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 19, color: webGreen),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            color: webInk,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );
}
