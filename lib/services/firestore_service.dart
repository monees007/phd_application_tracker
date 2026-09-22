import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/position.dart';

/// All reads and writes live under `users/{uid}/positions/{id}`.
/// That keeps the security rules trivial (owner-only) and means a second
/// device signed into the same account sees the same board.
class FirestoreService {
  FirestoreService(this.uid);

  final String uid;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('users').doc(uid).collection('positions');

  DocumentReference<Map<String, dynamic>> get _userDoc =>
      _db.collection('users').doc(uid);

  Stream<List<Position>> watchPositions() {
    // No orderBy here: sorting happens client-side so the user can reorder
    // without needing a new composite index for every combination.
    return _col.snapshots().map(
          (snap) => snap.docs.map(Position.fromFirestore).toList(),
        );
  }

  Future<String> add(Position p) async {
    final ref = await _col.add(p.toMap());
    return ref.id;
  }

  /// Used by the seed importer so IDs stay stable and re-import is idempotent.
  Future<void> setWithId(Position p) => _col.doc(p.id).set(p.toMap());

  Future<void> update(Position p) =>
      _col.doc(p.id).set(p.toMap(), SetOptions(merge: true));

  Future<void> delete(String id) => _col.doc(id).delete();

  Future<void> setArchived(String id, bool archived) => _col.doc(id).update({
        'archived': archived,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

  /// Changes status and stamps the matching date field, appending to history.
  Future<Position> changeStatus(Position p, AppStatus next, {String? note}) async {
    if (p.status == next && note == null) return p;
    final now = DateTime.now();

    final updated = p.copyWith(
      status: next,
      updatedAt: now,
      appliedAt: next == AppStatus.applied && p.appliedAt == null ? now : null,
      clearAppliedAt: next == AppStatus.notApplied,
      resultAt: next.isDecided ? now : null,
      clearResultAt: !next.isDecided,
      history: [...p.history, StatusChange(status: next, at: now, note: note)],
    );

    await update(updated);
    return updated;
  }

  /// Writes many documents in batches of 400 (Firestore's limit is 500 ops).
  Future<void> bulkSet(List<Position> items) async {
    const chunk = 400;
    for (var i = 0; i < items.length; i += chunk) {
      final batch = _db.batch();
      for (final p in items.skip(i).take(chunk)) {
        batch.set(_col.doc(p.id), p.toMap(), SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  Future<bool> hasAnyPosition() async {
    final snap = await _col.limit(1).get();
    return snap.docs.isNotEmpty;
  }

  Future<bool> seedAlreadyImported() async {
    final doc = await _userDoc.get();
    return (doc.data()?['seedImported'] as bool?) ?? false;
  }

  Future<void> markSeedImported() => _userDoc.set(
        {'seedImported': true, 'seedImportedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
}
