import 'package:flutter_test/flutter_test.dart';

import 'package:fotbal_matchmaker/models/models.dart';
import 'package:fotbal_matchmaker/services/ranking_service.dart';

MatchPlayerStats _st({
  required String matchId,
  required String playerId,
  required MatchTeam team,
  int goals = 0,
  bool isRotationGk = false,
  bool receivedMvpVote = false,
  bool receivedGkVote = false,
}) {
  return MatchPlayerStats(
    matchId: matchId,
    playerId: playerId,
    team: team,
    goals: goals,
    isRotationGk: isRotationGk,
    receivedMvpVote: receivedMvpVote,
    receivedGkVote: receivedGkVote,
  );
}

Player _p(
  String id,
  String name, {
  double mu = Player.defaultMu,
  double sigma = Player.defaultSigma,
  bool permGk = false,
  int matchesPlayed = 0,
}) {
  return Player(
    id: id,
    name: name,
    mu: mu,
    sigma: sigma,
    isPermanentGk: permGk,
    matchesPlayed: matchesPlayed,
  );
}

void main() {
  group('RankingService', () {
    test('rotation GK vote gives points only to rotation (not permanent GK)', () {
      final s = RankingService();
      final scoreRotation = s.computePerformanceScore(
        wonMatch: false,
        goals: 0,
        receivedMvpVote: false,
        receivedGkVote: true,
        isPermanentGk: false,
        isRotationGk: true,
      );
      final scorePermanent = s.computePerformanceScore(
        wonMatch: false,
        goals: 0,
        receivedMvpVote: false,
        receivedGkVote: true,
        isPermanentGk: true,
        isRotationGk: false,
      );
      expect(scoreRotation, greaterThan(0));
      expect(scorePermanent, equals(0));
    });

    test('winner team increases mu and matchesPlayed for all participants', () {
      final s = RankingService();
      final matchId = 'm1';

      final a1 = _p('a1', 'A1');
      final a2 = _p('a2', 'A2');
      final b1 = _p('b1', 'B1');
      final b2 = _p('b2', 'B2');

      final stats = <String, MatchPlayerStats>{
        a1.id: _st(matchId: matchId, playerId: a1.id, team: MatchTeam.a, goals: 3),
        a2.id: _st(matchId: matchId, playerId: a2.id, team: MatchTeam.a, goals: 0),
        b1.id: _st(matchId: matchId, playerId: b1.id, team: MatchTeam.b, goals: 0),
        b2.id: _st(matchId: matchId, playerId: b2.id, team: MatchTeam.b, goals: 0),
      };

      final updated = s.applyMatchToPlayers(
        roster: [a1, a2, b1, b2],
        scoreA: 3,
        scoreB: 0,
        statsByPlayerId: stats,
        teamA: [a1, a2],
        teamB: [b1, b2],
      );

      final uA1 = updated.firstWhere((p) => p.id == a1.id);
      final uA2 = updated.firstWhere((p) => p.id == a2.id);
      final uB1 = updated.firstWhere((p) => p.id == b1.id);
      final uB2 = updated.firstWhere((p) => p.id == b2.id);

      expect(uA1.matchesPlayed, equals(1));
      expect(uA2.matchesPlayed, equals(1));
      expect(uB1.matchesPlayed, equals(1));
      expect(uB2.matchesPlayed, equals(1));

      // Winners should increase mu on average.
      final avgMuA = (uA1.mu + uA2.mu) / 2;
      final avgMuB = (uB1.mu + uB2.mu) / 2;
      expect(avgMuA, greaterThan(avgMuB));

      // Higher performer within same winning team should gain more.
      expect(uA1.mu, greaterThan(uA2.mu));
    });
  });
}

