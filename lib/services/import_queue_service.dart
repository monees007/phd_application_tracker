import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/position.dart';
import 'firestore_service.dart';
import 'gemini_service.dart';
import 'notification_service.dart';
import 'page_fetcher.dart';
import 'settings_service.dart';
import 'share_service.dart';

enum ImportStatus { running, success, failed }

/// One share, from arrival to a result you can act on.
///
/// Persisted rather than held in memory: the notification that announces the
/// result may be tapped minutes later, possibly after the process has been
/// killed, and the extraction should not have to be paid for twice.
class PendingImport {
  final String id;
  final String? url;
  final String? sharedText;
  final DateTime createdAt;
  final ImportStatus status;
  final String? error;

  /// Hint shown alongside a failure, e.g. that the page was JavaScript-rendered.
  final String? hint;

  final Map<String, dynamic>? extracted;

  /// Set when the result was confident enough to save without review. Null
  /// means the extraction is waiting for you to look at it.
  final String? savedPositionId;

  const PendingImport({
    required this.id,
    required this.createdAt,
    required this.status,
    this.url,
    this.sharedText,
    this.error,
    this.hint,
    this.extracted,
    this.savedPositionId,
  });

  ExtractedPosition? get result =>
      extracted == null ? null : ExtractedPosition.fromJson(extracted!);

  bool get wasAutoSaved => savedPositionId != null;

  PendingImport copyWith({
    String? sharedText,
    ImportStatus? status,
    String? error,
    String? hint,
    Map<String, dynamic>? extracted,
    String? savedPositionId,
    bool clearSavedPositionId = false,
  }) =>
      PendingImport(
        id: id,
        url: url,
        sharedText: sharedText ?? this.sharedText,
        createdAt: createdAt,
        status: status ?? this.status,
        error: error ?? this.error,
        hint: hint ?? this.hint,
        extracted: extracted ?? this.extracted,
        savedPositionId: clearSavedPositionId
            ? null
            : (savedPositionId ?? this.savedPositionId),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'sharedText': sharedText,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'error': error,
    'hint': hint,
    'extracted': extracted,
    'savedPositionId': savedPositionId,
  };

  factory PendingImport.fromJson(Map<String, dynamic> j) => PendingImport(
    id: j['id'] as String,
    url: j['url'] as String?,
    sharedText: j['sharedText'] as String?,
    createdAt:
    DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    status: ImportStatus.values.firstWhere(
          (s) => s.name == j['status'],
      orElse: () => ImportStatus.failed,
    ),
    error: j['error'] as String?,
    hint: j['hint'] as String?,
    extracted: (j['extracted'] as Map?)?.cast<String, dynamic>(),
    savedPositionId: j['savedPositionId'] as String?,
  );
}

/// Runs share imports without blocking the UI and reports the outcome through
/// a notification.
///
/// Scope, stated plainly: this runs inside the app's own isolate. A share
/// opens the app, so the work starts with the process alive and normally
/// finishes in a few seconds. If you swipe the app away immediately after
/// sharing, Android may kill the process before the API call returns and the
/// import is lost — the record stays in `running` and is swept on next launch.
class ImportQueueService {
  ImportQueueService._();
  static final ImportQueueService instance = ImportQueueService._();

  static const _indexKey = 'import_index';
  static const _prefix = 'import:';

  final _settings = SettingsService();

  /// Firestore access, resolved per call from the signed-in user.
  ///
  /// Previously the controller had to lend this via attachStore(), which meant
  /// auto-save silently did nothing whenever no widget had yet read the
  /// provider. The uid is available from FirebaseAuth anywhere in the app, so
  /// there is no reason to route it through the widget tree.
  FirestoreService? get _store {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : FirestoreService(uid);
  }

  /// Fires whenever an import finishes, so an open review screen can refresh
  /// itself instead of polling.
  final ValueNotifier<PendingImport?> lastCompleted =
  ValueNotifier<PendingImport?>(null);

  // ---- persistence ---------------------------------------------------------

  Future<PendingImport?> load(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$id');
    if (raw == null) return null;
    try {
      return PendingImport.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(PendingImport p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix${p.id}', jsonEncode(p.toJson()));

    final index = prefs.getStringList(_indexKey) ?? <String>[];
    if (!index.contains(p.id)) {
      index.add(p.id);
      // Keep the last 20; each record can hold a few KB of shared text.
      while (index.length > 20) {
        final dropped = index.removeAt(0);
        await prefs.remove('$_prefix$dropped');
      }
      await prefs.setStringList(_indexKey, index);
    }
  }

  Future<void> discard(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$id');
    final index = prefs.getStringList(_indexKey) ?? <String>[];
    index.remove(id);
    await prefs.setStringList(_indexKey, index);
  }

  /// Deletes an auto-added position and clears the flag, so the record falls
  /// back to being a reviewable extraction rather than vanishing.
  Future<void> undoAutoSave(String importId) async {
    final p = await load(importId);
    final positionId = p?.savedPositionId;
    if (p == null || positionId == null) return;

    try {
      await _store?.delete(positionId);
    } catch (e) {
      debugPrint('ImportQueueService: undo failed: $e');
      return;
    }
    final updated = p.copyWith(clearSavedPositionId: true);
    await _save(updated);
    lastCompleted.value = updated;
  }

  /// Marks any import still flagged `running` as failed. Called at startup,
  /// because a `running` record at that point means the process died mid-flight.
  Future<void> sweepInterrupted() async {
    final prefs = await SharedPreferences.getInstance();
    for (final id in prefs.getStringList(_indexKey) ?? <String>[]) {
      final p = await load(id);
      if (p != null && p.status == ImportStatus.running) {
        await _save(p.copyWith(
          status: ImportStatus.failed,
          error: 'The app closed before this import finished.',
        ));
      }
    }
  }

  // ---- running -------------------------------------------------------------

  /// Starts an import and returns immediately with its id.
  Future<String> enqueue(SharedPayload payload) async {
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

    final record = PendingImport(
      id: id,
      url: payload.url?.toString(),
      sharedText: payload.content,
      createdAt: DateTime.now(),
      status: ImportStatus.running,
    );
    await _save(record);

    // Fire and forget. Errors are captured into the record, never thrown here.
    unawaited(_run(record));
    return id;
  }

  /// Re-runs an existing record, used by the "try again" action.
  Future<void> retry(String id) async {
    final p = await load(id);
    if (p == null) return;
    await _save(p.copyWith(status: ImportStatus.running));
    unawaited(_run(p));
  }

  /// Runs extraction against text the user pasted in by hand. Never auto-saves:
  /// if you are already in the review screen, you want to see the result.
  Future<PendingImport?> runWithText(String id, String text) async {
    final p = await load(id);
    if (p == null) return null;
    final updated = PendingImport(
      id: p.id,
      url: p.url,
      sharedText: text,
      createdAt: p.createdAt,
      status: ImportStatus.running,
    );
    await _save(updated);
    await _run(updated, notify: false, allowAutoSave: false, saveNote: false);
    return load(id);
  }

  Future<void> _run(
      PendingImport originalRecord, {
        bool notify = true,
    bool allowAutoSave = true,
    bool saveNote = true,
  }) async {
    var record = originalRecord;
    if (notify) await NotificationService.instance.showImportProgress(record);
    final fetcher = PageFetcher();
    final gemini = GeminiService();

    try {
      final apiKey = await _settings.geminiApiKey();
      if (apiKey.trim().isEmpty) {
        await _finish(
          record.copyWith(
            status: ImportStatus.failed,
            error: 'No Gemini API key saved.',
            hint: 'Settings → AI extraction → add your key, then share again.',
          ),
          notify: notify,
          saveNoteOnFailure: saveNote,
        );
        return;
      }

      // Text the user shared directly wins over fetching: they already have
      // the content, and it is the only thing that works for adverts a plain
      // GET cannot see.
      String text;
      if (record.sharedText != null && record.sharedText!.trim().length >= 80) {
        text = record.sharedText!;
      } else if (record.url != null) {
        final page = await fetcher.fetch(Uri.parse(record.url!));
        if (page.looksEmpty) {
          await _finish(
            record.copyWith(
              status: ImportStatus.failed,
              error: 'That page had almost no readable text.',
              hint: 'It is rendered with JavaScript after loading, which a '
                  'plain fetch cannot see. Open the link, select the advert '
                  'text, and share that instead.',
            ),
            notify: notify,
            saveNoteOnFailure: saveNote,
          );
          return;
        }
        text = page.text;
        // Keep what was fetched: the record is the only place a link import
        // can preserve the advert, and the notes are built from it.
        record = record.copyWith(sharedText: text);
      } else {
        await _finish(
          record.copyWith(
            status: ImportStatus.failed,
            error: 'Nothing usable was shared.',
          ),
          notify: notify,
          saveNoteOnFailure: saveNote,
        );
        return;
      }

      final extracted = await gemini.extract(
        pageText: text,
        sourceUrl: record.url ?? 'shared text',
        apiKey: apiKey,
        model: await _settings.geminiModel(),
      );

      var done = record.copyWith(
        status: ImportStatus.success,
        extracted: extracted.toJson(),
      );

      if (allowAutoSave) {
        final positionId = await _autoSave(done, extracted,
            confident: _isConfident(extracted));
        if (positionId != null) {
          done = done.copyWith(savedPositionId: positionId);
        }
      }

      await _finish(done, notify: notify, saveNoteOnFailure: saveNote);
    } on PageFetchException catch (e) {
      await _finish(
        record.copyWith(
          status: ImportStatus.failed,
          error: e.message,
          hint: 'You can share the advert text instead of the link.',
        ),
        notify: notify,
        saveNoteOnFailure: saveNote,
      );
    } on GeminiException catch (e) {
      await _finish(
        record.copyWith(status: ImportStatus.failed, error: e.message),
        notify: notify,
        saveNoteOnFailure: saveNote,
      );
    } catch (e) {
      await _finish(
        record.copyWith(status: ImportStatus.failed, error: e.toString()),
        notify: notify,
        saveNoteOnFailure: saveNote,
      );
    } finally {
      fetcher.dispose();
      gemini.dispose();
    }
  }

  /// Only skip review when the model says it was sure and actually named an
  /// institution. A `low` confidence result is the model reporting that it was
  /// guessing — exactly the case worth a human glance.
  ///
  /// To be stricter, add `&& e.deadline != null` here: an entry with no
  /// deadline gets no reminders, which is arguably worth confirming by hand.
  /// Confident enough to present as a finished entry rather than one tagged
  /// for follow-up. Either way it is saved — this only changes the tag, the
  /// notes and the notification wording.
  bool _isConfident(ExtractedPosition e) =>
      e.confidence != 'low' && (e.university ?? '').trim().isNotEmpty;

  /// Tag applied to anything saved without a confident extraction, so the
  /// incomplete entries are findable in one search instead of hiding among
  /// good ones. A tag rather than a new model field: tags already flow
  /// through search, the card chips and the CSV export.
  static const needsDetailsTag = 'needs-details';

  Future<String?> _autoSave(
    PendingImport record,
    ExtractedPosition e, {
    required bool confident,
  }) async {
    final now = DateTime.now();
    final deadline = e.deadline == null ? null : DateTime.tryParse(e.deadline!);

    final university = (e.university ?? '').trim().isNotEmpty
        ? e.university!.trim()
        : _fallbackTitle(record);

    final position = Position(
      id: 'pending',
      university: university,
      programme: e.programme?.trim() ?? '',
      deadline: deadline,
      // An inferred year stays flagged after saving, so the date shows the
      // same "verify me" marker as the CSV-imported rows.
      deadlineYearAssumed: deadline != null && !e.deadlineYearExplicit,
      funded: e.funded,
      applicationFee: e.applicationFee,
      feeCurrency: e.feeCurrency,
      link: record.url ?? '',
      country: e.country,
      tags: [...e.tags, if (!confident) needsDetailsTag],
      // Always starts as not-applied, so it joins the reminder schedule.
      status: AppStatus.notApplied,
      notes: [
        if (e.summary != null) e.summary!,
        if (!confident)
          'The model was not confident about this source, so check every '
              'field. The original text is kept below.',
        'Added automatically from a share on '
            '${now.toIso8601String().substring(0, 10)}.',
        if (e.notFound.isNotEmpty)
          'Not stated in the source: ${e.notFound.join(', ')}.',
        _sourceBlock(record),
      ].join('\n\n'),
      createdAt: now,
      updatedAt: now,
      history: [StatusChange(status: AppStatus.notApplied, at: now)],
    );

    return _write(position);
  }

  /// Saves the raw share when extraction never produced anything usable —
  /// because Gemini errored, the key is missing, or the page was a shell.
  ///
  /// Losing a shared advert is worse than holding an untidy one: the entry
  /// lands on the board tagged [needsDetailsTag] with the original text in
  /// its notes, ready for the manual re-extract in the edit screen.
  Future<String?> _saveAsNote(PendingImport record) async {
    final now = DateTime.now();

    return _write(Position(
      id: 'pending',
      university: _fallbackTitle(record),
      programme: '',
      link: record.url ?? '',
      status: AppStatus.notApplied,
      tags: const [needsDetailsTag],
      notes: [
        'Saved without extraction on '
            '${now.toIso8601String().substring(0, 10)}.',
        if (record.error != null) 'Reason: ${record.error}',
        'Open this entry, tap "Extract from text" and retry, or fill the '
            'fields in by hand.',
        _sourceBlock(record),
      ].join('\n\n'),
      createdAt: now,
      updatedAt: now,
      history: [StatusChange(status: AppStatus.notApplied, at: now)],
    ));
  }

  Future<String?> _write(Position position) async {
    final store = _store;
    if (store == null) {
      debugPrint('ImportQueueService: nobody signed in, keeping for review.');
      return null;
    }
    try {
      return await store.add(position);
    } catch (e) {
      // A write failure must not lose the extraction — fall back to review.
      debugPrint('ImportQueueService: save failed: $e');
      return null;
    }
  }

  /// A usable name when the model gave none: the site it came from beats
  /// "Untitled" for finding it again later.
  String _fallbackTitle(PendingImport record) {
    final url = record.url;
    if (url != null) {
      final host = Uri.tryParse(url)?.host.replaceFirst('www.', '');
      if (host != null && host.isNotEmpty) return host;
    }
    return 'Shared advert';
  }

  /// The original share, trimmed. Kept verbatim so a later re-extract has
  /// something to work from without refetching.
  String _sourceBlock(PendingImport record) {
    final text = record.sharedText?.trim();
    if (text == null || text.isEmpty) {
      return record.url == null ? '' : 'Source: ${record.url}';
    }
    // The whole advert is kept so the entry is self-contained: the source
    // page can be taken down, and a later re-extract needs no refetch.
    //
    // Budget: a Firestore document is capped at 1 MiB, so this is nowhere
    // near the hard limit. The real cost is that the app streams every
    // position on launch — at 20 kB each, a hundred positions is ~2 MB per
    // cold start. That is fine at this scale and would not be at ten times
    // it; see the note in CHANGES-ADVERT.md for the subcollection version.
    const limit = 20000;
    final clipped =
        text.length > limit ? '${text.substring(0, limit)}…' : text;
    return '--- shared text ---\n$clipped';
  }

  Future<void> _finish(
    PendingImport p, {
    required bool notify,
    bool saveNoteOnFailure = true,
  }) async {
    await NotificationService.instance.cancelImportProgress(p.id);

    var record = p;

    // A share that produced nothing usable is still worth keeping. Saving it
    // as a note means the link is never lost to a transient 503 or a page the
    // fetcher could not read.
    if (saveNoteOnFailure &&
        record.status == ImportStatus.failed &&
        !record.wasAutoSaved) {
      final id = await _saveAsNote(record);
      if (id != null) record = record.copyWith(savedPositionId: id);
    }

    await _save(record);
    lastCompleted.value = record;
    if (notify) {
      await NotificationService.instance.showImportResult(record);
    }
  }
}

/// Local stand-in so this file does not depend on package:async.
void unawaited(Future<void> future) {
  future.catchError((Object e) {
    debugPrint('ImportQueueService: unhandled $e');
  });
}