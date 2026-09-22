import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How and when deadline reminders fire.
///
/// Defaults match the brief: 3 days before, and on the day itself.
@immutable
class ReminderSettings {
  final bool enabled;

  /// Days before the deadline on which to fire. `0` means the deadline day.
  final List<int> leadDays;

  /// Local time of day the reminders fire.
  final int hour;
  final int minute;

  const ReminderSettings({
    this.enabled = true,
    this.leadDays = const [3, 0],
    this.hour = 9,
    this.minute = 0,
  });

  TimeOfDay get timeOfDay => TimeOfDay(hour: hour, minute: minute);

  ReminderSettings copyWith({
    bool? enabled,
    List<int>? leadDays,
    int? hour,
    int? minute,
  }) =>
      ReminderSettings(
        enabled: enabled ?? this.enabled,
        leadDays: leadDays ?? this.leadDays,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );
}

class SettingsService {
  static const _kEnabled = 'reminders_enabled';
  static const _kLeadDays = 'reminder_lead_days';
  static const _kHour = 'reminder_hour';
  static const _kMinute = 'reminder_minute';
  static const _kGeminiKey = 'gemini_api_key';
  static const _kGeminiModel = 'gemini_model';
  static const _kSwipeActions = 'swipe_actions_enabled';

  /// Every call used to await `SharedPreferences.getInstance()` separately.
  /// It is a singleton underneath, but each call still crossed the platform
  /// channel; the list screen reads the swipe flag on every build, so this is
  /// worth holding onto.
  static SharedPreferences? _cache;

  static Future<SharedPreferences> _prefs() async =>
      _cache ??= await SharedPreferences.getInstance();

  /// Warms the cache so synchronous reads work. Call once during startup.
  static Future<void> warmUp() => _prefs();

  /// Non-null only after [warmUp] or any async read has completed. Lets the
  /// UI avoid a FutureBuilder for a single boolean.
  static SharedPreferences? get cached => _cache;

  // ---- AI extraction -------------------------------------------------------

  Future<String> geminiApiKey() async {
    // A --dart-define wins over the stored value, so a key can be injected at
    // build time without ever touching the device's preferences.
    const fromEnv = String.fromEnvironment('GEMINI_API_KEY');
    if (fromEnv.isNotEmpty) return fromEnv;
    return (await _prefs()).getString(_kGeminiKey) ?? '';
  }

  Future<void> setGeminiApiKey(String key) async =>
      (await _prefs()).setString(_kGeminiKey, key);

  Future<String> geminiModel() async =>
      (await _prefs()).getString(_kGeminiModel) ?? 'gemini-3.5-flash';

  Future<void> setGeminiModel(String model) async =>
      (await _prefs()).setString(_kGeminiModel, model);

  // ---- interaction ---------------------------------------------------------

  /// Swipe-to-act on the list. Off means the list only scrolls, which suits
  /// anyone who keeps triggering it by accident on a long board.
  Future<bool> swipeActionsEnabled() async =>
      (await _prefs()).getBool(_kSwipeActions) ?? true;

  /// Synchronous read for build methods. Defaults to enabled until the cache
  /// is warm, which matches the stored default.
  static bool swipeActionsEnabledSync() =>
      _cache?.getBool(_kSwipeActions) ?? true;

  Future<void> setSwipeActionsEnabled(bool value) async =>
      (await _prefs()).setBool(_kSwipeActions, value);

  // ---- reminders -----------------------------------------------------------

  Future<ReminderSettings> load() async {
    final prefs = await _prefs();
    final raw = prefs.getStringList(_kLeadDays);
    final leads = raw == null
        ? const [3, 0]
        : (raw.map(int.tryParse).whereType<int>().toList()
          ..sort((a, b) => b - a));

    return ReminderSettings(
      enabled: prefs.getBool(_kEnabled) ?? true,
      leadDays: leads.isEmpty ? const [0] : leads,
      hour: prefs.getInt(_kHour) ?? 9,
      minute: prefs.getInt(_kMinute) ?? 0,
    );
  }

  Future<void> save(ReminderSettings s) async {
    final prefs = await _prefs();
    await prefs.setBool(_kEnabled, s.enabled);
    await prefs.setStringList(
        _kLeadDays, s.leadDays.map((e) => e.toString()).toList());
    await prefs.setInt(_kHour, s.hour);
    await prefs.setInt(_kMinute, s.minute);
  }
}
