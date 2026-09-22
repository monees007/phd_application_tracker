import 'package:flutter/material.dart';

import '../services/gemini_service.dart';
import '../services/settings_service.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _settings = SettingsService();
  final _keyCtrl = TextEditingController();

  String _model = GeminiService.defaultModel;
  List<String>? _availableModels;
  bool _loading = true;
  bool _fetchingModels = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final key = await _settings.geminiApiKey();
    final model = await _settings.geminiModel();
    if (!mounted) return;
    setState(() {
      _keyCtrl.text = key;
      _model = model;
      _loading = false;
    });
  }

  Future<void> _fetchModels() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _fetchingModels = true);
    final gemini = GeminiService();
    try {
      final models = await gemini.listModels(_keyCtrl.text.trim());
      if (!mounted) return;
      setState(() => _availableModels = models);
      if (models.isEmpty) {
        messenger.showSnackBar(const SnackBar(
            content: Text('The key works but returned no models.')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      gemini.dispose();
      if (mounted) setState(() => _fetchingModels = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI extraction'),
        actions: [
          TextButton(
            onPressed: () async {
              await _settings.setGeminiApiKey(_keyCtrl.text.trim());
              await _settings.setGeminiModel(_model);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Saved')));
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Text(
            'Sharing a job advert link into this app sends the page text to '
            'Google\'s Gemini API to pull out the university, title and '
            'deadline. Nothing is saved until you review it.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _keyCtrl,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Gemini API key',
              helperText: 'From aistudio.google.com → Get API key',
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Model', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          if (_availableModels == null)
            TextFormField(
              initialValue: _model,
              decoration: const InputDecoration(
                labelText: 'Model ID',
                helperText:
                    'Model names change and old ones are retired. Fetch the '
                    'list to see what your key can actually use.',
              ),
              onChanged: (v) => _model = v,
            )
          else
            DropdownButtonFormField<String>(
              initialValue:
                  _availableModels!.contains(_model) ? _model : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Model ID'),
              items: [
                for (final m in _availableModels!)
                  DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: (v) => setState(() => _model = v ?? _model),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _fetchingModels || _keyCtrl.text.trim().isEmpty
                ? null
                : _fetchModels,
            icon: _fetchingModels
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_download_outlined),
            label: const Text('Fetch available models'),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16),
                    const SizedBox(width: 8),
                    Text('About the key',
                        style: Theme.of(context).textTheme.labelLarge),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'The key is stored in SharedPreferences on this device. '
                  'That is fine for a personal build, but it is not encrypted '
                  'and it would be extractable from the APK\'s data on a '
                  'rooted device. Do not ship this app to anyone else with '
                  'your key in it, and revoke the key in AI Studio if you '
                  'lose the phone.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
