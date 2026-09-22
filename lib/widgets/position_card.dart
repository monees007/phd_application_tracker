import 'package:flutter/material.dart';

import '../models/position.dart';
import '../theme.dart';
import 'status_chip.dart';

class PositionCard extends StatelessWidget {
  const PositionCard({
    super.key,
    required this.position,
    required this.onTap,
    required this.onStatusTap,
    required this.onOpenLink,
  });

  final Position position;
  final VoidCallback onTap;
  final VoidCallback onStatusTap;
  final VoidCallback onOpenLink;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = position;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: appCardShape(context),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
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
                        Text(
                          p.university.isEmpty ? 'Unnamed' : p.university,
                          style: t.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: t.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          p.programme.isEmpty ? '—' : p.programme,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.bodyMedium
                              ?.copyWith(height: 1.25),
                        ),
                      ],
                    ),
                  ),
                  if (p.link.isNotEmpty)
                    IconButton(
                      tooltip: 'Open application page',
                      icon: const Icon(Icons.open_in_new, size: 19),
                      onPressed: onOpenLink,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onStatusTap,
                    child: StatusChip(status: p.status, compact: true),
                  ),
                  DeadlinePill(
                    deadline: p.deadline,
                    daysLeft: p.daysLeft,
                    yearAssumed: p.deadlineYearAssumed,
                  ),
                  if (p.funded == true)
                    const _MiniTag(
                        icon: Icons.savings_outlined, label: 'Funded'),
                  if (p.applicationFee != null)
                    _MiniTag(
                      icon: Icons.payments_outlined,
                      label:
                          '${p.applicationFee!.toStringAsFixed(0)} ${p.feeCurrency ?? ''}'
                              .trim(),
                    ),
                  for (final tag in p.tags)
                    _MiniTag(icon: Icons.label_outline, label: tag),
                  if (p.notes.isNotEmpty)
                    const _MiniTag(
                        icon: Icons.sticky_note_2_outlined, label: 'Note'),
                  if (!p.reminderEnabled)
                    const _MiniTag(
                        icon: Icons.notifications_off_outlined,
                        label: 'Muted'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: s.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: s.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  color: s.onSurfaceVariant,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
