import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// One piece of translated text found on the page (a bubble, sign, etc.).
class TranslationItem {
  final String type; // speech | thought | narration | sign | sfx
  final String? speaker;
  final String original;
  final String translation;

  TranslationItem({
    required this.type,
    this.speaker,
    required this.original,
    required this.translation,
  });

  factory TranslationItem.fromJson(Map<String, dynamic> json) {
    final speaker = json['speaker']?.toString().trim();
    return TranslationItem(
      type: (json['type'] ?? 'speech').toString(),
      speaker: (speaker == null || speaker.isEmpty || speaker == 'null')
          ? null
          : speaker,
      original: (json['original'] ?? '').toString(),
      translation: (json['translation'] ?? '').toString(),
    );
  }
}

class TranslationResult {
  final String language;
  final String summary;
  final List<TranslationItem> items;

  TranslationResult({
    required this.language,
    required this.summary,
    required this.items,
  });
}

/// Thrown with a plain-English message that is safe to show the user.
class GeminiException implements Exception {
  final String message;
  GeminiException(this.message);

  @override
  String toString() => message;
}

const String defaultModel = 'gemini-2.5-flash';

const String _prompt = '''
You are an expert manga, manhwa, manhua and comic translator.

Look at this comic page image. Find EVERY piece of text on it: speech bubbles,
thought bubbles, narration boxes, signs/labels, and sound effects.

Detect the source language automatically. List the items in natural reading
order: right-to-left and top-to-bottom for Japanese manga, left-to-right for
most other comics.

Respond ONLY with JSON in exactly this shape:
{
  "language": "name of the detected source language in English",
  "summary": "one or two sentences describing what happens on this page",
  "items": [
    {
      "type": "speech | thought | narration | sign | sfx",
      "speaker": "very short description of who says it (e.g. 'girl with glasses'), or null if unclear",
      "original": "the original text exactly as written",
      "translation": "a natural, colloquial English translation that keeps the tone"
    }
  ]
}

Translation guidelines:
- Sound natural in English; do not translate word-for-word.
- Keep honorifics like -san/-chan when they matter, otherwise drop them.
- For sound effects, give the meaning, e.g. "BAM (sound of a door slamming)".
- If the page contains no text at all, return "items": [].
''';

Future<TranslationResult> translateImage({
  required Uint8List bytes,
  required String mimeType,
  required String apiKey,
  required String model,
}) async {
  final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');

  final body = jsonEncode({
    'contents': [
      {
        'parts': [
          {'text': _prompt},
          {
            'inline_data': {
              'mime_type': mimeType,
              'data': base64Encode(bytes),
            }
          },
        ]
      }
    ],
    'generationConfig': {
      'temperature': 0.2,
      'response_mime_type': 'application/json',
    },
  });

  http.Response response;
  try {
    response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: body,
        )
        .timeout(const Duration(seconds: 120));
  } on SocketException {
    throw GeminiException(
        'No internet connection. Check your wi-fi or mobile data and try again.');
  } on TimeoutException {
    throw GeminiException(
        'The translation took too long and timed out. Try again in a moment.');
  }

  if (response.statusCode != 200) {
    throw GeminiException(_friendlyHttpError(response));
  }

  return _parseResponse(response.body);
}

String _friendlyHttpError(http.Response response) {
  String apiMessage = '';
  try {
    final decoded = jsonDecode(response.body);
    apiMessage = (decoded['error']?['message'] ?? '').toString();
  } catch (_) {}

  switch (response.statusCode) {
    case 400:
    case 401:
    case 403:
      if (apiMessage.toLowerCase().contains('api key') ||
          response.statusCode != 400) {
        return 'Google did not accept your API key. Open Settings and check '
            'that the key was pasted correctly (no extra spaces).';
      }
      return 'Google rejected the request: $apiMessage';
    case 404:
      return 'The AI model name in Settings looks wrong. Open Settings and '
          'reset it to "$defaultModel".';
    case 429:
      return 'You hit the free usage limit for the moment. Wait about a '
          'minute and try again.';
    case 500:
    case 503:
      return 'Google\'s servers are busy right now. Try again in a minute.';
    default:
      return 'Something went wrong (error ${response.statusCode}). '
          '${apiMessage.isNotEmpty ? apiMessage : 'Try again in a moment.'}';
  }
}

TranslationResult _parseResponse(String responseBody) {
  String text;
  try {
    final decoded = jsonDecode(responseBody);
    text = decoded['candidates'][0]['content']['parts'][0]['text'].toString();
  } catch (_) {
    throw GeminiException(
        'The AI sent back an unexpected reply. Try again in a moment.');
  }

  // The model is asked for pure JSON, but trim to the outermost braces just
  // in case it wraps the JSON in extra text.
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start == -1 || end <= start) {
    throw GeminiException(
        'The AI sent back an unexpected reply. Try again in a moment.');
  }

  try {
    final json = jsonDecode(text.substring(start, end + 1));
    final items = ((json['items'] ?? []) as List)
        .whereType<Map<String, dynamic>>()
        .map(TranslationItem.fromJson)
        .where((item) => item.translation.isNotEmpty || item.original.isNotEmpty)
        .toList();
    return TranslationResult(
      language: (json['language'] ?? 'Unknown').toString(),
      summary: (json['summary'] ?? '').toString(),
      items: items,
    );
  } catch (_) {
    throw GeminiException(
        'Could not read the AI\'s reply. Try translating the page again.');
  }
}
