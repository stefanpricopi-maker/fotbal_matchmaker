import 'dart:convert';

/// Meci înregistrat (scor final + metadate).
class Match {
  const Match({
    required this.id,
    required this.createdAt,
    required this.scoreA,
    required this.scoreB,
    this.durationMinutes = Match.defaultDuration,
  });

  static const int defaultDuration = 90;

  final String id;
  final DateTime createdAt;
  final int scoreA;
  final int scoreB;
  final int durationMinutes;

  Match copyWith({
    String? id,
    DateTime? createdAt,
    int? scoreA,
    int? scoreB,
    int? durationMinutes,
  }) {
    return Match(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      scoreA: scoreA ?? this.scoreA,
      scoreB: scoreB ?? this.scoreB,
      durationMinutes: durationMinutes ?? this.durationMinutes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt.toUtc().toIso8601String(),
        'score_a': scoreA,
        'score_b': scoreB,
        'duration_minutes': durationMinutes,
      };

  factory Match.fromJson(Map<String, dynamic> json) {
    return Match(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      scoreA: (json['score_a'] as num).toInt(),
      scoreB: (json['score_b'] as num).toInt(),
      durationMinutes:
          (json['duration_minutes'] as num?)?.toInt() ?? defaultDuration,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory Match.fromJsonString(String source) =>
      Match.fromJson(jsonDecode(source) as Map<String, dynamic>);
}
