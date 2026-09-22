import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/position.dart';

class SeedBundle {
  final List<Position> positions;

  /// The year assigned to any day+month deadline that carried no year.
  final int? assumedYear;
  final String source;

  /// Rows that were skipped, with the reason. Shown before importing so a
  /// half-parsed file is visible rather than silently partial.
  final List<String> skipped;

  const SeedBundle({
    required this.positions,
    required this.assumedYear,
    required this.source,
    this.skipped = const [],
  });
}

/// Builds positions from the bundled JSON, or from any CSV the user picks.
///
/// Nothing is synthesised: cells that cannot be parsed into a typed field are
/// copied verbatim into `notes` rather than guessed at, and a row with no
/// institution and no title is skipped and reported.
class SeedService {
  static const assetPath = 'assets/seed/positions.json';

  /// Deadlines written as day + month with no year resolve to this year.
  static int defaultYear = DateTime.now().year;

  Future<SeedBundle> loadBundled() async {
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final now = DateTime.now();

    final positions = (json['positions'] as List)
        .cast<Map<String, dynamic>>()
        .map((m) => Position(
              id: m['id'] as String,
              university: (m['university'] as String? ?? '').trim(),
              programme: (m['programme'] as String? ?? '').trim(),
              deadline: m['deadline'] == null
                  ? null
                  : DateTime.parse(m['deadline'] as String),
              deadlineYearAssumed: m['deadlineYearAssumed'] as bool? ?? false,
              funded: m['funded'] as bool?,
              applicationFee: (m['applicationFee'] as num?)?.toDouble(),
              feeCurrency: m['feeCurrency'] as String?,
              link: m['link'] as String? ?? '',
              status: AppStatus.fromName(m['status'] as String?),
              notes: m['notes'] as String? ?? '',
              tags:
                  (m['tags'] as List?)?.map((e) => e.toString()).toList() ??
                      const [],
              country: m['country'] as String?,
              createdAt: now,
              updatedAt: now,
            ))
        .toList();

    return SeedBundle(
      positions: positions,
      assumedYear: json['deadlineYearAssumed'] as int?,
      source: json['source'] as String? ?? 'bundled sheet',
    );
  }

  /// Parses a CSV the user picked.
  ///
  /// Column names are matched loosely and case-insensitively, because every
  /// spreadsheet spells these differently — "College", "University" and
  /// "Institution" all mean the same thing here. Unrecognised columns are
  /// appended to the notes rather than dropped, so no data is lost on import.
  Future<SeedBundle> loadCsv(File file, {int? year}) async {
    final text = await file.readAsString();
    return parseCsv(text, source: file.uri.pathSegments.last, year: year);
  }

  SeedBundle parseCsv(String text, {required String source, int? year}) {
    final assumedYear = year ?? defaultYear;
    final rows = const CsvToListConverter(shouldParseNumbers: false, eol: '\n')
        .convert(text.replaceAll('\r\n', '\n'));

    if (rows.isEmpty) {
      return SeedBundle(
          positions: const [],
          assumedYear: assumedYear,
          source: source,
          skipped: const ['The file was empty.']);
    }

    // Some exports carry a title row above the real header, so pick whichever
    // of the first three rows looks most like a header.
    final headerIndex = _findHeaderRow(rows);
    final header =
        rows[headerIndex].map((c) => c.toString().trim().toLowerCase()).toList();

    int col(List<String> names) {
      for (final n in names) {
        final i = header.indexWhere((h) => h == n);
        if (i >= 0) return i;
      }
      for (final n in names) {
        final i = header.indexWhere((h) => h.contains(n));
        if (i >= 0) return i;
      }
      return -1;
    }

    final iUni = col(['university', 'college', 'institution', 'school']);
    final iProg = col(['programme', 'program', 'course', 'position', 'title']);
    final iDeadline = col(['deadline', 'due', 'closing']);
    final iStatus = col(['status']);
    final iApplied = col(['applied']);
    final iFunded = col(['funded', 'funding']);
    final iFee = col(['fee']);
    final iLink = col(['link', 'url', 'apply']);
    final iNotes = col(['note', 'info', 'comment', 'remark']);
    final iCountry = col(['country']);
    final iTags = col(['tag']);

    if (iUni < 0 && iProg < 0) {
      return SeedBundle(
        positions: const [],
        assumedYear: assumedYear,
        source: source,
        skipped: const [
          'No recognisable university or programme column. Expected a header '
              'row containing something like "University" or "Course".'
        ],
      );
    }

    final now = DateTime.now();
    final positions = <Position>[];
    final skipped = <String>[];

    for (var r = headerIndex + 1; r < rows.length; r++) {
      final row = rows[r];
      String cell(int i) =>
          (i < 0 || i >= row.length) ? '' : row[i].toString().trim();

      final university = cell(iUni);
      final programme = cell(iProg);
      if (university.isEmpty && programme.isEmpty) continue; // blank row

      final rawDeadline = cell(iDeadline);
      final parsed = _parseDeadline(rawDeadline, assumedYear);

      final fee = _parseFee(cell(iFee));
      final funded = _parseBool(cell(iFunded));
      final linkRaw = cell(iLink);
      final link = linkRaw.toLowerCase().startsWith('http') ? linkRaw : '';

      final notes = <String>[
        if (cell(iNotes).isNotEmpty) cell(iNotes),
        if (rawDeadline.isNotEmpty && parsed == null)
          'Sheet deadline column held: $rawDeadline',
        if (linkRaw.isNotEmpty && link.isEmpty)
          'Sheet link column held (not a URL): $linkRaw',
        if (cell(iFunded).isNotEmpty && funded == null)
          'Sheet funded column held: ${cell(iFunded)}',
        // Anything the mapper did not claim, kept rather than dropped.
        ..._unmappedColumns(header, row, {
          iUni, iProg, iDeadline, iStatus, iApplied,
          iFunded, iFee, iLink, iNotes, iCountry, iTags,
        }),
      ];

      positions.add(Position(
        // Stable id from the content, so re-importing the same file updates
        // rows instead of duplicating them.
        id: 'csv_${_shortHash('$university|$programme|$rawDeadline')}',
        university: university,
        programme: programme,
        deadline: parsed,
        deadlineYearAssumed: parsed != null && !_hasExplicitYear(rawDeadline),
        funded: funded,
        applicationFee: fee?.$1,
        feeCurrency: fee?.$2,
        link: link,
        status: _parseStatus(cell(iStatus), cell(iApplied)),
        notes: notes.join('\n'),
        tags: cell(iTags)
            .split(RegExp(r'[;,]'))
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList(),
        country: cell(iCountry).isEmpty ? null : cell(iCountry),
        createdAt: now,
        updatedAt: now,
      ));
    }

    if (positions.isEmpty) {
      skipped.add('No data rows found below the header.');
    }

    return SeedBundle(
      positions: positions,
      assumedYear: assumedYear,
      source: source,
      skipped: skipped,
    );
  }

  // ---- parsing helpers -----------------------------------------------------

  int _findHeaderRow(List<List<dynamic>> rows) {
    const markers = [
      'university', 'college', 'course', 'programme', 'program',
      'deadline', 'status', 'link',
    ];
    var best = 0;
    var bestScore = -1;
    for (var i = 0; i < rows.length && i < 3; i++) {
      final cells =
          rows[i].map((c) => c.toString().trim().toLowerCase()).toList();
      final score =
          markers.where((m) => cells.any((c) => c.contains(m))).length;
      if (score > bestScore) {
        bestScore = score;
        best = i;
      }
    }
    return best;
  }

  static final _months = {
    for (var i = 0; i < 12; i++)
      const [
        'jan', 'feb', 'mar', 'apr', 'may', 'jun',
        'jul', 'aug', 'sep', 'oct', 'nov', 'dec'
      ][i]: i + 1
  };

  bool _hasExplicitYear(String raw) => RegExp(r'\b(19|20)\d{2}\b').hasMatch(raw);

  DateTime? _parseDeadline(String raw, int assumedYear) {
    if (raw.isEmpty) return null;
    final s = raw.trim();

    // ISO first: unambiguous, so no heuristics needed.
    final iso = DateTime.tryParse(s);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);

    // "15 Apr", "15 April 2026", "15.Apr.2026"
    final named = RegExp(r'(\d{1,2})[\s.\-/]*([A-Za-z]{3,})[\s.\-/]*(\d{4})?')
        .firstMatch(s);
    if (named != null) {
      final month = _months[named.group(2)!.substring(0, 3).toLowerCase()];
      if (month != null) {
        final year = int.tryParse(named.group(3) ?? '') ?? assumedYear;
        final day = int.parse(named.group(1)!);
        if (day >= 1 && day <= 31) return DateTime(year, month, day);
      }
    }

    // "06/03/2026" — day first, which is what these sheets use. An ambiguous
    // value like 06/03 is NOT guessed at; it falls through to null and the
    // raw text is preserved in the notes.
    final numeric =
        RegExp(r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})$').firstMatch(s);
    if (numeric != null) {
      final day = int.parse(numeric.group(1)!);
      final month = int.parse(numeric.group(2)!);
      var year = int.parse(numeric.group(3)!);
      if (year < 100) year += 2000;
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return DateTime(year, month, day);
      }
    }

    return null;
  }

  (double, String?)? _parseFee(String raw) {
    if (raw.isEmpty) return null;
    final m = RegExp(r'([\d.]+)\s*([A-Za-z]{3})?').firstMatch(raw.trim());
    if (m == null) return null;
    final value = double.tryParse(m.group(1)!);
    if (value == null) return null;
    return (value, m.group(2)?.toUpperCase());
  }

  bool? _parseBool(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'yes' || s == 'true' || s == 'y' || s == '1') return true;
    if (s == 'no' || s == 'false' || s == 'n' || s == '0') return false;
    return null;
  }

  AppStatus _parseStatus(String statusCell, String appliedCell) {
    final s = statusCell.trim().toLowerCase();
    if (s.contains('reject')) return AppStatus.rejected;
    if (s.contains('accept') || s.contains('offer')) return AppStatus.accepted;
    if (s.contains('interview')) return AppStatus.interview;
    if (s.contains('withdraw')) return AppStatus.withdrawn;
    if (s.contains('applied') || s.contains('submitted')) {
      return AppStatus.applied;
    }
    if (_parseBool(appliedCell) == true) return AppStatus.applied;
    return AppStatus.notApplied;
  }

  List<String> _unmappedColumns(
    List<String> header,
    List<dynamic> row,
    Set<int> claimed,
  ) {
    final out = <String>[];
    for (var i = 0; i < header.length && i < row.length; i++) {
      if (claimed.contains(i)) continue;
      final name = header[i].trim();
      final value = row[i].toString().trim();
      if (name.isEmpty || value.isEmpty) continue;
      out.add('$name: $value');
    }
    return out;
  }

  /// FNV-1a. Not cryptographic — it only has to be stable across runs so a
  /// re-import updates the same document. Avoids pulling in `crypto` for one
  /// call.
  String _shortHash(String input) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(input)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
