import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/position.dart';
import '../state/positions_controller.dart';
import '../widgets/extract_from_text_sheet.dart';

class PositionEditScreen extends StatefulWidget {
  const PositionEditScreen({super.key, required this.existing,
  this.prefill
  });

  final Position? existing;
  final Position? prefill;



  @override
  State<PositionEditScreen> createState() => _PositionEditScreenState();
}

class _PositionEditScreenState extends State<PositionEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _university;
  late final TextEditingController _programme;
  late final TextEditingController _link;
  late final TextEditingController _notes;
  late final TextEditingController _fee;
  late final TextEditingController _currency;
  late final TextEditingController _country;
  late final TextEditingController _tags;

  DateTime? _deadline;
  AppStatus _status = AppStatus.notApplied;
  bool? _funded;
  bool _reminderEnabled = true;
  bool _saving = false;

  static final _dateFmt = DateFormat('EEE d MMM yyyy');

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing ?? widget.prefill;
    _university = TextEditingController(text: p?.university ?? '');
    _programme = TextEditingController(text: p?.programme ?? '');
    _link = TextEditingController(text: p?.link ?? '');
    _notes = TextEditingController(text: p?.notes ?? '');
    _fee = TextEditingController(
        text: p?.applicationFee == null
            ? ''
            : p!.applicationFee!.toStringAsFixed(0));
    _currency = TextEditingController(text: p?.feeCurrency ?? '');
    _country = TextEditingController(text: p?.country ?? '');
    _tags = TextEditingController(text: p?.tags.join(', ') ?? '');
    _deadline = p?.deadline;
    _status = p?.status ?? AppStatus.notApplied;
    _funded = p?.funded;
    _reminderEnabled = p?.reminderEnabled ?? true;
  }

  @override
  void dispose() {
    for (final c in [
      _university,
      _programme,
      _link,
      _notes,
      _fee,
      _currency,
      _country,
      _tags
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now,
      // Wide window: some calls open more than a year ahead, and historical
      // entries need to stay editable.
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 6),
      helpText: 'Application deadline',
    );
    if (picked != null) {
      setState(() => _deadline = DateTime(picked.year, picked.month, picked.day));
    }
  }

  /// Fills the form from a pasted advert.
  ///
  /// Only overwrites a field when the model actually found something, so a
  /// partial extraction tops up what you already typed instead of wiping it.
  /// Nothing is written to Firestore here — you still press Save.
  Future<void> _extractFromText() async {
    // Seed with the shared text kept in the notes by a failed import, so a
    // retry needs no copy-and-paste.
    final seed = _sourceTextFromNotes(_notes.text);

    final result = await ExtractFromTextSheet.show(
      context,
      initialText: seed,
      url: _link.text.trim().isEmpty ? null : _link.text.trim(),
    );
    if (result == null || !mounted) return;

    setState(() {
      void fill(TextEditingController c, String? value) {
        final v = value?.trim();
        if (v != null && v.isNotEmpty) c.text = v;
      }

      fill(_university, result.university);
      fill(_programme, result.programme);
      fill(_country, result.country);
      fill(_currency, result.feeCurrency);

      if (result.applicationFee != null) {
        _fee.text = result.applicationFee!.toStringAsFixed(0);
      }
      if (result.funded != null) _funded = result.funded;

      if (result.deadline != null) {
        final parsed = DateTime.tryParse(result.deadline!);
        if (parsed != null) {
          _deadline = DateTime(parsed.year, parsed.month, parsed.day);
        }
      }

      if (result.tags.isNotEmpty) {
        final existing = _tags.text
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty && t != 'needs-details');
        _tags.text = {...existing, ...result.tags}.join(', ');
      }

      if (result.summary != null && result.summary!.isNotEmpty) {
        _notes.text = '${result.summary}\n\n${_notes.text}'.trim();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.confidence == 'low'
          ? 'Filled in, but the model was unsure — check each field.'
          : 'Filled in from the pasted text. Press Save to keep it.'),
    ));
  }

  /// Pulls back the original share that a failed import stored in the notes,
  /// so "Extract from text" opens pre-filled rather than empty.
  String _sourceTextFromNotes(String notes) {
    const marker = '--- shared text ---';
    final i = notes.indexOf(marker);
    return i < 0 ? '' : notes.substring(i + marker.length).trim();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final c = context.read<PositionsController>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final now = DateTime.now();

    final tags = _tags.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final fee = double.tryParse(_fee.text.trim());

    try {
      if (_isNew) {
        final p = Position(
          id: 'pending',
          university: _university.text.trim(),
          programme: _programme.text.trim(),
          deadline: _deadline,
          funded: _funded,
          applicationFee: fee,
          feeCurrency:
              _currency.text.trim().isEmpty ? null : _currency.text.trim().toUpperCase(),
          link: _link.text.trim(),
          status: _status,
          notes: _notes.text.trim(),
          tags: tags,
          country: _country.text.trim().isEmpty ? null : _country.text.trim(),
          createdAt: now,
          updatedAt: now,
          reminderEnabled: _reminderEnabled,
          appliedAt: _status == AppStatus.applied ? now : null,
          resultAt: _status.isDecided ? now : null,
          history: [StatusChange(status: _status, at: now)],
        );
        await c.create(p);
      } else {
        final old = widget.existing!;
        final statusChanged = old.status != _status;
        final updated = old.copyWith(
          university: _university.text.trim(),
          programme: _programme.text.trim(),
          deadline: _deadline,
          clearDeadline: _deadline == null,
          // Any manual edit means the date is now user-confirmed.
          deadlineYearAssumed: widget.prefill?.deadlineYearAssumed ?? false,
          funded: _funded,
          clearFunded: _funded == null,
          applicationFee: fee,
          clearFee: fee == null,
          feeCurrency: _currency.text.trim().toUpperCase(),
          link: _link.text.trim(),
          notes: _notes.text.trim(),
          tags: tags,
          country: _country.text.trim(),
          reminderEnabled: _reminderEnabled,
          updatedAt: now,
        );
        await c.save(updated);
        if (statusChanged) {
          await c.changeStatus(updated, _status);
        }
      }
      navigator.pop();
    } catch (e) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Add position' : 'Edit position'),
        actions: [
          IconButton(
            tooltip: 'Extract from pasted text',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: _saving ? null : _extractFromText,
          ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
          children: [
            TextFormField(
              controller: _university,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'University / institute *',
                prefixIcon: Icon(Icons.account_balance_outlined),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Give it a name so you can find it later'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _programme,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Programme / project title',
                prefixIcon: Icon(Icons.science_outlined),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              tileColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.45),
              leading: const Icon(Icons.event_outlined),
              title: Text(_deadline == null
                  ? 'No deadline set'
                  : _dateFmt.format(_deadline!)),
              subtitle: const Text('Deadline'),
              trailing: _deadline == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _deadline = null),
                    ),
              onTap: _pickDeadline,
            ),
            const SizedBox(height: 16),
            Text('Status', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in AppStatus.values)
                  ChoiceChip(
                    avatar: Icon(s.icon, size: 16),
                    label: Text(s.label),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Funding', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: -1, label: Text('Unknown')),
                ButtonSegment(value: 1, label: Text('Funded')),
                ButtonSegment(value: 0, label: Text('Not funded')),
              ],
              selected: {_funded == null ? -1 : (_funded! ? 1 : 0)},
              onSelectionChanged: (sel) => setState(() {
                final v = sel.first;
                _funded = v == -1 ? null : v == 1;
              }),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _fee,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Application fee',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      return double.tryParse(v.trim()) == null
                          ? 'Numbers only'
                          : null;
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _currency,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 3,
                    decoration: const InputDecoration(
                      labelText: 'Ccy',
                      counterText: '',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _link,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Link to apply',
                prefixIcon: Icon(Icons.link),
              ),
              validator: (v) {
                final s = v?.trim() ?? '';
                if (s.isEmpty) return null;
                final uri = Uri.tryParse(s);
                return (uri == null || !uri.hasScheme)
                    ? 'Include http:// or https://'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _country,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Country',
                prefixIcon: Icon(Icons.public),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tags,
              decoration: const InputDecoration(
                labelText: 'Tags (comma separated)',
                prefixIcon: Icon(Icons.label_outline),
                helperText: 'e.g. Marie-Curie, Bioinformatics',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Notes',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _reminderEnabled,
              onChanged: (v) => setState(() => _reminderEnabled = v),
              title: const Text('Deadline reminders'),
              subtitle: const Text(
                  'Reminders only fire while the status is “Not applied”.'),
            ),
          ],
        ),
      ),
    );
  }
}
