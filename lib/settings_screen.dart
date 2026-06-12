import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'gemini_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const String apiKeyPref = 'gemini_api_key';
  static const String modelPref = 'gemini_model';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  bool _hideKey = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _keyController.text = prefs.getString(SettingsScreen.apiKeyPref) ?? '';
    _modelController.text =
        prefs.getString(SettingsScreen.modelPref) ?? defaultModel;
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        SettingsScreen.apiKeyPref, _keyController.text.trim());
    final model = _modelController.text.trim();
    await prefs.setString(
        SettingsScreen.modelPref, model.isEmpty ? defaultModel : model);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved!')),
    );
    Navigator.of(context).pop();
  }

  Future<void> _openKeyPage() async {
    final uri = Uri.parse('https://aistudio.google.com/apikey');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Could not open the browser. Go to aistudio.google.com/apikey')),
      );
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Get your free Google AI key',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        const Text(
                          '1. Tap the button below — it opens Google AI Studio.\n'
                          '2. Sign in with your Google account.\n'
                          '3. Tap "Create API key".\n'
                          '4. Copy the long code it gives you.\n'
                          '5. Come back here and paste it in the box below.\n\n'
                          'The free plan is plenty for reading manga — no credit '
                          'card needed.',
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed: _openKeyPage,
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open Google AI Studio'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _keyController,
                  obscureText: _hideKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'API key',
                    hintText: 'Paste your key here',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _hideKey ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _hideKey = !_hideKey),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ExpansionTile(
                  title: const Text('Advanced'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  children: [
                    TextField(
                      controller: _modelController,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'AI model name',
                        helperText:
                            'Leave as-is unless something stops working. '
                            'Default: $defaultModel',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: const Text('Save'),
                ),
              ],
            ),
    );
  }
}
