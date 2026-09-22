import 'dart:convert';

import 'package:http/http.dart' as http;

class FetchedPage {
  final Uri url;
  final String text;
  final String? pageTitle;

  /// True when the fetch succeeded but yielded too little prose to be a real
  /// job description — almost always a JavaScript-rendered page whose content
  /// arrives via XHR after load. An HTTP GET cannot see that content.
  final bool looksEmpty;

  const FetchedPage({
    required this.url,
    required this.text,
    required this.pageTitle,
    required this.looksEmpty,
  });
}

class PageFetchException implements Exception {
  final String message;
  const PageFetchException(this.message);
  @override
  String toString() => message;
}

class PageFetcher {
  /// Below this many characters of extracted prose, treat the page as empty.
  /// A genuine PhD advert is several thousand characters; a JS shell is a few
  /// hundred of nav and footer boilerplate.
  static const _minUsefulChars = 600;

  /// Hard cap on what gets sent to the model. Keeps token cost bounded and
  /// well inside request limits; job adverts put the useful parts early.
  static const _maxChars = 24000;

  final http.Client _client;

  PageFetcher({http.Client? client}) : _client = client ?? http.Client();

  Future<FetchedPage> fetch(Uri url) async {
    late http.Response res;
    try {
      res = await _client.get(
        url,
        headers: {
          // Some university sites serve a stub or a 403 to unknown agents.
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'en',
        },
      ).timeout(const Duration(seconds: 25));
    } catch (e) {
      throw PageFetchException('Could not reach the page: $e');
    }

    if (res.statusCode != 200) {
      throw PageFetchException(
          'The site returned HTTP ${res.statusCode} for this link.');
    }

    final contentType = res.headers['content-type'] ?? '';
    if (!contentType.contains('html') && !contentType.contains('text')) {
      throw PageFetchException(
          'That link is not a web page (content type: $contentType). '
          'PDF adverts need to be pasted in manually.');
    }

    // http decodes as latin-1 unless the charset says otherwise, which
    // mangles the Scandinavian and German characters common in these adverts.
    final html = _decode(res);
    final title = _extractTitle(html);
    final text = htmlToText(html);

    return FetchedPage(
      url: url,
      text: text.length > _maxChars ? text.substring(0, _maxChars) : text,
      pageTitle: title,
      looksEmpty: _looksLikeShell(text),
    );
  }

  String _decode(http.Response res) {
    try {
      return utf8.decode(res.bodyBytes, allowMalformed: true);
    } catch (_) {
      return res.body;
    }
  }

  /// A real advert always contains application language somewhere. Nav chrome
  /// and cookie banners clear a character-count threshold but never contain
  /// these, which makes this a sharper test than length alone.
  static bool _looksLikeShell(String text) {
    if (text.length < _minUsefulChars) return true;
    final lower = text.toLowerCase();
    const markers = [
      'deadline', 'apply', 'application', 'qualification',
      'we offer', 'position', 'doctoral', 'phd',
    ];
    return markers.where(lower.contains).length < 2;
  }

  String? _extractTitle(String html) {
    final m = RegExp(r'<title[^>]*>(.*?)</title>',
            caseSensitive: false, dotAll: true)
        .firstMatch(html);
    if (m == null) return null;
    final t = _decodeEntities(m.group(1)!).trim();
    return t.isEmpty ? null : t;
  }

  /// Reduces HTML to readable prose.
  ///
  /// This is a regex reduction, not a parser, so it is approximate — it will
  /// keep some navigation text and drop some structure. That is an acceptable
  /// trade here: the output is only ever read by a language model, which
  /// tolerates noise, and it avoids a dependency on an HTML parsing package.
  static String htmlToText(String html) {
    var s = html;

    // Whole subtrees whose text content is never part of the advert.
    for (final tag in ['script', 'style', 'noscript', 'svg', 'head']) {
      s = s.replaceAll(
        RegExp('<$tag[^>]*>.*?</$tag>',
            caseSensitive: false, dotAll: true),
        ' ',
      );
    }

    s = s.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ');

    // Block-level tags become newlines so list items and paragraphs do not
    // run together into one unreadable line.
    s = s.replaceAll(
      RegExp(r'</(p|div|li|tr|h[1-6]|section|article|br)\s*>',
          caseSensitive: false),
      '\n',
    );
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');

    s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
    s = _decodeEntities(s);

    // Collapse the whitespace the tag stripping left behind.
    s = s.replaceAll(RegExp(r'[ \t\u00A0]+'), ' ');
    s = s.replaceAll(RegExp(r'\n\s*\n\s*(\n\s*)+'), '\n\n');
    s = s.split('\n').map((l) => l.trim()).join('\n');

    return s.trim();
  }

  static String _decodeEntities(String s) {
    const named = {
      '&nbsp;': ' ',
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
      '&apos;': "'",
      '&ndash;': '-',
      '&mdash;': '-',
      '&rsquo;': "'",
      '&lsquo;': "'",
      '&ldquo;': '"',
      '&rdquo;': '"',
      '&hellip;': '...',
      '&euro;': 'EUR',
      '&pound;': 'GBP',
    };
    var out = s;
    named.forEach((k, v) => out = out.replaceAll(k, v));

    // Numeric entities, decimal and hex.
    out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });
    out = out.replaceAllMapped(RegExp(r'&#[xX]([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });

    return out;
  }

  void dispose() => _client.close();
}
