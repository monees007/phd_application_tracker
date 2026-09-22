import 'package:flutter_test/flutter_test.dart';
import 'package:phd_tracker/models/position.dart';

Position make({DateTime? deadline, AppStatus status = AppStatus.notApplied}) {
  final now = DateTime.now();
  return Position(
    id: 'x',
    university: 'Test University',
    programme: 'Test Programme',
    deadline: deadline,
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}

DateTime daysFromToday(int n) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).add(Duration(days: n));
}

void main() {
  group('daysLeft', () {
    test('is zero on the deadline day regardless of clock time', () {
      expect(make(deadline: daysFromToday(0)).daysLeft, 0);
    });

    test('counts whole days ahead', () {
      expect(make(deadline: daysFromToday(3)).daysLeft, 3);
    });

    test('is negative once the deadline has passed', () {
      expect(make(deadline: daysFromToday(-2)).daysLeft, -2);
      expect(make(deadline: daysFromToday(-2)).isOverdue, isTrue);
    });

    test('is null when no deadline is set', () {
      expect(make().daysLeft, isNull);
      expect(make().isOverdue, isFalse);
    });
  });

  group('status buckets', () {
    test('only notApplied needs action, which is what gets reminders', () {
      expect(AppStatus.notApplied.needsAction, isTrue);
      for (final s in AppStatus.values.where((s) => s != AppStatus.notApplied)) {
        expect(s.needsAction, isFalse, reason: '${s.name} should not remind');
      }
    });

    test('applied and interview are pending, results are decided', () {
      expect(AppStatus.applied.isPending, isTrue);
      expect(AppStatus.interview.isPending, isTrue);
      expect(AppStatus.accepted.isDecided, isTrue);
      expect(AppStatus.rejected.isDecided, isTrue);
      expect(AppStatus.withdrawn.isDecided, isTrue);
    });

    test('every status falls into exactly one bucket', () {
      for (final s in AppStatus.values) {
        final hits = [s.needsAction, s.isPending, s.isDecided]
            .where((b) => b)
            .length;
        expect(hits, 1, reason: '${s.name} landed in $hits buckets');
      }
    });

    test('unknown names fall back to notApplied rather than throwing', () {
      expect(AppStatus.fromName('nonsense'), AppStatus.notApplied);
      expect(AppStatus.fromName(null), AppStatus.notApplied);
      expect(AppStatus.fromName('REJECTED'), AppStatus.rejected);
    });
  });

  group('isUrgent', () {
    test('true inside a week when still unsubmitted', () {
      expect(make(deadline: daysFromToday(5)).isUrgent, isTrue);
    });

    test('false once submitted', () {
      expect(
        make(deadline: daysFromToday(5), status: AppStatus.applied).isUrgent,
        isFalse,
      );
    });

    test('false once the date has passed', () {
      expect(make(deadline: daysFromToday(-1)).isUrgent, isFalse);
    });
  });
}
