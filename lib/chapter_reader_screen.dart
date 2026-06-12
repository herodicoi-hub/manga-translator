import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_windows/webview_windows.dart';

import 'gemini_service.dart';
import 'settings_screen.dart';

enum _PageStatus { waiting, downloading, downloadFailed, translating, done, failed }

class _PageData {
  final String url;
  Uint8List? bytes;
  String mime = 'image/jpeg';
  _PageStatus status = _PageStatus.waiting;
  TranslationResult? result;
  String? error;

  _PageData(this.url);
}

/// Reads a chapter: downloads each page image through the browser tab that
/// is still open underneath (so the website treats it as normal browsing),
/// translates page by page, and shows image + translations side by side.
class ChapterReaderScreen extends StatefulWidget {
  final WebviewController controller;
  final List<String> imageUrls;

  const ChapterReaderScreen({
    super.key,
    required this.controller,
    required this.imageUrls,
  });

  @override
  State<ChapterReaderScreen> createState() => _ChapterReaderScreenState();
}

class _ChapterReaderScreenState extends State<ChapterReaderScreen> {
  late final List<_PageData> _pages;
  StreamSubscription<dynamic>? _subscription;
  Completer<Map<String, dynamic>>? _pending;
  String? _pendingUrl;
  int _current = 0;
  bool _stopped = false;
  bool _working = true;
  String _phase = 'Preparing…';

  @override
  void initState() {
    super.initState();
    _pages = widget.imageUrls.map(_PageData.new).toList();
    _subscription = widget.controller.webMessage.listen(_onWebMessage);
    _run();
  }

  @override
  void dispose() {
    _stopped = true;
    _subscription?.cancel();
    super.dispose();
  }

  void _onWebMessage(dynamic message) {
    if (message is! Map) return;
    final type = message['type'];
    if (type != 'mtImage' && type != 'mtError') return;
    if (_pending != null &&
        !_pending!.isCompleted &&
        message['url'] == _pendingUrl) {
      _pending!.complete(Map<String, dynamic>.from(message));
    }
  }

  String _fetchScript(String url) {
    final encoded = jsonEncode(url);
    return '''
(function () {
  function send(o) { window.chrome.webview.postMessage(o); }
  var u = $encoded;
  if (u.indexOf('canvas:') === 0) {
    try {
      var idx = parseInt(u.substring(7));
      var c = document.querySelectorAll('canvas')[idx];
      send({type: 'mtImage', url: u, data: c.toDataURL('image/jpeg', 0.92)});
    } catch (e) {
      send({type: 'mtError', url: u, message: String(e)});
    }
    return;
  }
  fetch(u, {credentials: 'include'}).then(function (r) {
    if (!r.ok) throw new Error('HTTP ' + r.status);
    return r.blob();
  }).then(function (b) {
    return new Promise(function (resolve, reject) {
      var fr = new FileReader();
      fr.onload = function () { resolve(fr.result); };
      fr.onerror = function () { reject(new Error('could not read image')); };
      fr.readAsDataURL(b);
    });
  }).then(function (d) {
    send({type: 'mtImage', url: u, data: d});
  }).catch(function (e) {
    send({type: 'mtError', url: u, message: String(e)});
  });
})()
''';
  }

  Future<void> _run() async {
    // Phase 1: pull every page image out of the website.
    for (var i = 0; i < _pages.length; i++) {
      if (_stopped) return;
      final page = _pages[i];
      _setState(() {
        page.status = _PageStatus.downloading;
        _phase = 'Getting page ${i + 1} of ${_pages.length} from the site…';
      });
      try {
        _pendingUrl = page.url;
        _pending = Completer<Map<String, dynamic>>();
        await widget.controller.executeScript(_fetchScript(page.url));
        final message =
            await _pending!.future.timeout(const Duration(seconds: 60));
        if (message['type'] == 'mtImage') {
          final dataUrl = message['data'].toString();
          final comma = dataUrl.indexOf(',');
          final header = dataUrl.substring(0, comma);
          final mimeMatch = RegExp('data:([^;]+)').firstMatch(header);
          page.mime = mimeMatch?.group(1) ?? 'image/jpeg';
          page.bytes = base64Decode(dataUrl.substring(comma + 1));
          page.status = _PageStatus.waiting;
        } else {
          page.status = _PageStatus.downloadFailed;
          page.error = 'The site refused to hand over this page '
              '(${message['message']}).';
        }
      } catch (_) {
        page.status = _PageStatus.downloadFailed;
        page.error = 'Timed out getting this page from the site.';
      }
      _setState(() {});
    }

    // Phase 2: translate page by page.
    final prefs = await SharedPreferences.getInstance();
    final apiKey = (prefs.getString(SettingsScreen.apiKeyPref) ?? '').trim();
    final model = (prefs.getString(SettingsScreen.modelPref) ?? '').trim();

    for (var i = 0; i < _pages.length; i++) {
      if (_stopped) return;
      final page = _pages[i];
      if (page.bytes == null) continue;
      _setState(() => _phase = 'Translating page ${i + 1} of ${_pages.length}…');
      await _translatePage(page, apiKey, model,
          label: 'page ${i + 1} of ${_pages.length}');
      _setState(() {});
      // Stay politely under the free plan's per-minute limit.
      await Future.delayed(const Duration(seconds: 4));
    }

    _setState(() {
      _working = false;
      _phase = '';
    });
  }

  Future<void> _translatePage(_PageData page, String apiKey, String model,
      {String? label}) async {
    page.status = _PageStatus.translating;
    _setState(() {});
    for (var attempt = 0; attempt < 3; attempt++) {
      if (_stopped) return;
      try {
        page.result = await translateImage(
          bytes: page.bytes!,
          mimeType: page.mime,
          apiKey: apiKey,
          model: model.isEmpty ? defaultModel : model,
        );
        page.status = _PageStatus.done;
        page.error = null;
        return;
      } on GeminiException catch (e) {
        if (e.statusCode == 429 && attempt < 2) {
          _setState(() => _phase =
              'Free limit reached for the moment — waiting 35 seconds, then '
              'continuing with ${label ?? 'this page'}…');
          for (var s = 0; s < 35 && !_stopped; s++) {
            await Future.delayed(const Duration(seconds: 1));
          }
          continue;
        }
        page.status = _PageStatus.failed;
        page.error = e.message;
        return;
      } catch (_) {
        page.status = _PageStatus.failed;
        page.error = 'Something unexpected went wrong on this page.';
        return;
      }
    }
  }

  Future<void> _retryPage(_PageData page) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = (prefs.getString(SettingsScreen.apiKeyPref) ?? '').trim();
    final model = (prefs.getString(SettingsScreen.modelPref) ?? '').trim();
    await _translatePage(page, apiKey, model);
    _setState(() {});
  }

  void _setState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  void _goTo(int index) {
    if (index < 0 || index >= _pages.length) return;
    setState(() => _current = index);
  }

  void _copyPage(_PageData page) {
    final result = page.result;
    if (result == null) return;
    final buffer = StringBuffer();
    for (var i = 0; i < result.items.length; i++) {
      final item = result.items[i];
      buffer.writeln('${i + 1}. ${item.original}');
      buffer.writeln('   ${item.translation}');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Page translations copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_current];
    final doneCount =
        _pages.where((p) => p.status == _PageStatus.done).length;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _goTo(_current + 1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _goTo(_current - 1),
        const SingleActivator(LogicalKeyboardKey.pageDown): () =>
            _goTo(_current + 1),
        const SingleActivator(LogicalKeyboardKey.pageUp): () =>
            _goTo(_current - 1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Text('Page ${_current + 1} of ${_pages.length}'),
            actions: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous page (left arrow)',
                onPressed: _current > 0 ? () => _goTo(_current - 1) : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next page (right arrow)',
                onPressed: _current < _pages.length - 1
                    ? () => _goTo(_current + 1)
                    : null,
              ),
              if (page.result != null)
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy this page\'s translations',
                  onPressed: () => _copyPage(page),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            children: [
              if (_working) ...[
                LinearProgressIndicator(
                  value: _pages.isEmpty ? null : doneCount / _pages.length,
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_phase, style: const TextStyle(fontSize: 13)),
                ),
              ],
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Container(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: page.bytes == null
                            ? const Center(child: CircularProgressIndicator())
                            : InteractiveViewer(
                                maxScale: 5,
                                child: Center(
                                  child: Image.memory(page.bytes!,
                                      fit: BoxFit.contain),
                                ),
                              ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      flex: 2,
                      child: _translationPanel(page),
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

  Widget _translationPanel(_PageData page) {
    switch (page.status) {
      case _PageStatus.waiting:
      case _PageStatus.downloading:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Waiting for this page\'s turn…'),
          ),
        );
      case _PageStatus.translating:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Translating this page…'),
            ],
          ),
        );
      case _PageStatus.downloadFailed:
      case _PageStatus.failed:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 12),
                Text(page.error ?? 'Something went wrong on this page.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                if (page.bytes != null)
                  FilledButton.tonalIcon(
                    onPressed: () => _retryPage(page),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try this page again'),
                  ),
              ],
            ),
          ),
        );
      case _PageStatus.done:
        final result = page.result!;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Row(
              children: [
                Chip(
                  avatar: const Icon(Icons.language, size: 18),
                  label: Text(result.language),
                ),
              ],
            ),
            if (result.summary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
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
                child: Center(child: Text('No text on this page.')),
              ),
            for (var i = 0; i < result.items.length; i++)
              _itemCard(i + 1, result.items[i]),
          ],
        );
    }
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
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 12,
                child: Text('$number', style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.speaker != null)
                      Row(
                        children: [
                          Icon(icon,
                              size: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              item.speaker!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    Text(
                      item.original,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.translation,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
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
