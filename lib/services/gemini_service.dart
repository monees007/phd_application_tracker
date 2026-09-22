import 'dart:convert';

import 'package:http/http.dart' as http;

/// What the model managed to pull out of a job advert.
///
/// Every field is nullable on purpose. The prompt tells the model to return
/// null rather than guess, so a null here means "not stated on the page",
/// which the review screen shows as blank instead of inventing a value.
class ExtractedPosition {
  final String? university;
  final String? programme;

  /// ISO yyyy-MM-dd, or null.
  final String? deadline;

  /// False when the page gave a day and month but no year, so the year in
  /// [deadline] was inferred and needs checking.
  final bool deadlineYearExplicit;

  final bool? funded;
  final double? applicationFee;
  final String? feeCurrency;
  final String? country;
  final List<String> tags;
  final String? summary;

  /// The model's own read on how much of this it actually found: high,
  /// medium or low.
  final String confidence;

  /// Fields the model was asked for and could not find.
  final List<String> notFound;

  const ExtractedPosition({
    this.university,
    this.programme,
    this.deadline,
    this.deadlineYearExplicit = false,
    this.funded,
    this.applicationFee,
    this.feeCurrency,
    this.country,
    this.tags = const [],
    this.summary,
    this.confidence = 'low',
    this.notFound = const [],
  });

  Map<String, dynamic> toJson() => {
    'university': university,
    'programme': programme,
    'deadline': deadline,
    'deadlineYearExplicit': deadlineYearExplicit,
    'funded': funded,
    'applicationFee': applicationFee,
    'feeCurrency': feeCurrency,
    'country': country,
    'tags': tags,
    'summary': summary,
    'confidence': confidence,
    'notFound': notFound,
  };

  factory ExtractedPosition.fromJson(Map<String, dynamic> j) {
    double? asDouble(Object? v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    String? asString(Object? v) {
      if (v == null) return null;
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      // Models sometimes emit these as literal strings.
      if (s.toLowerCase() == 'null' || s.toLowerCase() == 'n/a') return null;
      return s;
    }

    return ExtractedPosition(
      university: asString(j['university']),
      programme: asString(j['programme']),
      deadline: asString(j['deadline']),
      deadlineYearExplicit: j['deadlineYearExplicit'] == true,
      funded: j['funded'] is bool ? j['funded'] as bool : null,
      applicationFee: asDouble(j['applicationFee']),
      feeCurrency: asString(j['feeCurrency']),
      country: asString(j['country']),
      tags: (j['tags'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
      summary: asString(j['summary']),
      confidence: asString(j['confidence'])?.toLowerCase() ?? 'low',
      notFound: (j['notFound'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  bool get isEmpty => university == null && programme == null;
}

class GeminiException implements Exception {
  final String message;
  const GeminiException(this.message);
  @override
  String toString() => message;
}

class GeminiService {
  GeminiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _base = 'https://generativelanguage.googleapis.com/v1beta';

  /// A starting point, not a guarantee. Model names change often and old ones
  /// are retired, so the UI lets you list what your key can actually reach
  /// and pick from that. If this one 404s, that is what it means.
  static const defaultModel = 'gemini-3.5-flash';

  /// Model IDs available to this API key that can generate content.
  Future<List<String>> listModels(String apiKey) async {
    final res = await _client.get(
      Uri.parse('$_base/models'),
      headers: {'x-goog-api-key': apiKey},
    ).timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw GeminiException(_describeError(res));
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final models = (body['models'] as List?) ?? const [];

    return models
        .whereType<Map<String, dynamic>>()
        .where((m) =>
            (m['supportedGenerationMethods'] as List?)
                ?.contains('generateContent') ??
            true)
        .map((m) => (m['name'] as String? ?? '').replaceFirst('models/', ''))
        .where((n) => n.isNotEmpty)
        .toList()
      ..sort();
  }

  Future<ExtractedPosition> extract({
    required String pageText,
    required String sourceUrl,
    required String apiKey,
    String? model,
    int currentYear = 0,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const GeminiException(
          'No Gemini API key saved. Add one in Settings.');
    }
    if (pageText.trim().length < 80) {
      throw const GeminiException(
          'There was almost no text on that page to work from.');
    }

    final year = currentYear == 0 ? DateTime.now().year : currentYear;
    final prompt = _buildPrompt(pageText, sourceUrl, year);
    final modelId = (model == null || model.trim().isEmpty)
        ? defaultModel
        : model.trim();

    // First attempt constrains the output with a schema. If the API rejects
    // the schema — field names in this area have shifted between versions —
    // retry without it. The prompt alone still asks for bare JSON.
    var res = await _post(modelId, apiKey, _body(prompt, withSchema: true));

    if (res.statusCode == 400 &&
        res.body.toLowerCase().contains('schema')) {
      res = await _post(modelId, apiKey, _body(prompt, withSchema: false));
    }

    if (res.statusCode != 200) {
      throw GeminiException(_describeError(res, modelId: modelId));
    }

    return ExtractedPosition.fromJson(_parseJsonPayload(res.body));
  }

  Future<http.Response> _post(
    String model,
    String apiKey,
    Map<String, dynamic> body,
  ) {
    return _client
        .post(
          Uri.parse('$_base/models/$model:generateContent'),
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
  }

  Map<String, dynamic> _body(String prompt, {required bool withSchema}) {
    return {
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        // Extraction, not writing: no reason to sample creatively.
        'temperature': 0,
        'responseMimeType': 'application/json',
        if (withSchema) 'responseSchema': _schema,
      },
    };
  }

  static const Map<String, dynamic> _schema = {
    'type': 'OBJECT',
    'properties': {
      'university': {'type': 'STRING', 'nullable': true},
      'programme': {'type': 'STRING', 'nullable': true},
      'deadline': {
        'type': 'STRING',
        'nullable': true,
        'description': 'Application deadline as yyyy-MM-dd.',
      },
      'deadlineYearExplicit': {'type': 'BOOLEAN'},
      'funded': {'type': 'BOOLEAN', 'nullable': true},
      'applicationFee': {'type': 'NUMBER', 'nullable': true},
      'feeCurrency': {'type': 'STRING', 'nullable': true},
      'country': {'type': 'STRING', 'nullable': true},
      'tags': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      },
      'summary': {'type': 'STRING', 'nullable': true},
      'confidence': {
        'type': 'STRING',
        'enum': ['high', 'medium', 'low'],
      },
      'notFound': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      },
    },
    'required': ['deadlineYearExplicit', 'confidence', 'tags', 'notFound'],
  };

  String _buildPrompt(String pageText, String url, int year) {
    return '''
You are extracting structured data from the text of a PhD or research position
advert. Today's date is ${DateTime.now().toIso8601String().substring(0, 10)}.

Rules, in order of importance:
1. Only report what the page states. If a field is not stated, return null for
   it and add its name to "notFound". Never guess, never infer from the
   university's reputation, and never fill a field from general knowledge.
2. "deadline" must be yyyy-MM-dd. If the page gives a day and month but no
   year, choose the next occurrence of that date after today, and set
   "deadlineYearExplicit" to false. Set it to true only when the page states
   the year outright.
3. "funded" is true only if the page says the position is funded, salaried, or
   comes with a stipend or employment contract. Most European PhD positions
   are employment; if the page says nothing about money, return null.
4. "applicationFee" is the fee to submit an application, not the salary and
   not the tuition. Null unless a fee is explicitly stated.
5. "programme" is the position or project title, not the page's marketing
   headline. "university" is the institution, without its department.
6. "tags" are at most four short research-area keywords taken from the text.
7. "summary" is at most two sentences on what the project involves, in your
   own words.
8. "confidence" is high only when university, programme and deadline were all
   clearly stated; low if the text looks like a navigation page, a cookie
   banner, or a listing index rather than one specific advert.

Source URL: $url

--- PAGE TEXT ---
$pageText
--- END PAGE TEXT ---

Respond with a single JSON object and nothing else. No prose, no code fences.
''';
  }

  Map<String, dynamic> _parseJsonPayload(String responseBody) {
    final decoded = jsonDecode(responseBody) as Map<String, dynamic>;

    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      final feedback = decoded['promptFeedback'];
      throw GeminiException(feedback == null
          ? 'The model returned no candidates.'
          : 'The request was blocked: $feedback');
    }

    final first = candidates.first as Map<String, dynamic>;
    final finish = first['finishReason'];
    final parts = (first['content'] as Map<String, dynamic>?)?['parts'] as List?;

    if (parts == null || parts.isEmpty) {
      throw GeminiException(
          'The model returned an empty response (finishReason: $finish).');
    }

    final text = parts
        .whereType<Map<String, dynamic>>()
        .map((p) => p['text']?.toString() ?? '')
        .join()
        .trim();

    return _decodeLoose(text);
  }



  /// Tolerates a model that wrapped its JSON in a code fence or added a
  /// sentence either side, which happens when the schema path was skipped.
  Map<String, dynamic> _decodeLoose(String text) {
    var s = text.trim();
    s = s.replaceAll(RegExp(r'^```(?:json)?', multiLine: true), '');
    s = s.replaceAll(RegExp(r'```$', multiLine: true), '');
    s = s.trim();

    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      final start = s.indexOf('{');
      final end = s.lastIndexOf('}');
      if (start >= 0 && end > start) {
        try {
          return jsonDecode(s.substring(start, end + 1))
              as Map<String, dynamic>;
        } catch (_) {/* fall through */}
      }
      throw const GeminiException(
          'The model did not return usable JSON. Try again, or pick a '
          'different model in Settings.');
    }
  }

  String _describeError(http.Response res, {String? modelId}) {
    String detail = res.body;
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['error'] is Map) {
        detail = (body['error']['message'] ?? detail).toString();
      }
    } catch (_) {/* keep raw body */}

    return switch (res.statusCode) {
      400 => 'Gemini rejected the request: $detail',
      401 || 403 =>
        'Gemini refused the API key. Check it is valid and that the '
            'Generative Language API is enabled. ($detail)',
      404 =>
        'No such model${modelId == null ? '' : ' "$modelId"'}. Open Settings '
            'and pick one your key can reach. ($detail)',
      429 => 'Rate limit or quota exceeded. Wait and try again.',
      >= 500 => 'Gemini had a server error (${res.statusCode}). Try again.',
      _ => 'Gemini returned HTTP ${res.statusCode}: $detail',
    };
  }

  void dispose() => _client.close();
}
