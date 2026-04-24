import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:fotbal_matchmaker/models/models.dart';
import 'package:fotbal_matchmaker/services/matchmaking_engine.dart';

Player _p(
  String id,
  String name, {
  double mu = Player.defaultMu,
  double sigma = Player.defaultSigma,
  bool permGk = false,
}) {
  return Player(
    id: id,
    name: name,
    mu: mu,
    sigma: sigma,
    isPermanentGk: permGk,
    matchesPlayed: 0,
  );
}

void main() {
  group('MatchmakingEngine.balanceTeams', () {
    test('keeps two permanent GKs on opposite teams', () {
      final engine = MatchmakingEngine(random: Random(42));
      final gk1 = _p('gk1', 'GK 1', permGk: true, mu: 28);
      final gk2 = _p('gk2', 'GK 2', permGk: true, mu: 27);
      final others = List.generate(
        10,
        (i) => _p(
          'p$i',
          'P$i',
          mu: 20 + i.toDouble(),
          sigma: 7.5,
        ),
      );

      final res = engine.balanceTeams([gk1, gk2, ...others]);

      final teamAIds = res.teamA.map((e) => e.id).toSet();
      final teamBIds = res.teamB.map((e) => e.id).toSet();
      expect(teamAIds.contains(gk1.id) || teamBIds.contains(gk1.id), isTrue);
      expect(teamAIds.contains(gk2.id) || teamBIds.contains(gk2.id), isTrue);
      expect(teamAIds.contains(gk1.id) && teamAIds.contains(gk2.id), isFalse);
      expect(teamBIds.contains(gk1.id) && teamBIds.contains(gk2.id), isFalse);
    });

    test('produces teams with size difference at most 1', () {
      final engine = MatchmakingEngine(random: Random(7));
      final players = List.generate(
        13,
        (i) => _p('p$i', 'P$i', mu: 25 + (i % 5), sigma: 8),
      );

      final res = engine.balanceTeams(players);
      expect((res.teamA.length - res.teamB.length).abs(), lessThanOrEqualTo(1));
      expect(res.teamA.length + res.teamB.length, equals(players.length));
    });

    test('for symmetric ratings, win chance stays near 50%', () {
      final engine = MatchmakingEngine(random: Random(123));
      final players = <Player>[
        _p('a1', 'A1', mu: 25, sigma: 7),
        _p('a2', 'A2', mu: 25, sigma: 7),
        _p('a3', 'A3', mu: 25, sigma: 7),
        _p('a4', 'A4', mu: 25, sigma: 7),
        _p('a5', 'A5', mu: 25, sigma: 7),
        _p('a6', 'A6', mu: 25, sigma: 7),
        _p('a7', 'A7', mu: 25, sigma: 7),
        _p('a8', 'A8', mu: 25, sigma: 7),
      ];

      final res = engine.balanceTeams(players);
      expect(res.winChanceTeamA, inInclusiveRange(0.35, 0.65));
    });
  });
}

