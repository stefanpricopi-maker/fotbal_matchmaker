import 'dart:convert';

import 'match_team.dart';

/// Statistici individuale pe meci (tabel `match_player_stats`).
class MatchPlayerStats {
  const MatchPlayerStats({
    required this.matchId,
    required this.playerId,
    required this.team,
    this.goals = 0,
    this.isRotationGk = false,
    this.receivedMvpVote = false,
    this.receivedGkVote = false,
  });

  final String matchId;
  final String playerId;
  final MatchTeam team;
  final int goals;
  final bool isRotationGk;
  final bool receivedMvpVote;
  final bool receivedGkVote;

  MatchPlayerStats copyWith({
    String? matchId,
    String? playerId,
    MatchTeam? team,
    int? goals,
    bool? isRotationGk,
    bool? receivedMvpVote,
    bool? receivedGkVote,
  }) {
    return MatchPlayerStats(
      matchId: matchId ?? this.matchId,
      playerId: playerId ?? this.playerId,
      team: team ?? this.team,
      goals: goals ?? this.goals,
      isRotationGk: isRotationGk ?? this.isRotationGk,
      receivedMvpVote: receivedMvpVote ?? this.receivedMvpVote,
      receivedGkVote: receivedGkVote ?? this.receivedGkVote,
    );
  }

  Map<String, dynamic> toJson() => {
        'match_id': matchId,
        'player_id': playerId,
        'team': team.dbValue,
        'goals': goals,
        'is_rotation_gk': isRotationGk,
        'received_mvp_vote': receivedMvpVote,
        'received_gk_vote': receivedGkVote,
      };

  static bool _bool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v is num) return v != 0;
    return false;
  }

  factory MatchPlayerStats.fromJson(Map<String, dynamic> json) {
    return MatchPlayerStats(
      matchId: json['match_id'] as String,
      playerId: json['player_id'] as String,
      team: MatchTeam.fromDb(json['team'] as String),
      goals: (json['goals'] as num?)?.toInt() ?? 0,
      isRotationGk: _bool(json['is_rotation_gk']),
      receivedMvpVote: _bool(json['received_mvp_vote']),
      receivedGkVote: _bool(json['received_gk_vote']),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory MatchPlayerStats.fromJsonString(String source) =>
      MatchPlayerStats.fromJson(jsonDecode(source) as Map<String, dynamic>);
}
