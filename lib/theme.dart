import 'package:flutter/material.dart';

import 'models/position.dart';

const _seed = Color(0xFF4C5FD5);

/// Note on API choices: `ThemeData.cardTheme` and `tabBarTheme` changed type
/// (`CardTheme` -> `CardThemeData`) in recent Flutter releases, so this theme
/// deliberately sets neither. Card styling lives in `appCardShape()` below and
/// is applied per-widget, which compiles on every 3.x that supports
/// `Color.withValues` (Flutter >= 3.27).
ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: scheme.surfaceTint,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 3,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: const DividerThemeData(space: 1, thickness: 1),
  );
}

OutlinedBorder appCardShape(BuildContext context) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    );

/// Background/foreground pairs for each status, derived from the active
/// scheme so both light and dark themes stay legible.
({Color bg, Color fg}) statusColors(BuildContext context, AppStatus status) {
  final s = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;

  Color mix(Color base) =>
      dark ? Color.alphaBlend(base.withValues(alpha: 0.24), s.surface) : base;

  return switch (status) {
    AppStatus.notApplied => (
        bg: mix(const Color(0xFFE8EAF6)),
        fg: dark ? const Color(0xFFB9C1FF) : const Color(0xFF32409A),
      ),
    AppStatus.applied => (
        bg: mix(const Color(0xFFE1F0FB)),
        fg: dark ? const Color(0xFF8FCBF3) : const Color(0xFF14567E),
      ),
    AppStatus.interview => (
        bg: mix(const Color(0xFFFFF0D6)),
        fg: dark ? const Color(0xFFF2C77A) : const Color(0xFF8A5A00),
      ),
    AppStatus.accepted => (
        bg: mix(const Color(0xFFDDF3E1)),
        fg: dark ? const Color(0xFF8FD6A0) : const Color(0xFF1B6B33),
      ),
    AppStatus.rejected => (
        bg: mix(const Color(0xFFFBE0E0)),
        fg: dark ? const Color(0xFFF2A8A8) : const Color(0xFF9A2B2B),
      ),
    AppStatus.withdrawn => (
        bg: mix(const Color(0xFFEDEDED)),
        fg: dark ? const Color(0xFFBDBDBD) : const Color(0xFF5A5A5A),
      ),
  };
}

/// Colour for the deadline pill: red once overdue, red-tinted inside three
/// days, tertiary inside a week, neutral otherwise.
({Color bg, Color fg}) deadlineColors(BuildContext context, int? daysLeft) {
  final s = Theme.of(context).colorScheme;
  if (daysLeft == null) {
    return (bg: s.surfaceContainerHighest, fg: s.onSurfaceVariant);
  }
  if (daysLeft < 0) return (bg: s.errorContainer, fg: s.onErrorContainer);
  if (daysLeft <= 3) {
    return (bg: s.error.withValues(alpha: 0.14), fg: s.error);
  }
  if (daysLeft <= 7) {
    return (bg: s.tertiaryContainer, fg: s.onTertiaryContainer);
  }
  return (bg: s.surfaceContainerHighest, fg: s.onSurfaceVariant);
}
