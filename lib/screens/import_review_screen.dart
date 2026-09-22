import 'package:flutter/material.dart';

import '../models/position.dart';
import '../services/gemini_service.dart';
import '../services/import_queue_service.dart';
import 'position_edit_screen.dart';

/// Shows the outcome of a background import.
///
/// Reached by tapping the result notification, or from the app while an import
/// is still running. It reads the persisted record rather than doing the work
/// itself, so reopening it never re-runs a paid API call.
///
/// Nothing reaches Firestore from here. The extraction is presented for review
/// and then handed to the normal edit form, because a model reading a job
/// advert will occasionally be confidently wrong, and a tracker full of
/// plausible-but-wrong deadlines is worse than one with gaps.
class ImportReviewScreen extends StatefulWidget {
  const ImportReviewScreen({super.key, required this.importId});

  final String importId;

  @override
  State<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

class _ImportReviewScreenState extends State<ImportReviewScreen> {
  final _queue = ImportQueueService.instance;
  final _pasteCtrl = TextEditingController();

  PendingImport? _record;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
    // An import may still be running when this screen opens; refresh when the
    // queue reports a result rather than polling for it.
    _queue.lastCompleted.addListener(_onCompleted);
  }

  @override
  void dispose() {
    _queue.lastCompleted.removeListener(_onCompleted);
    // Owned by the State, not by the dialog: disposing it when the dialog
    // closes would kill it while the exit animation still reads from it.
    _pasteCtrl.dispose();
    super.dispose();
  }

  void _onCompleted() {
    final done = _queue.lastCompleted.value;
    if (done != null && done.id == widget.importId && mounted) {
      setState(() => _record = done);
    }
  }

  Future<void> _load() async {
    final r = await _queue.load(widget.importId);
    if (!mounted) return;
    setState(() {
      _record = r;
      _loading = false;
    });
  }

  Future<void> _pasteManually() async {
    _pasteCtrl.clear();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste the description'),
        content: TextField(
          controller: _pasteCtrl,
          maxLines: 10,
          minLines: 6,
          autofocus: true,
          decoration:
              const InputDecoration(hintText: 'Paste the advert text here…'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _pasteCtrl.text),
            child: const Text('Extract'),
          ),
        ],
      ),
    );

    if (text == null) return;
    if (text.trim().length < 80) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('That was too short to work from.')));
      }
      return;
    }

    setState(() => _working = true);
    final updated = await _queue.runWithText(widget.importId, text);
    if (!mounted) return;
    setState(() {
      _record = updated;
      _working = false;
    });
  }

  Position _toPosition(PendingImport record, ExtractedPosition e) {
    final now = DateTime.now();
    final deadline =
        e.deadline == null ? null : DateTime.tryParse(e.deadline!);

    return Position(
      id: 'pending',
      university: e.university ?? '',
      programme: e.programme ?? '',
      deadline: deadline,
      // Flag the date unless the page stated the year outright.
      deadlineYearAssumed: deadline != null && !e.deadlineYearExplicit,
      funded: e.funded,
      applicationFee: e.applicationFee,
      feeCurrency: e.feeCurrency,
      link: record.url ?? '',
      country: e.country,
      tags: e.tags,
      notes: [
        if (e.summary != null) e.summary!,
        'Imported from a share on '
            '${now.toIso8601String().substring(0, 10)}.',
        if (e.notFound.isNotEmpty)
          'Not stated in the source: ${e.notFound.join(', ')}.',
      ].join('\n\n'),
      createdAt: now,
      updatedAt: now,
    );
  }

  void _openEditor(Position prefill) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PositionEditScreen(existing: null, prefill: prefill),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final record = _record;

    return Scaffold(
      appBar: AppBar(title: const Text('Imported position')),
      body: Builder(builder: (context) {
        if (_loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (record == null) {
          return const _Centered(
            icon: Icons.help_outline,
            title: 'That import is no longer saved.',
            detail: 'Records are kept for the last 20 shares.',
          );
        }
        if (_working || record.status == ImportStatus.running) {
          return const _Centered(
            icon: null,
            title: 'Still reading the advert…',
            detail: 'You can leave this screen — a notification will tell you '
                'when it is done.',
          );
        }
        if (record.status == ImportStatus.failed) {
          return _Failure(
            record: record,
            onPaste: _pasteManually,
            onRetry: () async {
              setState(() => _working = true);
              await _queue.retry(record.id);
              if (mounted) setState(() => _working = false);
            },
            onManual: () => _openEditor(Position(
              id: 'pending',
              university: '',
              programme: '',
              link: record.url ?? '',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            )),
          );
        }

        final extracted = record.result;
        if (extracted == null) {
          return const _Centered(
            icon: Icons.error_outline,
            title: 'The saved result could not be read.',
            detail: 'Share the link again.',
          );
        }

        return _Result(
          record: record,
          extracted: extracted,
          onPaste: _pasteManually,
          onAccept: () => _openEditor(_toPosition(record, extracted)),
        );
      }),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData? icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon == null)
              const CircularProgressIndicator()
            else
              Icon(icon, size: 44, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(detail,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({
    required this.record,
    required this.onPaste,
    required this.onRetry,
    required this.onManual,
  });

  final PendingImport record;
  final VoidCallback onPaste;
  final VoidCallback onRetry;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.link_off, size: 44, color: s.error),
        const SizedBox(height: 16),
        Text(record.error ?? 'Something went wrong.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall),
        if (record.hint != null) ...[
          const SizedBox(height: 10),
          Text(record.hint!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 26),
        FilledButton.icon(
          onPressed: onPaste,
          icon: const Icon(Icons.content_paste),
          label: const Text('Paste the description instead'),
        ),
        const SizedBox(height: 8),
        if (record.url != null)
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try the link again'),
          ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onManual,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Enter it manually'),
        ),
        if (record.url != null) ...[
          const SizedBox(height: 20),
          Text(record.url!,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: s.outline)),
        ],
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.record,
    required this.extracted,
    required this.onAccept,
    required this.onPaste,
  });

  final PendingImport record;
  final ExtractedPosition extracted;
  final VoidCallback onAccept;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final shaky = extracted.confidence == 'low' || extracted.isEmpty;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            children: [
              if (shaky)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: s.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_outlined,
                          size: 18, color: s.onErrorContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'The model was not confident about this source. '
                          'Check every field before saving.',
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: s.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              _Field('University', extracted.university),
              _Field('Programme', extracted.programme),
              _Field(
                'Deadline',
                extracted.deadline,
                warning: extracted.deadline != null &&
                        !extracted.deadlineYearExplicit
                    ? 'Year was not stated in the source — verify it'
                    : null,
              ),
              _Field(
                  'Funded',
                  extracted.funded == null
                      ? null
                      : (extracted.funded! ? 'Yes' : 'No')),
              _Field(
                'Application fee',
                extracted.applicationFee == null
                    ? null
                    : '${extracted.applicationFee} ${extracted.feeCurrency ?? ''}'
                        .trim(),
              ),
              _Field('Country', extracted.country),
              _Field('Tags',
                  extracted.tags.isEmpty ? null : extracted.tags.join(', ')),
              _Field('Summary', extracted.summary),
              const SizedBox(height: 12),
              Text('Confidence: ${extracted.confidence}',
                  style: Theme.of(context).textTheme.bodySmall),
              if (extracted.notFound.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Not stated in the source: ${extracted.notFound.join(', ')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                record.url ?? 'From shared text',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: s.outline),
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onPaste,
                    child: const Text('Re-extract'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: onAccept,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Review & save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value, {this.warning});

  final String label;
  final String? value;
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final missing = value == null || value!.isEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: s.primary,
                  )),
          const SizedBox(height: 3),
          Text(
            missing ? 'Not found in the source' : value!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.35,
                  fontStyle: missing ? FontStyle.italic : FontStyle.normal,
                  color: missing ? s.outline : null,
                ),
          ),
          if (warning != null) ...[
            const SizedBox(height: 3),
            Row(
              children: [
                Icon(Icons.info_outline, size: 13, color: s.error),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(warning!,
                      style: TextStyle(fontSize: 11.5, color: s.error)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
