import 'dart:math';

import '../models/models.dart';
import 'ranking_service.dart';

/// Rezultatul motorului de matchmaking: compoziția echipelor + șanse de victorie.
class MatchmakingResult {
  const MatchmakingResult({
    required this.teamA,
    required this.teamB,
    required this.teamSumMuA,
    required this.teamSumMuB,
    required this.winChanceTeamA,
  });

  final List<Player> teamA;
  final List<Player> teamB;
  final double teamSumMuA;
  final double teamSumMuB;

  /// Probabilitate că echipa A câștigă (model Gaussian simplificat).
  final double winChanceTeamA;
}

/// Motor **Iterative Swap** — specificația 3.1.
///
/// - Dacă există exact doi portari permanenți, sunt plasați obligatoriu în echipe
///   diferite și **nu** mai sunt mutați de swap-uri.
/// - Restul jucătorilor sunt amestecați aleator, apoi încercăm până la 100 de
///   interschimbări aleatoare care micșorează \|Σμ_A − Σμ_B\|.
class MatchmakingEngine {
  MatchmakingEngine({
    Random? random,
    RankingService? rankingService,
  })  : _random = random ?? Random.secure(),
        _ranking = rankingService ?? RankingService();

  final Random _random;
  final RankingService _ranking;

  /// Numărul de iterații din specificație.
  static const int iterations = 100;
  static const int restarts = 20;

  /// Ponderi pentru obiectiv:
  /// - `balanceWeight`: echilibru între echipe (diferența de putere).
  /// - `homogeneityWeight`: omogenitate (să nu ai "spike-uri" mari într-o echipă).
  ///
  /// Folosim `conservativeSkill` (μ − 3σ) ca proxy pentru "valoarea" jucătorului,
  /// fiind mai stabilă decât μ când σ e mare.
  static const double balanceWeight = 1.0;
  static const double homogeneityWeight = 0.55;

  MatchmakingResult balanceTeams(List<Player> participants) {
    if (participants.length < 2) {
      throw ArgumentError('Sunt necesari cel puțin 2 jucători pentru meci.');
    }

    final permGk =
        participants.where((p) => p.isPermanentGk).toList(growable: false);
    final rest =
        participants.where((p) => !p.isPermanentGk).toList(growable: true);

    // Doar primii doi portari permanenți rămân „fixați” pe echipe opuse (spec 3.1).
    final locked =
        permGk.length >= 2 ? {permGk[0].id, permGk[1].id} : <String>{};

    List<Player>? bestA;
    List<Player>? bestB;
    var bestScore = double.infinity;

    // Multi-start: încearcă mai multe shuffl-uri inițiale și păstrează cea mai bună soluție.
    for (var r = 0; r < restarts; r++) {
      rest.shuffle(_random);

      final teamA = <Player>[];
      final teamB = <Player>[];

      void assignPermanentGoalkeepers() {
        if (permGk.length >= 2) {
          teamA.add(permGk[0]);
          teamB.add(permGk[1]);
          for (var i = 2; i < permGk.length; i++) {
            (i.isEven ? teamA : teamB).add(permGk[i]);
          }
        } else {
          teamA.addAll(permGk);
        }
      }

      assignPermanentGoalkeepers();

      for (var i = 0; i < rest.length; i++) {
        (i.isEven ? teamA : teamB).add(rest[i]);
      }

      _balanceSizes(teamA, teamB);

      var localBestA = List<Player>.from(teamA);
      var localBestB = List<Player>.from(teamB);
      var localBestScore = _objective(localBestA, localBestB);

      for (var n = 0; n < iterations; n++) {
        final swappableA = <int>[];
        for (var i = 0; i < teamA.length; i++) {
          if (!locked.contains(teamA[i].id)) swappableA.add(i);
        }
        final swappableB = <int>[];
        for (var i = 0; i < teamB.length; i++) {
          if (!locked.contains(teamB[i].id)) swappableB.add(i);
        }
        if (swappableA.isEmpty || swappableB.isEmpty) break;

        final ia = swappableA[_random.nextInt(swappableA.length)];
        final ib = swappableB[_random.nextInt(swappableB.length)];

        final tmp = teamA[ia];
        teamA[ia] = teamB[ib];
        teamB[ib] = tmp;

        final score = _objective(teamA, teamB);
        if (score < localBestScore) {
          localBestScore = score;
          localBestA = List<Player>.from(teamA);
          localBestB = List<Player>.from(teamB);
        } else {
          final t2 = teamA[ia];
          teamA[ia] = teamB[ib];
          teamB[ib] = t2;
        }
      }

      // Tie-break: dacă e "egal de bun", alegem aleator ca să obținem varietate.
      if (localBestScore < bestScore - 1e-9 ||
          ((localBestScore - bestScore).abs() <= 1e-9 &&
              _random.nextBool())) {
        bestScore = localBestScore;
        bestA = localBestA;
        bestB = localBestB;
      }
    }

    final finalA = bestA ?? <Player>[];
    final finalB = bestB ?? <Player>[];

    final sumA = finalA.fold<double>(0, (s, p) => s + p.mu);
    final sumB = finalB.fold<double>(0, (s, p) => s + p.mu);
    final winA = _ranking.winProbabilityTeamA(teamA: finalA, teamB: finalB);

    return MatchmakingResult(
      teamA: finalA,
      teamB: finalB,
      teamSumMuA: sumA,
      teamSumMuB: sumB,
      winChanceTeamA: winA,
    );
  }

  double _objective(List<Player> a, List<Player> b) {
    final bal = _teamStrengthSum(a) - _teamStrengthSum(b);
    final balance = bal.abs();

    // Omogenitate: penalizăm spread-ul (σ echipă) și diferența de spread între echipe.
    final spreadA = _teamSpread(a);
    final spreadB = _teamSpread(b);
    final homogeneity = (spreadA + spreadB) + (spreadA - spreadB).abs();

    return balanceWeight * balance + homogeneityWeight * homogeneity;
  }

  double _teamStrengthSum(List<Player> team) {
    return team.fold<double>(0, (s, p) => s + p.conservativeSkill);
  }

  double _teamSpread(List<Player> team) {
    if (team.length <= 1) return 0;
    final vals = team.map((p) => p.conservativeSkill).toList(growable: false);
    final mean = vals.reduce((a, b) => a + b) / vals.length;
    var varSum = 0.0;
    for (final v in vals) {
      final d = v - mean;
      varSum += d * d;
    }
    return sqrt(varSum / vals.length);
  }

  /// Echilibrează numărul de jucători între echipe mutând unul din lista mai lungă.
  void _balanceSizes(List<Player> teamA, List<Player> teamB) {
    while ((teamA.length - teamB.length).abs() > 1) {
      if (teamA.length > teamB.length) {
        teamB.add(teamA.removeLast());
      } else {
        teamA.add(teamB.removeLast());
      }
    }
    if (teamA.length < teamB.length) {
      teamA.add(teamB.removeLast());
    } else if (teamB.length < teamA.length) {
      teamB.add(teamA.removeLast());
    }
  }
}
