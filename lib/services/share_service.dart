import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What arrived through the share sheet.
///
/// Android sends one blob of text either way, so the two cases have to be told
/// apart by shape: a browser's "share link" is a short string containing a URL,
/// while "select text → share" is a wall of prose that may or may not also
/// carry a URL.
class SharedPayload {
  final Uri? url;

  /// Page text the user shared directly, already long enough to extract from.
  /// Null when all we got was a link.
  final String? content;

  const SharedPayload({this.url, this.content});

  bool get hasContent => content != null;
  bool get isUsable => hasContent || url != null;
}

class ShareService {
  ShareService._();
  static final ShareService instance = ShareService._();

  static const _channel = MethodChannel('app.phdtracker/share');

  /// Text shorter than this is treated as a link share with a title attached,
  /// not as page content. A real advert is thousands of characters; a share
  /// subject line is tens.
  static const _contentThreshold = 400;

  Future<String?> consumePendingShare() async {
    try {
      return await _channel.invokeMethod<String>('consumePendingShare');
    } on MissingPluginException {
      return null; // hot restart can outrun channel registration
    } on PlatformException catch (e) {
      debugPrint('ShareService: ${e.message}');
      return null;
    }
  }

  Future<void> moveToBack() async {
    try {
      await _channel.invokeMethod<void>('moveToBack');
    } on PlatformException catch (_) {/* not fatal */}
  }

  static SharedPayload classify(String shared) {
    final url = extractUrl(shared);

    // Measure the prose with any URL removed, so a long URL cannot on its own
    // push a link share over the content threshold.
    final withoutUrl =
        shared.replaceAll(RegExp(r'https?://[^\s<>"\]]+'), ' ').trim();

    return SharedPayload(
      url: url,
      content: withoutUrl.length >= _contentThreshold ? shared.trim() : null,
    );
  }

  /// Pulls the first http(s) URL out of shared text. Share sheets rarely hand
  /// over a bare URL — usually "Job title — https://…" or similar.
  static Uri? extractUrl(String shared) {
    final match = RegExp(r'https?://[^\s<>"\]]+').firstMatch(shared);
    if (match == null) return null;

    var raw = match.group(0)!;
    while (raw.isNotEmpty && '.,;:)]}>"\''.contains(raw[raw.length - 1])) {
      raw = raw.substring(0, raw.length - 1);
    }

    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri;
  }
}
