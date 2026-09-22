import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/position.dart';
import '../state/positions_controller.dart';
import '../theme.dart';
import '../widgets/status_chip.dart';
import 'position_edit_screen.dart';

class PositionDetailScreen extends StatelessWidget {
  const PositionDetailScreen({super.key, required this.positionId});

  final String positionId;

  static final _dateFmt = DateFormat('EEE d MMM yyyy');

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PositionsController>();
    final match = c.all.where((p) => p.id == positionId);

    if (match.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This position no longer exists.')),
      );
    }
    final p = match.first;
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(p.university.isEmpty ? 'Position' : p.university),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => PositionEditScreen(existing: p)),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => _onMenu(context, c, p, v),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'archive',
                child: Text(p.archived ? 'Unarchive' : 'Archive'),
              ),
              PopupMenuItem(
                value: 'mute',
                child: Text(p.reminderEnabled
                    ? 'Mute reminders'
                    : 'Unmute reminders'),
              ),
              if (p.link.isNotEmpty)
                const PopupMenuItem(value: 'copy', child: Text('Copy link')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Text(
            p.programme.isEmpty ? '—' : p.programme,
            style: t.textTheme.headlineSmall?.copyWith(height: 1.25),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusChip(status: p.status),
              DeadlinePill(
                deadline: p.deadline,
                daysLeft: p.daysLeft,
                yearAssumed: p.deadlineYearAssumed,
              ),
            ],
          ),
          if (p.deadlineYearAssumed) ...[
            const SizedBox(height: 12),
            const _Banner(
              icon: Icons.info_outline,
              text: 'The source sheet gave only a day and month for this '
                  'deadline. The year was filled in on import — tap Edit to '
                  'correct it if it is wrong.',
            ),
          ],
          if (p.isOverdue && p.status.needsAction) ...[
            const SizedBox(height: 12),
            const _Banner(
              icon: Icons.warning_amber_outlined,
              tone: _BannerTone.warning,
              text: 'The deadline has passed and this is still marked as not '
                  'applied. Archive it, or correct the date.',
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.tonalIcon(
            onPressed: () async {
              final next = await showStatusPicker(context, current: p.status);
              if (next != null) await c.changeStatus(p, next);
            },
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Change status'),
          ),
          if (p.link.isNotEmpty) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.tryParse(p.link);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open application page'),
            ),
          ],
          const SizedBox(height: 24),
          _Section(title: 'Details', children: [
            _Row(label: 'University', value: p.university),
            _Row(
                label: 'Deadline',
                value: p.deadline == null
                    ? 'Not set'
                    : _dateFmt.format(p.deadline!)),
            _Row(
                label: 'Funded',
                value: p.funded == null
                    ? 'Unknown'
                    : (p.funded! ? 'Yes' : 'No')),
            _Row(
              label: 'Application fee',
              value: p.applicationFee == null
                  ? 'None recorded'
                  : '${p.applicationFee!.toStringAsFixed(0)} ${p.feeCurrency ?? ''}'
                      .trim(),
            ),
            if (p.country != null && p.country!.isNotEmpty)
              _Row(label: 'Country', value: p.country!),
            _Row(
                label: 'Applied on',
                value: p.appliedAt == null
                    ? '—'
                    : _dateFmt.format(p.appliedAt!)),
            _Row(
                label: 'Result on',
                value:
                    p.resultAt == null ? '—' : _dateFmt.format(p.resultAt!)),
            _Row(
                label: 'Reminders',
                value: p.reminderEnabled ? 'On' : 'Muted'),
          ]),
          if (p.tags.isNotEmpty) ...[
            const SizedBox(height: 18),
            _Section(title: 'Tags', children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final tag in p.tags) Chip(label: Text(tag))],
              ),
            ]),
          ],
          if (p.notes.isNotEmpty) ...[
            const SizedBox(height: 18),
            // The advert itself is split out and collapsed. Notes now carry
            // the whole source text, and inlining twenty thousand characters
            // would bury the summary and the history under a wall of scroll.
            Builder(builder: (context) {
              final split = _splitNotes(p.notes);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (split.summary.isNotEmpty)
                    _Section(title: 'Notes', children: [
                      Text(split.summary,
                          style: t.textTheme.bodyMedium?.copyWith(height: 1.4)),
                    ]),
                  if (split.advert.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Card(
                      elevation: 0,
                      margin: EdgeInsets.zero,
                      shape: appCardShape(context),
                      child: ExpansionTile(
                        shape: const Border(),
                        collapsedShape: const Border(),
                        tilePadding:
                            const EdgeInsets.symmetric(horizontal: 14),
                        leading: const Icon(Icons.article_outlined, size: 20),
                        title: const Text('Full advert',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            '${split.advert.length} characters, saved with '
                            'the entry'),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        children: [
                          SelectableText(
                            split.advert,
                            style: t.textTheme.bodySmall?.copyWith(height: 1.45),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            }),
          ],
          if (p.history.isNotEmpty) ...[
            const SizedBox(height: 18),
            _Section(title: 'History', children: [
              for (final h in p.history.reversed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(h.status.icon,
                          size: 17, color: statusColors(context, h.status).fg),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(h.status.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            Text(
                              DateFormat('d MMM yyyy, HH:mm').format(h.at),
                              style: t.textTheme.bodySmall,
                            ),
                            if (h.note != null && h.note!.isNotEmpty)
                              Text(h.note!, style: t.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ]),
          ],
        ],
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, PositionsController c,
      Position p, String action) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    switch (action) {
      case 'archive':
        await c.setArchived(p.id, !p.archived);
        messenger.showSnackBar(SnackBar(
            content: Text(p.archived ? 'Unarchived' : 'Archived')));
      case 'mute':
        await c.save(p.copyWith(reminderEnabled: !p.reminderEnabled));
        await c.forceRescheduleReminders();
        messenger.showSnackBar(SnackBar(
            content: Text(p.reminderEnabled
                ? 'Reminders muted for this position'
                : 'Reminders on for this position')));
      case 'copy':
        await Clipboard.setData(ClipboardData(text: p.link));
        messenger.showSnackBar(const SnackBar(content: Text('Link copied')));
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete this position?'),
            content: const Text(
                'This removes it permanently. Archiving keeps the record but '
                'hides it from the board.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete')),
            ],
          ),
        );
        if (ok == true) {
          await c.delete(p.id);
          navigator.pop();
        }
    }
  }
}

enum _BannerTone { info, warning }

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    this.tone = _BannerTone.info,
  });

  final IconData icon;
  final String text;
  final _BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final bg = tone == _BannerTone.warning
        ? s.errorContainer
        : s.secondaryContainer;
    final fg = tone == _BannerTone.warning
        ? s.onErrorContainer
        : s.onSecondaryContainer;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(color: fg, fontSize: 13, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary)),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.outline)),
          ),
          Expanded(
              child: Text(value.isEmpty ? '—' : value,
                  style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Splits the notes into the human-written part and the archived advert.
///
/// The marker is written by the importer and the Chrome extension, and is
/// also what the edit screen's "Extract from text" button reads back.
({String summary, String advert}) _splitNotes(String notes) {
  const marker = '--- shared text ---';
  final i = notes.indexOf(marker);
  if (i < 0) return (summary: notes.trim(), advert: '');
  return (
    summary: notes.substring(0, i).trim(),
    advert: notes.substring(i + marker.length).trim(),
  );
}
