import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api.dart';
import 'main.dart';
import 'workspace.dart';
import 'ui_labels.dart';

const webInk = Color(0xff122238);
const webMuted = Color(0xff4f6071);
const webGreen = Color(0xff007747);
const webLine = Color(0xffdde6ea);

class WebCard extends StatelessWidget {
  const WebCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.inset = false,
    this.integrated = false,
  });
  final Widget child;
  final EdgeInsets padding;
  final bool inset;
  final bool integrated;

  @override
  Widget build(BuildContext context) => integrated
      ? Padding(padding: padding, child: child)
      : Container(
          decoration: BoxDecoration(
            color: inset ? const Color(0xfff8fcfb) : const Color(0xfffbfdfd),
            borderRadius: BorderRadius.circular(inset ? 11 : 16),
            border: Border.all(
              color: inset ? const Color(0xffe1ede9) : Colors.white,
            ),
            boxShadow: inset
                ? null
                : const [
                    BoxShadow(
                      color: Color(0x14254255),
                      blurRadius: 17,
                      offset: Offset(0, 5),
                    ),
                  ],
          ),
          child: Padding(padding: padding, child: child),
        );
}

class DashboardHeading extends StatelessWidget {
  const DashboardHeading(this.title, this.caption, {super.key, this.action});
  final String title;
  final String caption;
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
                color: webInk,
                fontSize: 33,
                height: 1.05,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.15,
              ),
            ),
            if (caption.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                caption,
                style: const TextStyle(color: webMuted, fontSize: 14),
              ),
            ],
          ],
        ),
      ),
      if (action != null) ...[const SizedBox(width: 14), action!],
    ],
  );
}

class WebAction extends StatelessWidget {
  const WebAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xff00904b), Color(0xff005746)],
      ),
      borderRadius: BorderRadius.circular(11),
      boxShadow: const [
        BoxShadow(
          color: Color(0x29017650),
          blurRadius: 10,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        minimumSize: const Size(0, 42),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
  );
}

class WebSidebar extends StatelessWidget {
  const WebSidebar({
    super.key,
    required this.selected,
    required this.client,
    required this.reports,
    required this.onSelect,
    required this.onSignOut,
  });
  final int selected;
  final bool client;
  final bool reports;
  final ValueChanged<int> onSelect;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final entries = [0, 2, 1, if (!client) 3, if (reports) 5, 4];
    return SizedBox(
      width: 214,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xff031f25), Color(0xff00332e), Color(0xff045642)],
          ),
        ),
        child: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: LandscapeBands(
                    tint: Color(0xff42e8a2),
                    sidebar: true,
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(23, 27, 15, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Brand(inverse: true),
                      const SizedBox(height: 17),
                      Text(
                        client
                            ? 'Client Portal'
                            : 'Reactive maintenance\nmanagement',
                        style: const TextStyle(
                          color: Color(0xffd0e7de),
                          fontSize: 13,
                          height: 1.32,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    children: [
                      for (final index in entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: index == selected
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xff008f49),
                                        Color(0xff006b59),
                                      ],
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(11),
                              border: index == selected
                                  ? Border.all(color: const Color(0xff45c996))
                                  : null,
                              boxShadow: index == selected
                                  ? const [
                                      BoxShadow(
                                        color: Color(0x3a36eaa3),
                                        blurRadius: 10,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: ListTile(
                              dense: true,
                              minTileHeight: 43,
                              minLeadingWidth: 22,
                              horizontalTitleGap: 12,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(11),
                              ),
                              selected: index == selected,
                              selectedColor: Colors.white,
                              textColor: const Color(0xffe5f3ee),
                              iconColor: const Color(0xffc0dbd3),
                              leading: Icon(
                                workspaceDestinations[index].$1,
                                size: 20,
                              ),
                              title: Text(
                                workspaceDestinations[index].$2,
                                style: const TextStyle(fontSize: 14),
                              ),
                              onTap: () => onSelect(index),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 0, 13, 18),
                  child: ListTile(
                    dense: true,
                    textColor: Colors.white,
                    iconColor: const Color(0xffc0dbd3),
                    leading: const Icon(Icons.logout_rounded, size: 19),
                    title: const Text(signOutLabel),
                    onTap: onSignOut,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class LandscapeBands extends CustomPainter {
  const LandscapeBands({required this.tint, this.sidebar = false});
  final Color tint;
  final bool sidebar;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    for (var i = 0; i < 3; i++) {
      final offset = i * h * .085;
      final path = Path()
        ..moveTo(w * (sidebar ? -.30 : .42), h + offset)
        ..cubicTo(
          w * .40,
          h * (sidebar ? .67 : .93) + offset,
          w * .83,
          h * (sidebar ? .87 : .80) + offset,
          w * 1.13,
          h * (sidebar ? .58 : .27) + offset,
        )
        ..lineTo(w * 1.14, h * 1.34)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = tint.withValues(alpha: .10 + i * .04),
      );
    }
  }

  @override
  bool shouldRepaint(LandscapeBands oldDelegate) =>
      tint != oldDelegate.tint || sidebar != oldDelegate.sidebar;
}

class MetricCards extends StatelessWidget {
  const MetricCards({super.key, required this.metrics, required this.columns});

  final List<MetricTile> metrics;
  final int columns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      const gap = 12.0;
      final width = (bounds.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final metric in metrics) SizedBox(width: width, child: metric),
        ],
      );
    },
  );
}

class _MetricWaves extends CustomPainter {
  const _MetricWaves(this.accent);
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final back = Path()
      ..moveTo(w * .55, h)
      ..cubicTo(w * .78, h * .94, w * .82, h * .48, w, h * .35)
      ..lineTo(w, h)
      ..close();
    final front = Path()
      ..moveTo(w * .71, h)
      ..cubicTo(w * .88, h * .90, w * .90, h * .64, w, h * .57)
      ..lineTo(w, h)
      ..close();

    final lowerCorner = Rect.fromLTWH(w * .55, h * .35, w * .45, h * .65);
    canvas.drawPath(
      back,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: .03),
            accent.withValues(alpha: .24),
          ],
        ).createShader(lowerCorner),
    );
    canvas.drawPath(front, Paint()..color = accent.withValues(alpha: .12));
  }

  @override
  bool shouldRepaint(_MetricWaves oldDelegate) => oldDelegate.accent != accent;
}

class MetricTile extends StatefulWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.tint,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color accent;
  final Color tint;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<MetricTile> createState() => _MetricTileState();
}

class _MetricTileState extends State<MetricTile> {
  Offset? pointer;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final hovered = pointer != null && !reduceMotion;
    final duration = reduceMotion
        ? Duration.zero
        : Duration(milliseconds: hovered ? 105 : 210);
    return Semantics(
      selected: widget.selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: reduceMotion
            ? null
            : (event) => setState(() => pointer = event.localPosition),
        onHover: reduceMotion
            ? null
            : (event) => setState(() => pointer = event.localPosition),
        onExit: (_) {
          if (pointer != null) setState(() => pointer = null);
        },
        child: SizedBox(
          height: 104,
          child: LayoutBuilder(
            builder: (context, bounds) {
              final location = pointer ?? bounds.biggest.center(Offset.zero);
              final tilt = hovered
                  ? Offset(
                      (2 * location.dx / bounds.maxWidth - 1).clamp(-1.0, 1.0),
                      (2 * location.dy / bounds.maxHeight - 1).clamp(-1.0, 1.0),
                    )
                  : Offset.zero;
              return TweenAnimationBuilder<Offset>(
                duration: duration,
                curve: Curves.easeOutCubic,
                tween: Tween<Offset>(begin: Offset.zero, end: tilt),
                builder: (context, angle, child) => Transform(
                  alignment: Alignment.center,
                  transformHitTests: false,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, .0018)
                    ..rotateX(-angle.dy * .15)
                    ..rotateY(angle.dx * .15),
                  child: child,
                ),
                child: surface(duration, hovered),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget surface(Duration duration, bool hovered) {
    final accent = widget.accent;
    final radius = BorderRadius.circular(17);
    return AnimatedContainer(
      duration: duration,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xff263e55,
            ).withValues(alpha: hovered ? .18 : .09),
            offset: Offset(0, hovered ? 10 : 6),
            blurRadius: hovered ? 21 : 15,
          ),
          BoxShadow(
            color: accent.withValues(alpha: .08),
            offset: const Offset(0, 5),
            blurRadius: 9,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(Colors.white, widget.tint, .35)!,
                widget.tint,
              ],
            ),
            border: Border.all(
              color: widget.selected
                  ? accent.withValues(alpha: .65)
                  : Colors.white,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(child: CustomPaint(painter: _MetricWaves(accent))),
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: widget.onTap,
                  hoverColor: Colors.transparent,
                  focusColor: accent.withValues(alpha: .10),
                  splashColor: accent.withValues(alpha: .13),
                  child: LayoutBuilder(
                    builder: (context, bounds) {
                      final compact = bounds.maxWidth < 200;
                      final iconSize = compact ? 38.0 : 52.0;
                      return Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 10 : 15,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: iconSize,
                              height: iconSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    accent.withValues(alpha: .045),
                                    accent.withValues(alpha: .19),
                                  ],
                                ),
                              ),
                              child: Icon(
                                widget.icon,
                                size: compact ? 22 : 28,
                                color: accent,
                              ),
                            ),
                            SizedBox(width: compact ? 8 : 13),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.label,
                                    maxLines: 2,
                                    style: const TextStyle(
                                      color: webInk,
                                      fontSize: 13,
                                      height: 1.13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    '${widget.value}',
                                    style: const TextStyle(
                                      color: Color(0xff0b172a),
                                      fontSize: 33,
                                      height: .98,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -.9,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WebWorkbench extends StatelessWidget {
  const WebWorkbench({super.key, required this.queue, required this.detail});

  final Widget queue;
  final Widget detail;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xfffafdfd),
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: Colors.white),
      boxShadow: const [
        BoxShadow(
          color: Color(0x13243b4a),
          blurRadius: 17,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Stack(
      children: [
        const Positioned.fill(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Spacer(flex: 45),
              Expanded(
                flex: 55,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xfff2f8f7),
                    border: Border(left: BorderSide(color: webLine)),
                  ),
                ),
              ),
            ],
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 45, child: queue),
            Expanded(
              flex: 55,
              child: Padding(padding: const EdgeInsets.all(12), child: detail),
            ),
          ],
        ),
      ],
    ),
  );
}

class PriorityTag extends StatelessWidget {
  const PriorityTag(this.priority, {super.key});
  final String priority;

  @override
  Widget build(BuildContext context) {
    final (fill, text, icon) = switch (priority) {
      'Critical' || 'High' => (
        const Color(0xfffee2e3),
        const Color(0xffa62129),
        Icons.keyboard_double_arrow_up_rounded,
      ),
      'Medium' => (
        const Color(0xffffecd1),
        const Color(0xff8f4a00),
        Icons.keyboard_arrow_up_rounded,
      ),
      _ => (
        const Color(0xffdcf5e9),
        const Color(0xff08704e),
        Icons.arrow_downward_rounded,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 3, 7, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: text),
            const SizedBox(width: 2),
            Text(
              priority,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WebQueue extends StatefulWidget {
  const WebQueue({
    super.key,
    required this.rows,
    required this.active,
    required this.filter,
    required this.filters,
    required this.selected,
    required this.client,
    required this.jobFor,
    required this.onSelect,
    required this.onFilter,
    this.onExport,
    this.onClearJob,
    this.jobLabel,
    this.assignmentFilter,
    this.assignee,
  });
  final List<Data> rows;
  final int active;
  final String filter;
  final List<(String, String, int)> filters;
  final String? selected;
  final bool client;
  final Data Function(Data) jobFor;
  final ValueChanged<Data> onSelect;
  final ValueChanged<String> onFilter;
  final ValueChanged<String>? onExport;
  final VoidCallback? onClearJob;
  final String? jobLabel;
  final Widget? assignmentFilter;
  final String? assignee;

  @override
  State<WebQueue> createState() => _WebQueueState();
}

class _WebQueueState extends State<WebQueue> {
  static const pageSize = 8;
  int page = 0;

  @override
  void didUpdateWidget(WebQueue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter ||
        oldWidget.jobLabel != widget.jobLabel ||
        oldWidget.assignee != widget.assignee ||
        oldWidget.rows.length != widget.rows.length) {
      page = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final start = page * pageSize;
    final end = math.min(start + pageSize, widget.rows.length);
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.client
                      ? 'My Service Requests'
                      : 'Service Request List',
                  style: const TextStyle(
                    color: webInk,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.35,
                  ),
                ),
              ),
              if (!widget.client)
                Text(
                  '${widget.active} unclosed',
                  style: const TextStyle(
                    color: webMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (widget.onExport != null)
                PopupMenuButton<String>(
                  tooltip: 'Download Service Request Report',
                  icon: const Icon(Icons.file_download_outlined, size: 20),
                  onSelected: widget.onExport,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'xlsx',
                      child: Text(downloadExcelLabel),
                    ),
                    PopupMenuItem(value: 'pdf', child: Text(downloadPdfLabel)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 9),
          if (widget.jobLabel != null)
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                label: Text(widget.jobLabel!),
                onDeleted: widget.onClearJob,
              ),
            ),
          Wrap(
            spacing: 5,
            runSpacing: 6,
            children: [
              for (final (id, name, count) in widget.filters)
                FilterPill(
                  label: '$name ($count)',
                  selected: widget.filter == id,
                  onTap: () => widget.onFilter(id),
                ),
            ],
          ),
          const SizedBox(height: 13),
          if (widget.assignmentFilter != null) ...[
            widget.assignmentFilter!,
            const SizedBox(height: 12),
          ],
          if (widget.rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No service requests match these filters.',
                textAlign: TextAlign.center,
                style: TextStyle(color: webMuted),
              ),
            )
          else ...[
            lineItem(heading: true),
            const SizedBox(height: 3),
            for (final row in widget.rows.getRange(start, end))
              Material(
                color: widget.selected == row['id']
                    ? const Color(0xffd6f3e7)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => widget.onSelect(row),
                  child: lineItem(row: row),
                ),
              ),
            const Divider(color: webLine, height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${start + 1}–$end of ${widget.rows.length} requests',
                    style: const TextStyle(color: webMuted, fontSize: 11),
                  ),
                ),
                if (widget.rows.length > pageSize) ...[
                  IconButton(
                    tooltip: 'Previous Page',
                    onPressed: page > 0 ? () => setState(() => page--) : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                    visualDensity: VisualDensity.compact,
                  ),
                  Text(
                    '${page + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: webInk,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next Page',
                    onPressed: end < widget.rows.length
                        ? () => setState(() => page++)
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget lineItem({bool heading = false, Data? row}) {
    final job = row == null ? const <String, dynamic>{} : widget.jobFor(row);
    Widget cell(String label, String value, int flex, {bool bold = false}) =>
        Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              heading ? label : value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: webInk,
                fontSize: heading ? 10 : 11,
                height: 1.22,
                fontWeight: heading || bold ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
        );
    return Container(
      constraints: BoxConstraints(minHeight: heading ? 28 : 50),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: webLine.withValues(alpha: .75)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        children: [
          cell('Request No.', textOf(row ?? {}, 'code'), 22, bold: true),
          cell(
            'Site / Request',
            [textOf(job, 'site'), textOf(row ?? {}, 'title')].join('\n'),
            26,
          ),
          if (!widget.client)
            Expanded(
              flex: 19,
              child: heading
                  ? const Text(
                      'Priority',
                      style: TextStyle(
                        color: webInk,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: PriorityTag(textOf(row!, 'priority')),
                      ),
                    ),
            ),
          Expanded(
            flex: 26,
            child: heading
                ? const Text(
                    'Status',
                    style: TextStyle(
                      color: webInk,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: StatusTag(row: row!),
                  ),
          ),
          if (!widget.client)
            cell('Assigned To', textOf(row ?? {}, 'assignee', '—'), 20),
        ],
      ),
    );
  }
}

class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      backgroundColor: selected ? const Color(0xff00784b) : Colors.white,
      foregroundColor: selected ? Colors.white : webInk,
      side: BorderSide(color: selected ? webGreen : webLine),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      minimumSize: const Size(0, 32),
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
    ),
    child: Text(label),
  );
}

class ClientStageLine extends StatelessWidget {
  const ClientStageLine(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final stage = switch (status) {
      'solved' => 2,
      'in_progress' || 'pending' => 1,
      _ => 0,
    };
    const labels = ['Open', 'In Progress', 'Closed'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, label) in labels.indexed)
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 2,
                        color: index == 0
                            ? Colors.transparent
                            : index <= stage
                            ? webGreen
                            : webLine,
                      ),
                    ),
                    Icon(
                      index < stage || stage == 2
                          ? Icons.check_circle_rounded
                          : index == stage
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 17,
                      color: index <= stage
                          ? webGreen
                          : const Color(0xff9cabb7),
                    ),
                    Expanded(
                      child: Container(
                        height: 2,
                        color: index == 2
                            ? Colors.transparent
                            : index < stage
                            ? webGreen
                            : webLine,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: webMuted,
                    fontWeight: index == stage
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
