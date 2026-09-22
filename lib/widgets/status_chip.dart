import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/position.dart';
import '../theme.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.compact = false});

  final AppStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = statusColors(context, status);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10, vertical: compact ? 3 : 5),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: compact ? 13 : 15, color: c.fg),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              color: c.fg,
              fontSize: compact ? 11.5 : 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class DeadlinePill extends StatelessWidget {
  const DeadlinePill({
    super.key,
    required this.deadline,
    required this.daysLeft,
    this.yearAssumed = false,
    this.showRelative = true,
  });

  final DateTime? deadline;
  final int? daysLeft;
  final bool yearAssumed;
  final bool showRelative;

  static final _fmt = DateFormat('d MMM yyyy');

  String get _relative {
    final d = daysLeft;
    if (d == null) return 'No deadline';
    if (d == 0) return 'Today';
    if (d == 1) return 'Tomorrow';
    if (d < 0) return '${-d}d ago';
    return 'in ${d}d';
  }

  @override
  Widget build(BuildContext context) {
    final c = deadlineColors(context, daysLeft);
    final label = deadline == null
        ? 'No deadline'
        : showRelative
            ? '${_fmt.format(deadline!)} · $_relative'
            : _fmt.format(deadline!);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            daysLeft != null && daysLeft! < 0
                ? Icons.event_busy_outlined
                : Icons.event_outlined,
            size: 14,
            color: c.fg,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
                color: c.fg, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          if (yearAssumed) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: 'Year was not in the source sheet — please verify',
              child: Icon(Icons.help_outline, size: 13, color: c.fg),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom sheet for changing status, with an optional note recorded in the
/// position's history.
Future<AppStatus?> showStatusPicker(
  BuildContext context, {
  required AppStatus current,
}) {
  return showModalBottomSheet<AppStatus>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Change status',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            for (final s in AppStatus.values)
              ListTile(
                leading: Icon(s.icon, color: statusColors(ctx, s).fg),
                title: Text(s.label),
                trailing: s == current
                    ? const Icon(Icons.check, size: 20)
                    : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
