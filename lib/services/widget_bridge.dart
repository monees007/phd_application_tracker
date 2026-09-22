import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/position.dart';

/// Pushes a snapshot of upcoming deadlines to the Android home screen widget.
///
/// The widget process cannot run Dart or reach Firestore, so the app writes a
/// plain JSON snapshot into native SharedPreferences and asks Android to
/// redraw. That means the widget shows whatever was true the last time the app
/// ran — which for deadlines weeks out is fine, and the widget says when it
/// last synced so a stale reading is visible rather than misleading.
class WidgetBridge {
  WidgetBridge._();
  static final WidgetBridge instance = WidgetBridge._();

  static const _channel = MethodChannel('app.phdtracker/widget');

  /// The widget layout has room for five rows plus an overflow line.
  static const _maxRows = 5;

  Future<void> push(List<Position> positions) async {
    final upcoming = positions
        .where((p) =>
            !p.archived &&
            p.status.needsAction &&
            p.deadline != null &&
            (p.daysLeft ?? -1) >= 0)
        .toList()
      ..sort((a, b) => a.deadline!.compareTo(b.deadline!));

    final payload = {
      'syncedAt': DateTime.now().toIso8601String(),
      'total': upcoming.length,
      'items': [
        for (final p in upcoming.take(_maxRows))
          {
            'title': p.programme.isEmpty ? p.university : p.programme,
            'subtitle': p.university,
            'daysLeft': p.daysLeft,
            'deadline': p.deadline!.toIso8601String().substring(0, 10),
          }
      ],
    };

    try {
      await _channel.invokeMethod<void>('updateWidget', jsonEncode(payload));
    } on MissingPluginException {
      // No widget placed, or the channel is not up yet. Nothing to do.
    } on PlatformException catch (e) {
      debugPrint('WidgetBridge: ${e.message}');
    }
  }
}
