import 'package:flutter/material.dart';

import '../services/gemini_service.dart';
import '../services/settings_service.dart';

/// Runs a Gemini extraction on text the user pastes, and hands back the
/// result.
///
/// Shared by the edit screen ("Extract from text") and anywhere else that
/// wants a one-off extraction. Deliberately not routed through
/// ImportQueueService: this is synchronous, in front of the user, and must
/// not create a second position — the caller decides what to do with the
/// result.
class ExtractFromTextSheet extends StatefulWidget {
  const ExtractFromTextSheet({super.key, this.initialText = '', this.url});

  final String initialText;
  final String? url;

  static Future<ExtractedPosition?> show(
    BuildContext context, {
    String initialText = '',
    String? url,
  }) {
    return showModalBottomSheet<ExtractedPosition>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        // Keeps the field above the keyboard.
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ExtractFromTextSheet(initialText: initialText, url: url),
      ),
    );
  }

  @override
  State<ExtractFromTextSheet> createState() => _ExtractFromTextSheetState();
}

class _ExtractFromTextSheetState extends State<ExtractFromTextSheet> {
  late final TextEditingController _text =
      TextEditingController(text: widget.initialText);
  final _settings = SettingsService();

  bool _running = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final text = _text.text.trim();
    if (text.length < 80) {
      setState(() => _error = 'Paste a bit more — that is too short to read.');
      return;
    }

    setState(() {
      _running = true;
      _error = null;
    });

    final gemini = GeminiService();
    try {
      final result = await gemini.extract(
        pageText: text,
        sourceUrl: widget.url ?? 'pasted text',
        apiKey: await _settings.geminiApiKey(),
        model: await _settings.geminiModel(),
      );
      if (!mounted) return;
      Navigator.pop(context, result);
    } on GeminiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      gemini.dispose();
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Extract from text',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'Paste the advert. Anything already filled in will be replaced '
              'by what the model finds, and blank findings leave your values '
              'alone.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _text,
              minLines: 6,
              maxLines: 10,
              autofocus: widget.initialText.isEmpty,
              decoration: const InputDecoration(
                hintText: 'Paste the job description here…',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline,
                      size: 16, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: Theme.of(context).colorScheme.error)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _running ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _running ? null : _run,
                    icon: _running
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome),
                    label: Text(_running ? 'Reading…' : 'Extract'),
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
