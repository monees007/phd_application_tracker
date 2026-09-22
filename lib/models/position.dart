import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// The four states you asked for, plus two that fall naturally out of a real
/// application pipeline. The core four are always shown first in pickers.
enum AppStatus {
  notApplied,
  applied,
  interview,
  accepted,
  rejected,
  withdrawn;

  static AppStatus fromName(String? raw) {
    if (raw == null) return AppStatus.notApplied;
    return AppStatus.values.firstWhere(
      (s) => s.name.toLowerCase() == raw.toLowerCase(),
      orElse: () => AppStatus.notApplied,
    );
  }

  String get label => switch (this) {
        AppStatus.notApplied => 'Not applied',
        AppStatus.applied => 'Applied',
        AppStatus.interview => 'Interview',
        AppStatus.accepted => 'Accepted',
        AppStatus.rejected => 'Rejected',
        AppStatus.withdrawn => 'Withdrawn',
      };

  IconData get icon => switch (this) {
        AppStatus.notApplied => Icons.edit_note_outlined,
        AppStatus.applied => Icons.send_outlined,
        AppStatus.interview => Icons.record_voice_over_outlined,
        AppStatus.accepted => Icons.check_circle_outline,
        AppStatus.rejected => Icons.cancel_outlined,
        AppStatus.withdrawn => Icons.remove_circle_outline,
      };

  /// Still needs an application submitted -> deserves deadline reminders.
  bool get needsAction => this == AppStatus.notApplied;

  /// Submitted, no final answer yet.
  bool get isPending => this == AppStatus.applied || this == AppStatus.interview;

  /// Answer is in (or you pulled out).
  bool get isDecided =>
      this == AppStatus.accepted ||
      this == AppStatus.rejected ||
      this == AppStatus.withdrawn;
}

/// One entry in the audit trail of status changes.
class StatusChange {
  final AppStatus status;
  final DateTime at;
  final String? note;

  const StatusChange({required this.status, required this.at, this.note});

  factory StatusChange.fromMap(Map<String, dynamic> m) => StatusChange(
        status: AppStatus.fromName(m['status'] as String?),
        at: _toDate(m['at']) ?? DateTime.now(),
        note: m['note'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'status': status.name,
        'at': Timestamp.fromDate(at),
        if (note != null && note!.isNotEmpty) 'note': note,
      };
}

DateTime? _toDate(Object? v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

class Position {
  final String id;
  final String university;
  final String programme;

  /// Stored as a date only (local midnight). Null = no published deadline.
  final DateTime? deadline;

  /// True when the deadline's *year* was inferred during CSV import rather
  /// than being present in the source sheet. Surfaced in the UI so you know
  /// which dates to double-check.
  final bool deadlineYearAssumed;

  final bool? funded;
  final double? applicationFee;
  final String? feeCurrency;
  final String link;
  final AppStatus status;
  final String notes;
  final List<String> tags;
  final String? country;

  final DateTime? appliedAt;
  final DateTime? resultAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  final bool archived;
  final bool reminderEnabled;
  final List<StatusChange> history;

  const Position({
    required this.id,
    required this.university,
    required this.programme,
    required this.createdAt,
    required this.updatedAt,
    this.deadline,
    this.deadlineYearAssumed = false,
    this.funded,
    this.applicationFee,
    this.feeCurrency,
    this.link = '',
    this.status = AppStatus.notApplied,
    this.notes = '',
    this.tags = const [],
    this.country,
    this.appliedAt,
    this.resultAt,
    this.archived = false,
    this.reminderEnabled = true,
    this.history = const [],
  });

  factory Position.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return Position(
      id: doc.id,
      university: (d['university'] as String?)?.trim() ?? '',
      programme: (d['programme'] as String?)?.trim() ?? '',
      deadline: _toDate(d['deadline']),
      deadlineYearAssumed: d['deadlineYearAssumed'] as bool? ?? false,
      funded: d['funded'] as bool?,
      applicationFee: (d['applicationFee'] as num?)?.toDouble(),
      feeCurrency: d['feeCurrency'] as String?,
      link: d['link'] as String? ?? '',
      status: AppStatus.fromName(d['status'] as String?),
      notes: d['notes'] as String? ?? '',
      tags: (d['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      country: d['country'] as String?,
      appliedAt: _toDate(d['appliedAt']),
      resultAt: _toDate(d['resultAt']),
      createdAt: _toDate(d['createdAt']) ?? DateTime.now(),
      updatedAt: _toDate(d['updatedAt']) ?? DateTime.now(),
      archived: d['archived'] as bool? ?? false,
      reminderEnabled: d['reminderEnabled'] as bool? ?? true,
      history: (d['history'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(StatusChange.fromMap)
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toMap() => {
        'university': university,
        'programme': programme,
        'deadline': deadline == null ? null : Timestamp.fromDate(deadline!),
        'deadlineYearAssumed': deadlineYearAssumed,
        'funded': funded,
        'applicationFee': applicationFee,
        'feeCurrency': feeCurrency,
        'link': link,
        'status': status.name,
        'notes': notes,
        'tags': tags,
        'country': country,
        'appliedAt': appliedAt == null ? null : Timestamp.fromDate(appliedAt!),
        'resultAt': resultAt == null ? null : Timestamp.fromDate(resultAt!),
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
        'archived': archived,
        'reminderEnabled': reminderEnabled,
        // Keep the trail bounded so a document can never approach the 1 MiB cap.
        'history': history.length <= 50
            ? history.map((h) => h.toMap()).toList()
            : history.sublist(history.length - 50).map((h) => h.toMap()).toList(),
        // Lower-cased blob for cheap server-side search. Notes are
        // deliberately excluded: they now hold the full advert, which would
        // roughly double every document for a field the app does not read —
        // client-side filtering builds its own blob from the live object.
        'searchIndex':
            '$university $programme ${tags.join(' ')}'.toLowerCase(),
      };

  Position copyWith({
    String? university,
    String? programme,
    DateTime? deadline,
    bool clearDeadline = false,
    bool? deadlineYearAssumed,
    bool? funded,
    bool clearFunded = false,
    double? applicationFee,
    bool clearFee = false,
    String? feeCurrency,
    String? link,
    AppStatus? status,
    String? notes,
    List<String>? tags,
    String? country,
    DateTime? appliedAt,
    bool clearAppliedAt = false,
    DateTime? resultAt,
    bool clearResultAt = false,
    DateTime? updatedAt,
    bool? archived,
    bool? reminderEnabled,
    List<StatusChange>? history,
  }) {
    return Position(
      id: id,
      university: university ?? this.university,
      programme: programme ?? this.programme,
      deadline: clearDeadline ? null : (deadline ?? this.deadline),
      deadlineYearAssumed: deadlineYearAssumed ?? this.deadlineYearAssumed,
      funded: clearFunded ? null : (funded ?? this.funded),
      applicationFee: clearFee ? null : (applicationFee ?? this.applicationFee),
      feeCurrency: feeCurrency ?? this.feeCurrency,
      link: link ?? this.link,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      country: country ?? this.country,
      appliedAt: clearAppliedAt ? null : (appliedAt ?? this.appliedAt),
      resultAt: clearResultAt ? null : (resultAt ?? this.resultAt),
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      archived: archived ?? this.archived,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      history: history ?? this.history,
    );
  }

  String get title =>
      programme.isEmpty ? university : '$programme — $university';

  /// Whole days from today (local) until the deadline. Negative = past.
  int? get daysLeft {
    if (deadline == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(deadline!.year, deadline!.month, deadline!.day);
    return d.difference(today).inDays;
  }

  bool get isOverdue {
    final d = daysLeft;
    return d != null && d < 0;
  }

  /// Open, unsubmitted and the clock is running out.
  bool get isUrgent {
    final d = daysLeft;
    return status.needsAction && d != null && d >= 0 && d <= 7;
  }
}
