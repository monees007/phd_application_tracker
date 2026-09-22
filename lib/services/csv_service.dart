import 'dart:io';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/position.dart';

/// Exports the board back to a spreadsheet-friendly CSV so the data is never
/// trapped inside the app.
class CsvService {
  static final _date = DateFormat('yyyy-MM-dd');

  String buildCsv(List<Position> positions) {
    final rows = <List<dynamic>>[
      [
        'University',
        'Programme',
        'Deadline',
        'Status',
        'Funded',
        'App fee',
        'Fee currency',
        'Link',
        'Applied on',
        'Result on',
        'Tags',
        'Notes',
      ],
      ...positions.map((p) => [
            p.university,
            p.programme,
            p.deadline == null ? '' : _date.format(p.deadline!),
            p.status.label,
            p.funded == null ? '' : (p.funded! ? 'Yes' : 'No'),
            p.applicationFee?.toString() ?? '',
            p.feeCurrency ?? '',
            p.link,
            p.appliedAt == null ? '' : _date.format(p.appliedAt!),
            p.resultAt == null ? '' : _date.format(p.resultAt!),
            p.tags.join('; '),
            p.notes.replaceAll('\n', ' | '),
          ]),
    ];
    return const ListToCsvConverter().convert(rows);
  }

  /// Writes to the app's documents directory and opens the system share sheet.
  /// Returns the file path so the UI can show it.
  Future<String> exportAndShare(List<Position> positions) async {
    final csv = buildCsv(positions);
    final dir = Directory.systemTemp;
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final file = File('${dir.path}/phd_positions_$stamp.csv');
    await file.writeAsString(csv);

    // share_plus v10 API. v11 replaced this with SharePlus.instance.share().
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'PhD application tracker export',
    );
    return file.path;
  }
}
