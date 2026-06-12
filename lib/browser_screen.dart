import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';

import 'chapter_reader_screen.dart';

/// In-app browser (Windows only). Browse to a manga chapter on any site,
/// then hit "Translate this chapter" to pull the page images out and
/// translate them all.
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

const Map<String, String> _bookmarks = {
  'MangaFire': 'https://mangafire.to',
  'Rawkuma (JP raws)': 'https://rawkuma.com',
  'MangaDex (many languages)': 'https://mangadex.org',
};

/// Finds the chapter page images on the open web page. Prefers <canvas>
/// elements when the site renders pages into canvases (some readers do),
/// otherwise collects all large <img> elements in document order.
const String _collectScript = r'''
(function () {
  var imgUrls = [];
  var canvasUrls = [];
  var seen = {};
  var imgs = document.querySelectorAll('img');
  for (var i = 0; i < imgs.length; i++) {
    var im = imgs[i];
    var u = im.currentSrc || im.src || im.getAttribute('data-src') ||
            im.getAttribute('data-url') || im.getAttribute('data-lazy-src');
    if (!u) continue;
    var w = im.naturalWidth || im.width || 0;
    var h = im.naturalHeight || im.height || 0;
    if (w < 300 || h < 300) continue;
    try { u = new URL(u, location.href).href; } catch (e) { continue; }
    if (u.indexOf('http') !== 0 && u.indexOf('blob:') !== 0) continue;
    if (seen[u]) continue;
    seen[u] = 1;
    imgUrls.push(u);
  }
  var cvs = document.querySelectorAll('canvas');
  for (var j = 0; j < cvs.length; j++) {
    if (cvs[j].width >= 300 && cvs[j].height >= 300) {
      canvasUrls.push('canvas:' + j);
    }
  }
  return canvasUrls.length >= 3 ? canvasUrls : imgUrls.concat(canvasUrls);
})()
''';

class _BrowserScreenState extends State<BrowserScreen> {
  final WebviewController _controller = WebviewController();
  final TextEditingController _urlController = TextEditingController();
  bool _ready = false;
  bool _collecting = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();
      await _controller
          .setPopupWindowPolicy(WebviewPopupWindowPolicy.sameWindow);
      _controller.url.listen((url) {
        if (mounted) setState(() => _urlController.text = url);
      });
      await _controller.loadUrl(_bookmarks.values.first);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) {
        setState(() => _initError =
            'The built-in browser needs "Microsoft Edge WebView2", which is '
            'normally already part of Windows. ($e)');
      }
    }
  }

  void _go(String input) {
    var url = input.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    _controller.loadUrl(url);
  }

  Future<void> _translateChapter() async {
    setState(() => _collecting = true);
    List<String> urls = [];
    try {
      dynamic value = await _controller.executeScript(_collectScript);
      // Depending on the plugin version the result may arrive as a JSON
      // string instead of a decoded list — handle both.
      for (var i = 0; i < 2 && value is String; i++) {
        try {
          value = jsonDecode(value);
        } catch (_) {
          break;
        }
      }
      if (value is List) {
        urls = value.whereType<String>().take(80).toList();
      }
    } catch (_) {
      urls = [];
    } finally {
      if (mounted) setState(() => _collecting = false);
    }

    if (!mounted) return;

    if (urls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No manga pages found here. Open a chapter first, '
            'scroll through it so the pages load, then try again.'),
        duration: Duration(seconds: 5),
      ));
      return;
    }

    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Found ${urls.length} page images'),
        content: const Text(
            'Translate them all? Pages are translated one by one, so a full '
            'chapter takes a few minutes on the free plan. You can start '
            'reading while the rest finishes.\n\n'
            'Tip: if the number looks too low, scroll through the whole '
            'chapter first so every page loads.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Translate'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          ChapterReaderScreen(controller: _controller, imageUrls: urls),
    ));
  }

  @override
  void dispose() {
    _urlController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse manga sites'),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            tooltip: 'Back',
            onPressed: _ready ? () => _controller.goBack() : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _ready ? () => _controller.reload() : null,
          ),
        ],
      ),
      body: _initError != null ? _errorView() : _browserView(),
      floatingActionButton: _ready
          ? FloatingActionButton.extended(
              onPressed: _collecting ? null : _translateChapter,
              icon: _collecting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.translate),
              label: const Text('Translate this chapter'),
            )
          : null,
    );
  }

  Widget _errorView() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text(_initError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => launchUrl(
                      Uri.parse(
                          'https://developer.microsoft.com/microsoft-edge/webview2'),
                      mode: LaunchMode.externalApplication),
                  child: const Text('Get WebView2 from Microsoft'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _browserView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: 'Type a website address and press Enter',
                    prefixIcon: Icon(Icons.public, size: 20),
                  ),
                  onSubmitted: _go,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () => _go(_urlController.text),
                child: const Text('Go'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              for (final entry in _bookmarks.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(entry.key),
                    onPressed: () => _go(entry.value),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _ready
              ? Webview(_controller)
              : const Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }
}
