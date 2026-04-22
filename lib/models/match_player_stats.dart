import 'dart:convert';

import 'match_team.dart';

/// Statistici individuale pe meci (tabel `match_player_stats`).
class MatchPlayerStats {
  const MatchPlayerStats({
    required this.matchId,
    required this.playerId,
    required this.team,
    this.goals = 0,
    this.saves = 0,
    this.isRotationGk = false,
    this.receivedMvpVote = false,
    this.cleanSheet = false,
  });

  final String matchId;
  final String playerId;
  final MatchTeam team;
  final int goals;
  final int saves;
  final bool isRotationGk;
  final bool receivedMvpVote;
  final bool cleanSheet;

  MatchPlayerStats copyWith({
    String? matchId,
    String? playerId,
    MatchTeam? team,
    int? goals,
    int? saves,
    bool? isRotationGk,
    bool? receivedMvpVote,
    bool? cleanSheet,
  }) {
    return MatchPlayerStats(
      matchId: matchId ?? this.matchId,
      playerId: playerId ?? this.playerId,
      team: team ?? this.team,
      goals: goals ?? this.goals,
      saves: saves ?? this.saves,
      isRotationGk: isRotationGk ?? this.isRotationGk,
      receivedMvpVote: receivedMvpVote ?? this.receivedMvpVote,
      cleanSheet: cleanSheet ?? this.cleanSheet,
    );
  }

  Map<String, dynamic> toJson() => {
        'match_id': matchId,
        'player_id': playerId,
        'team': team.dbValue,
        'goals': goals,
        'saves': saves,
        'is_rotation_gk': isRotationGk,
        'received_mvp_vote': receivedMvpVote,
        'clean_sheet': cleanSheet,
      };

  factory MatchPlayerStats.fromJson(Map<String, dynamic> json) {
    return MatchPlayerStats(
      matchId: json['match_id'] as String,
      playerId: json['player_id'] as String,
      team: MatchTeam.fromDb(json['team'] as String),
      goals: (json['goals'] as num?)?.toInt() ?? 0,
      saves: (json['saves'] as num?)?.toInt() ?? 0,
      isRotationGk: json['is_rotation_gk'] as bool? ?? false,
      receivedMvpVote: json['received_mvp_vote'] as bool? ?? false,
      cleanSheet: json['clean_sheet'] as bool? ?? false,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory MatchPlayerStats.fromJsonString(String source) =>
      MatchPlayerStats.fromJson(jsonDecode(source) as Map<String, dynamic>);
}
