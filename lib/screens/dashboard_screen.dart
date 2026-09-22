import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/position.dart';
import '../state/positions_controller.dart';
import '../theme.dart';
import 'position_detail_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static final _fmt = DateFormat('d MMM');

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PositionsController>();
    final counts = c.statusCounts;
    final live = c.all.where((p) => !p.archived).toList();
    final upcoming = c.upcoming(withinDays: 30);
    final missed = c.missed;

    final decided = counts[AppStatus.accepted]! +
        counts[AppStatus.rejected]! +
        counts[AppStatus.withdrawn]!;
    final submitted = counts[AppStatus.applied]! +
        counts[AppStatus.interview]! +
        decided;

    return Scaffold(
      appBar: AppBar(title: const Text('Overview')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
        children: [
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  value: '${live.length}',
                  label: 'Tracked',
                  icon: Icons.list_alt,
                ),
              ),
              Expanded(
                child: _StatTile(
                  value: '$submitted',
                  label: 'Submitted',
                  icon: Icons.send_outlined,
                ),
              ),
              Expanded(
                child: _StatTile(
                  value: '${counts[AppStatus.notApplied]}',
                  label: 'To apply',
                  icon: Icons.edit_note_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Card(
            title: 'By status',
            child: Column(
              children: [
                for (final s in AppStatus.values)
                  if ((counts[s] ?? 0) > 0)
                    _StatusBar(
                      status: s,
                      count: counts[s]!,
                      total: live.isEmpty ? 1 : live.length,
                    ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (submitted > 0)
            _Card(
              title: 'Outcomes so far',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$decided of $submitted submitted application'
                    '${submitted == 1 ? '' : 's'} have come back.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    // Deliberately no "success rate" headline: with a handful
                    // of decisions the number is noise, not signal.
                    'Accepted ${counts[AppStatus.accepted]} · '
                    'Rejected ${counts[AppStatus.rejected]} · '
                    'Awaiting ${submitted - decided}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          _Card(
            title: 'Deadlines in the next 30 days',
            child: upcoming.isEmpty
                ? const Text('Nothing due in the next month.')
                : Column(
                    children: [
                      for (final p in upcoming.take(8))
                        _MiniRow(
                          position: p,
                          trailing:
                              '${_fmt.format(p.deadline!)} · ${p.daysLeft}d',
                        ),
                      if (upcoming.length > 8)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('+${upcoming.length - 8} more',
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                    ],
                  ),
          ),
          if (missed.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Card(
              title: 'Passed without applying (${missed.length})',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'These deadlines are in the past and still marked as not '
                    'applied. If the dates came from the imported sheet, check '
                    'the year before archiving them.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  for (final p in missed.take(6))
                    _MiniRow(
                        position: p, trailing: _fmt.format(p.deadline!)),
                  if (missed.length > 6)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('+${missed.length - 6} more',
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _Card(
            title: 'Top institutions',
            child: Column(
              children: [
                for (final e in _topUniversities(live).entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(child: Text(e.key)),
                        Text('${e.value}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
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

  Map<String, int> _topUniversities(List<Position> items) {
    final counts = <String, int>{};
    for (final p in items) {
      if (p.university.isEmpty) continue;
      counts[p.university] = (counts[p.university] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted.take(6));
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(
      {required this.value, required this.label, required this.icon});

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: s.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: s.primary),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700, color: s.primary)),
          Text(label,
              style: TextStyle(fontSize: 11.5, color: s.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar(
      {required this.status, required this.count, required this.total});

  final AppStatus status;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = statusColors(context, status);
    final frac = total == 0 ? 0.0 : count / total;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Row(
              children: [
                Icon(status.icon, size: 15, color: c.fg),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(status.label,
                      style: const TextStyle(fontSize: 12.5),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 8,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(c.fg),
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text('$count',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _MiniRow extends StatelessWidget {
  const _MiniRow({required this.position, required this.trailing});

  final Position position;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PositionDetailScreen(positionId: position.id)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(position.university,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(
                    position.programme,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(trailing,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: deadlineColors(context, position.daysLeft).fg)),
          ],
        ),
      ),
    );
  }
}
