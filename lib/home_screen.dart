import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'browser_screen.dart';
import 'gemini_service.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();

  Uint8List? _imageBytes;
  String _mimeType = 'image/jpeg';
  TranslationResult? _result;
  String? _error;
  bool _busy = false;
  bool _hasApiKey = true;

  bool get _isAndroid {
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  bool get _isWindows {
    try {
      return Platform.isWindows;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _checkApiKey();
  }

  Future<void> _checkApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(SettingsScreen.apiKeyPref) ?? '';
    if (mounted) setState(() => _hasApiKey = key.trim().isNotEmpty);
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final lowerPath = file.path.toLowerCase();
      setState(() {
        _imageBytes = bytes;
        _mimeType = lowerPath.endsWith('.png')
            ? 'image/png'
            : lowerPath.endsWith('.webp')
                ? 'image/webp'
                : 'image/jpeg';
        _result = null;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not open that image. Try another one.');
    }
  }

  Future<void> _translate() async {
    final bytes = _imageBytes;
    if (bytes == null) return;

    final prefs = await SharedPreferences.getInstance();
    final apiKey = (prefs.getString(SettingsScreen.apiKeyPref) ?? '').trim();
    final model = (prefs.getString(SettingsScreen.modelPref) ?? '').trim();

    if (apiKey.isEmpty) {
      setState(() => _hasApiKey = false);
      _openSettings();
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await translateImage(
        bytes: bytes,
        mimeType: _mimeType,
        apiKey: apiKey,
        model: model.isEmpty ? defaultModel : model,
      );
      if (mounted) setState(() => _result = result);
    } on GeminiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Something unexpected went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    _checkApiKey();
  }

  void _copyAll() {
    final result = _result;
    if (result == null) return;
    final buffer = StringBuffer();
    for (var i = 0; i < result.items.length; i++) {
      final item = result.items[i];
      buffer.writeln('${i + 1}. ${item.original}');
      buffer.writeln('   ${item.translation}');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All translations copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manga Translator'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_hasApiKey) _apiKeyBanner(),
          _imageCard(),
          const SizedBox(height: 12),
          _actionButtons(),
          if (_busy) ...[
            const SizedBox(height: 32),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 12),
            const Center(child: Text('Reading the page…')),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: Theme.of(context).colorScheme.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_result != null) ..._resultWidgets(_result!),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _apiKeyBanner() {
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.key),
        title: const Text('One-time setup needed'),
        subtitle: const Text(
            'Tap here to add your free Google AI key (takes 2 minutes).'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _openSettings,
      ),
    );
  }

  Widget _imageCard() {
    final bytes = _imageBytes;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: bytes == null
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(Icons.menu_book,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  const Text(
                    'Pick a manga page to translate',
                    style: TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
    );
  }

  Widget _actionButtons() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: [
        FilledButton.tonalIcon(
          onPressed: _busy ? null : () => _pickImage(ImageSource.gallery),
          icon: const Icon(Icons.image),
          label: Text(_isAndroid ? 'Choose from gallery' : 'Choose image'),
        ),
        if (_isAndroid)
          FilledButton.tonalIcon(
            onPressed: _busy ? null : () => _pickImage(ImageSource.camera),
            icon: const Icon(Icons.photo_camera),
            label: const Text('Take photo'),
          ),
        if (_isWindows)
          FilledButton.tonalIcon(
            onPressed: _busy
                ? null
                : () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const BrowserScreen()));
                  },
            icon: const Icon(Icons.public),
            label: const Text('Translate from a website'),
          ),
        if (_imageBytes != null)
          FilledButton.icon(
            onPressed: _busy ? null : _translate,
            icon: const Icon(Icons.translate),
            label: Text(_result == null ? 'Translate' : 'Translate again'),
          ),
      ],
    );
  }

  List<Widget> _resultWidgets(TranslationResult result) {
    return [
      const SizedBox(height: 16),
      Row(
        children: [
          Chip(
            avatar: const Icon(Icons.language, size: 18),
            label: Text(result.language),
          ),
          const Spacer(),
          if (result.items.isNotEmpty)
            TextButton.icon(
              onPressed: _copyAll,
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy all'),
            ),
        ],
      ),
      if (result.summary.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            result.summary,
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      if (result.items.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: Text('No text was found on this page.')),
        ),
      for (var i = 0; i < result.items.length; i++)
        _itemCard(i + 1, result.items[i]),
    ];
  }

  Widget _itemCard(int number, TranslationItem item) {
    final icon = switch (item.type) {
      'thought' => Icons.cloud_outlined,
      'narration' => Icons.notes,
      'sign' => Icons.signpost_outlined,
      'sfx' => Icons.volume_up_outlined,
      _ => Icons.chat_bubble_outline,
    };
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: item.translation));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Translation copied')),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 14,
                child: Text('$number', style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon,
                            size: 16,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        if (item.speaker != null)
                          Expanded(
                            child: Text(
                              item.speaker!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.original,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.translation,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
