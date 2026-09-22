import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'import_queue_service.dart';

import '../models/position.dart';
import 'settings_service.dart';

/// Reminders are scheduled **on-device** with exact alarms rather than pushed
/// from a server. Rationale: a deadline reminder must fire even with no
/// network, must not depend on FCM delivery latency, and costs nothing to run.
/// `functions/index.js` contains an optional server-side FCM backup for people
/// who want a second channel.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'deadline_reminders';
  static const _channelName = 'Deadline reminders';
  static const _channelDesc =
      'Reminders before and on the day an application deadline closes.';

  /// Identifies the Undo button on an auto-saved import notification.
  static const undoActionId = 'undo_import';

  static const _importChannelId = 'import_results';
  static const _importChannelName = 'Link imports';
  static const _importChannelDesc =
      'Results of importing a shared job advert.';


  /// Android allows ~500 pending alarms per app. Stay well under it.
  static const int _maxPending = 440;

  bool _ready = false;

  /// Set by main.dart so a tapped notification can deep-link to a position.
  /// Set by app.dart so a tapped notification can route somewhere.
  void Function(Map<String, dynamic> payload)? onNotificationPayload;

  Future<void> init() async {
    if (_ready) return;

    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (e) {
      // Falls back to UTC. Times would then be offset, so surface it in debug.
      debugPrint('NotificationService: could not resolve local timezone: $e');
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final map = jsonDecode(payload) as Map<String, dynamic>;
          if (resp.actionId != null && resp.actionId!.isNotEmpty) {
            map['action'] = resp.actionId;
          }
          onNotificationPayload?.call(map);
        } catch (_) {/* malformed payload: ignore */}
      },
    );

    final android13 = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android13?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      ),
    );
    await android13?.createNotificationChannel(
      const AndroidNotificationChannel(
        _importChannelId,
        _importChannelName,
        description: _importChannelDesc,
        importance: Importance.defaultImportance,
      ),
    );

    _ready = true;
  }

  /// Android 13+ runtime notification permission.
  Future<bool> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission() ?? false;
    // Android 12+ needs a separate grant for exact alarms. Without it we fall
    // back to inexact scheduling, which can drift by minutes to hours.
    await android?.requestExactAlarmsPermission();
    return granted;
  }

  Future<bool> exactAlarmsAllowed() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.canScheduleExactNotifications() ?? false;
  }

  Future<List<PendingNotificationRequest>> pending() =>
      _plugin.pendingNotificationRequests();

  /// Wipes every scheduled alarm and rebuilds the schedule from scratch.
  ///
  /// Called after any change to the position list or the reminder settings.
  /// Rebuilding wholesale is far simpler to reason about than diffing, and at
  /// a few hundred alarms it is fast enough to be unnoticeable.
  Future<void> rescheduleAll(
    List<Position> positions,
    ReminderSettings settings,
  ) async {
    await init();
    await _plugin.cancelAll();
    if (!settings.enabled) return;

    final now = tz.TZDateTime.now(tz.local);

    // Build the candidate list first, then sort by fire time, so that if we
    // exceed the alarm budget we keep the *soonest* reminders.
    final candidates = <_Reminder>[];

    for (final p in positions) {
      if (p.archived || !p.reminderEnabled) continue;
      if (!p.status.needsAction) continue; // already submitted: nothing to do
      final deadline = p.deadline;
      if (deadline == null) continue;

      for (final lead in settings.leadDays) {
        final fire = _fireTime(deadline, lead, settings.hour, settings.minute);
        if (fire.isAfter(now)) {
          candidates.add(_Reminder(p, lead, fire));
        }
      }
    }

    candidates.sort((a, b) => a.fireAt.compareTo(b.fireAt));

    for (final r in candidates.take(_maxPending)) {
      await _schedule(r);
    }

    if (candidates.length > _maxPending) {
      debugPrint(
        'NotificationService: ${candidates.length} reminders requested, '
        'scheduled the nearest $_maxPending (OS limit).',
      );
    }
  }

  tz.TZDateTime _fireTime(DateTime deadline, int leadDays, int hour, int min) {
    final d = DateTime(deadline.year, deadline.month, deadline.day)
        .subtract(Duration(days: leadDays));
    return tz.TZDateTime(tz.local, d.year, d.month, d.day, hour, min);
  }

  Future<void> _schedule(_Reminder r) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        styleInformation: BigTextStyleInformation(r.body),
      ),
    );

    await _plugin.zonedSchedule(
      r.notificationId,
      r.title,
      r.body,
      r.fireAt,
      details,
      // exactAllowWhileIdle survives Doze. If the user denied the exact-alarm
      // permission the plugin degrades to an inexact alarm rather than throwing.
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
      payload: jsonEncode({
        'type': 'position',
        'positionId': r.position.id,
      }),
    );
  }
  /// Posted the moment an import starts, replaced by the result when it lands.
  /// Low priority and silent — this is status, not an interruption.
  Future<void> showImportProgress(PendingImport record) async {
    await init();
    await _plugin.show(
      _progressNotificationId(record.id),
      'Reading the advert…',
      record.url ?? 'From shared text',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _importChannelId,
          _importChannelName,
          channelDescription: _importChannelDesc,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          playSound: false,
          enableVibration: false,
          showProgress: true,
          indeterminate: true,
        ),
      ),
    );
  }

  Future<void> cancelImportProgress(String importId) =>
      _plugin.cancel(_progressNotificationId(importId));

  int _progressNotificationId(String importId) {
    var hash = 0;
    for (final code in importId.codeUnits) {
      hash = (hash * 31 + code) & 0x0FFFFFFF;
    }
    return 0x50000000 | hash;
  }

  /// Tells the user an import finished, successfully or not. This is the whole
  /// point of running extraction in the background — they get their phone back
  /// and hear about it when it lands.
  Future<void> showImportResult(PendingImport record) async {
    await init();

    final success = record.status == ImportStatus.success;
    final extracted = record.result;
    final saved = record.wasAutoSaved;

    final String title;
    final String body;

    if (saved && success) {
      title = 'Added: ${extracted?.university ?? 'position'}';
      body = [
        if ((extracted?.programme ?? '').isNotEmpty) extracted!.programme!,
        if (extracted?.deadline != null)
          'Deadline ${extracted!.deadline}'
        else
          'No deadline found, so no reminders are set',
      ].join(' \u00b7 ');
    } else if (saved) {
      // Extraction failed but the share was kept verbatim, so the entry is on
      // the board waiting for details rather than lost.
      title = 'Saved as a note';
      body = '${record.error ?? 'Could not read the advert.'} '
          'Tap to fill in the details.';
    } else if (success) {
      title = extracted?.university ?? 'Position found';
      body = [
        extracted?.programme ?? 'Tap to review and save',
        if (extracted?.deadline != null) 'Deadline ${extracted!.deadline}',
      ].join(' \u00b7 ');
    } else {
      title = 'Could not read that advert';
      body = '${record.error ?? ''} Tap to add it manually.'.trim();
    }

    // Carrying the position id lets the tap open the saved entry instead of a
    // review screen for something already on the board.
    final payload = <String, dynamic>{
      'type': 'import',
      'importId': record.id,
      if (record.savedPositionId != null) 'positionId': record.savedPositionId,
    };

    await _plugin.show(
      _importNotificationId(record.id),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _importChannelId,
          _importChannelName,
          channelDescription: _importChannelDesc,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          styleInformation: BigTextStyleInformation(body),
          actions: saved
              ? <AndroidNotificationAction>[
                  const AndroidNotificationAction(
                    undoActionId,
                    'Undo',
                    // Brings the app forward to do the delete. A silent
                    // background action would run in a separate isolate with
                    // no Firebase, which is a lot of machinery for one button.
                    showsUserInterface: true,
                    cancelNotification: true,
                  ),
                ]
              : null,
        ),
      ),
      payload: jsonEncode(payload),
    );
  }


  /// Stable per-import id, offset well clear of the deadline reminder range.
  int _importNotificationId(String importId) {
    var hash = 0;
    for (final code in importId.codeUnits) {
      hash = (hash * 31 + code) & 0x0FFFFFFF;
    }
    return 0x40000000 | hash;
  }

  /// The payload of a notification that cold-started the app, if any.
  Future<Map<String, dynamic>?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    final payload = details!.notificationResponse?.payload;
    if (payload == null || payload.isEmpty) return null;
    try {
      return jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }


  /// Fires ~5 seconds out so you can confirm the channel works end to end.
  Future<void> sendTestNotification() async {
    await init();
    await _plugin.zonedSchedule(
      999999,
      'Test reminder',
      'If you can see this, deadline reminders will work.',
      tz.TZDateTime.now(tz.local).add(const Duration(seconds: 5)),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}

class _Reminder {
  _Reminder(this.position, this.leadDays, this.fireAt);

  final Position position;
  final int leadDays;
  final tz.TZDateTime fireAt;

  /// Deterministic, collision-resistant 31-bit ID derived from the document ID
  /// and the lead time, so rescheduling the same reminder reuses the same slot.
  int get notificationId {
    final key = '${position.id}#$leadDays';
    var hash = 0;
    for (final code in key.codeUnits) {
      hash = (hash * 31 + code) & 0x3FFFFFFF;
    }
    return hash;
  }

  String get title => leadDays == 0
      ? 'Deadline today: ${position.university}'
      : 'Deadline in $leadDays day${leadDays == 1 ? '' : 's'}: '
          '${position.university}';

  String get body {
    final what = position.programme.isEmpty ? 'Application' : position.programme;
    return leadDays == 0
        ? '$what closes today. You have not marked it as applied yet.'
        : '$what closes in $leadDays day${leadDays == 1 ? '' : 's'}. '
            'Still marked as not applied.';
  }
}
