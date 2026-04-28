import 'dart:convert';

/// Meci înregistrat (scor final + metadate).
class Match {
  const Match({
    required this.id,
    required this.createdAt,
    required this.scoreA,
    required this.scoreB,
    this.durationMinutes = Match.defaultDuration,
    this.updatedAt,
  });

  static const int defaultDuration = 90;

  final String id;
  final DateTime createdAt;
  final int scoreA;
  final int scoreB;
  final int durationMinutes;
  final DateTime? updatedAt;

  /// Meci “draft” (salvat fără scor).
  ///
  /// Folosit doar local (SQLite). În Supabase nu urcăm meciuri draft.
  bool get isDraft => scoreA < 0 || scoreB < 0;

  String get scoreLabel => isDraft ? '—' : '$scoreA - $scoreB';

  Match copyWith({
    String? id,
    DateTime? createdAt,
    int? scoreA,
    int? scoreB,
    int? durationMinutes,
    DateTime? updatedAt,
  }) {
    return Match(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      scoreA: scoreA ?? this.scoreA,
      scoreB: scoreB ?? this.scoreB,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': id,
      'created_at': createdAt.toUtc().toIso8601String(),
      'score_a': scoreA,
      'score_b': scoreB,
      'duration_minutes': durationMinutes,
    };
    final u = updatedAt?.toUtc().toIso8601String();
    if (u != null) m['updated_at'] = u;
    return m;
  }

  factory Match.fromJson(Map<String, dynamic> json) {
    return Match(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      scoreA: (json['score_a'] as num).toInt(),
      scoreB: (json['score_b'] as num).toInt(),
      durationMinutes:
          (json['duration_minutes'] as num?)?.toInt() ?? defaultDuration,
      updatedAt: (json['updated_at'] as String?) != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory Match.fromJsonString(String source) =>
      Match.fromJson(jsonDecode(source) as Map<String, dynamic>);
}
