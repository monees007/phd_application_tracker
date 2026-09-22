import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/position.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../services/widget_bridge.dart';

enum SortBy { deadlineAsc, deadlineDesc, university, programme, recentlyUpdated }

extension SortByLabel on SortBy {
  String get label => switch (this) {
        SortBy.deadlineAsc => 'Deadline (soonest first)',
        SortBy.deadlineDesc => 'Deadline (latest first)',
        SortBy.university => 'University (A–Z)',
        SortBy.programme => 'Programme (A–Z)',
        SortBy.recentlyUpdated => 'Recently updated',
      };
}

/// Which of the three boards the user is looking at.
enum Bucket { toApply, pending, decided, all }

extension BucketLabel on Bucket {
  String get label => switch (this) {
        Bucket.toApply => 'To apply',
        Bucket.pending => 'Pending',
        Bucket.decided => 'Decided',
        Bucket.all => 'All',
      };

  bool matches(Position p) => switch (this) {
        Bucket.toApply => p.status.needsAction,
        Bucket.pending => p.status.isPending,
        Bucket.decided => p.status.isDecided,
        Bucket.all => true,
      };
}

class PositionsController extends ChangeNotifier {
  PositionsController(this.service) {
    _sub = service.watchPositions().listen(
      (items) {
        _all = items;
        _loading = false;
        _error = null;
        notifyListeners();
        _scheduleReminderSync();
        debugPrint('CONTROLLER: got ${items.length} positions');
        WidgetBridge.instance.push(items);
      },

      onError: (Object e) {
        _loading = false;
        _error = e.toString();
        notifyListeners();
      },
    );
    // A stream that never emits should not look like a hung app. Firestore
    // normally delivers a first snapshot — empty or not — within a second or
    // two, including from cache while offline.
    Timer(const Duration(seconds: 8), () {
      if (_loading) {
        _loading = false;
        _error = 'No response from Firestore. Check that the security rules '
            'are deployed and that this device has network access.';
        notifyListeners();
      }
    });
    _loadSettings();
  }

  final FirestoreService service;
  StreamSubscription<List<Position>>? _sub;
  Timer? _debounce;

  final SettingsService _settingsService = SettingsService();
  ReminderSettings _reminders = const ReminderSettings();
  ReminderSettings get reminders => _reminders;

  List<Position> _all = const [];
  bool _loading = true;
  String? _error;

  bool get loading => _loading;
  String? get error => _error;
  List<Position> get all => _all;

  // ---- filters -------------------------------------------------------------
  String _query = '';
  bool _hidePastDeadlines = false;
  bool _showArchived = false;
  bool _fundedOnly = false;
  String? _universityFilter;
  SortBy _sortBy = SortBy.deadlineAsc;

  String get query => _query;
  bool get hidePastDeadlines => _hidePastDeadlines;
  bool get showArchived => _showArchived;
  bool get fundedOnly => _fundedOnly;
  String? get universityFilter => _universityFilter;
  SortBy get sortBy => _sortBy;

  bool get hasActiveFilters =>
      _hidePastDeadlines || _fundedOnly || _universityFilter != null || _showArchived;

  void setQuery(String v) {
    _query = v;
    notifyListeners();
  }

  void setHidePast(bool v) {
    _hidePastDeadlines = v;
    notifyListeners();
  }

  void setShowArchived(bool v) {
    _showArchived = v;
    notifyListeners();
  }

  void setFundedOnly(bool v) {
    _fundedOnly = v;
    notifyListeners();
  }

  void setUniversityFilter(String? v) {
    _universityFilter = v;
    notifyListeners();
  }

  void setSortBy(SortBy v) {
    _sortBy = v;
    notifyListeners();
  }

  void clearFilters() {
    _hidePastDeadlines = false;
    _showArchived = false;
    _fundedOnly = false;
    _universityFilter = null;
    notifyListeners();
  }

  List<String> get universities {
    final set = _all.map((p) => p.university).where((u) => u.isNotEmpty).toSet();
    final list = set.toList()..sort();
    return list;
  }

  List<Position> visible(Bucket bucket) {
    final q = _query.trim().toLowerCase();

    final items = _all.where((p) {
      if (!_showArchived && p.archived) return false;
      if (!bucket.matches(p)) return false;
      if (_fundedOnly && p.funded != true) return false;
      if (_universityFilter != null && p.university != _universityFilter) {
        return false;
      }
      if (_hidePastDeadlines && p.isOverdue) return false;
      if (q.isNotEmpty) {
        final blob =
            '${p.university} ${p.programme} ${p.notes} ${p.tags.join(' ')}'
                .toLowerCase();
        if (!blob.contains(q)) return false;
      }
      return true;
    }).toList();

    items.sort(_comparator);
    return items;
  }

  int Function(Position, Position) get _comparator => switch (_sortBy) {
        SortBy.deadlineAsc => (a, b) => _nullableDate(a.deadline, b.deadline, 1),
        SortBy.deadlineDesc => (a, b) => _nullableDate(b.deadline, a.deadline, 1),
        SortBy.university => (a, b) => a.university
            .toLowerCase()
            .compareTo(b.university.toLowerCase()),
        SortBy.programme => (a, b) =>
            a.programme.toLowerCase().compareTo(b.programme.toLowerCase()),
        SortBy.recentlyUpdated => (a, b) => b.updatedAt.compareTo(a.updatedAt),
      };

  /// Entries with no deadline always sink to the bottom rather than sorting
  /// as if they were at the epoch.
  int _nullableDate(DateTime? a, DateTime? b, int dir) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b) * dir;
  }

  // ---- stats ---------------------------------------------------------------
  Map<AppStatus, int> get statusCounts {
    final m = {for (final s in AppStatus.values) s: 0};
    for (final p in _all.where((p) => !p.archived)) {
      m[p.status] = (m[p.status] ?? 0) + 1;
    }
    return m;
  }

  List<Position> upcoming({int withinDays = 14}) {
    final list = _all
        .where((p) =>
            !p.archived &&
            p.status.needsAction &&
            p.daysLeft != null &&
            p.daysLeft! >= 0 &&
            p.daysLeft! <= withinDays)
        .toList()
      ..sort((a, b) => a.deadline!.compareTo(b.deadline!));
    return list;
  }

  /// Open positions whose deadline has already passed and that were never
  /// submitted — the ones most likely to need cleaning up.
  List<Position> get missed => _all
      .where((p) => !p.archived && p.status.needsAction && p.isOverdue)
      .toList();

  // ---- mutations -----------------------------------------------------------
  Future<void> changeStatus(Position p, AppStatus next, {String? note}) async {
    await service.changeStatus(p, next, note: note);
  }

  Future<void> save(Position p) => service.update(p);

  Future<String> create(Position p) => service.add(p);

  Future<void> delete(String id) => service.delete(id);

  Future<void> setArchived(String id, bool archived) =>
      service.setArchived(id, archived);

  // ---- reminders -----------------------------------------------------------
  Future<void> _loadSettings() async {
    _reminders = await _settingsService.load();
    notifyListeners();
    _scheduleReminderSync();
  }

  Future<void> updateReminderSettings(ReminderSettings s) async {
    _reminders = s;
    await _settingsService.save(s);
    notifyListeners();
    await NotificationService.instance.rescheduleAll(_all, s);
  }

  /// Firestore streams can fire several times in quick succession (local echo
  /// then server ack), so coalesce before touching the alarm manager.
  void _scheduleReminderSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1200), () {
      NotificationService.instance.rescheduleAll(_all, _reminders);
    });
  }

  Future<void> forceRescheduleReminders() =>
      NotificationService.instance.rescheduleAll(_all, _reminders);

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
