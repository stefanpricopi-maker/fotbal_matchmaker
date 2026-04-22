import 'dart:math' as math;

import 'package:matchmaker/matchmaker.dart';

import '../models/models.dart';

/// Calculul performanței **P_i** și actualizarea ratingurilor μ/σ.
///
/// Specificația menționează modelul **OpenSkill**; pachetul `openskill_dart`
/// nu este disponibil pe pub.dev, deci folosim **TrueSkill** din `matchmaker`
/// (aceeași reprezentare Gaussiană μ, σ cu valorile implicite din SIMF).
class RankingService {
  RankingService({TrueSkill? engine})
      : _ts = engine ??
            const TrueSkill(
              mu: Player.defaultMu,
              sigma: Player.defaultSigma,
              drawProbability: 0.08,
            );

  final TrueSkill _ts;

  List<double> _weightsFromPerformanceScores(List<double> scores) {
    if (scores.isEmpty) return const [];
    if (scores.length == 1) return const [1.0];
    final mean = scores.reduce((a, b) => a + b) / scores.length;
    var varSum = 0.0;
    for (final s in scores) {
      final d = s - mean;
      varSum += d * d;
    }
    final std = math.sqrt(varSum / scores.length);
    if (std <= 1e-9) {
      return List<double>.filled(scores.length, 1.0);
    }

    // Convertim performanța în greutăți de participare:
    // - peste medie → primește o fracție mai mare din delta echipei
    // - sub medie → primește o fracție mai mică
    //
    // TrueSkill/`matchmaker` folosește `weights` ca „participation weight”, dar
    // aici o folosim ca aproximație pentru cerința SIMF: diferențiem impactul
    // în funcție de P_i (secțiunea 3.2).
    return scores
        .map((s) => (1.0 + 0.15 * ((s - mean) / std)).clamp(0.7, 1.3))
        .toList(growable: false);
  }

  /// Ponderile pentru termenul „Saves” din formulă (secțiunea 3.2).
  ///
  /// - Portar permanent: pondere 3.
  /// - Portar de rotație (mănușă): pondere 1.
  /// - Altfel: parada unui jucător de câmp nu intră în formulă → 0.
  double savesWeight({
    required bool isPermanentGk,
    required bool isRotationGk,
  }) {
    if (isPermanentGk) return 3;
    if (isRotationGk) return 1;
    return 0;
  }

  /// Formula P_i din specificație (fără normalizare ulterioară).
  double computePerformanceScore({
    required bool wonMatch,
    required int goals,
    required int saves,
    required bool cleanSheet,
    required bool receivedMvpVote,
    required bool isPermanentGk,
    required bool isRotationGk,
  }) {
    final winPoints = wonMatch ? 10.0 : 0.0;
    final gkW = savesWeight(
      isPermanentGk: isPermanentGk,
      isRotationGk: isRotationGk,
    );
    return winPoints +
        goals * 4 +
        saves * gkW +
        (cleanSheet ? 8.0 : 0.0) +
        (receivedMvpVote ? 7.0 : 0.0);
  }

  /// Probabilitate aproximativă că **echipa A** câștigă, folosind suma μ și
  /// dispersia combinată (aproximație Gaussiană — secțiunea 3.1, afișare șanse).
  double winProbabilityTeamA({
    required List<Player> teamA,
    required List<Player> teamB,
  }) {
    final muA = teamA.fold<double>(0, (s, p) => s + p.mu);
    final muB = teamB.fold<double>(0, (s, p) => s + p.mu);
    final varA = teamA.fold<double>(0, (s, p) => s + p.sigma * p.sigma);
    final varB = teamB.fold<double>(0, (s, p) => s + p.sigma * p.sigma);
    final diff = muA - muB;
    final denom = math.sqrt(varA + varB + 1e-9);
    if (denom == 0) return 0.5;
    return _phi(diff / denom);
  }

  /// Actualizează μ și σ după rezultatul meciului, păstrând ordinea din [roster].
  ///
  /// [statsByPlayerId] trebuie să conțină câte o intrare pentru fiecare jucător
  /// din ambele echipe (cheie = `playerId`).
  List<Player> applyMatchToPlayers({
    required List<Player> roster,
    required int scoreA,
    required int scoreB,
    required Map<String, MatchPlayerStats> statsByPlayerId,
    required List<Player> teamA,
    required List<Player> teamB,
  }) {
    if (teamA.isEmpty || teamB.isEmpty) {
      throw ArgumentError('Echipele trebuie să aibă cel puțin un jucător.');
    }

    for (final p in [...teamA, ...teamB]) {
      if (!statsByPlayerId.containsKey(p.id)) {
        throw ArgumentError('Lipsește statistica pentru jucătorul ${p.id}.');
      }
    }

    final ratingsA =
        teamA.map((p) => _ts.createRating(mu: p.mu, sigma: p.sigma)).toList();
    final ratingsB =
        teamB.map((p) => _ts.createRating(mu: p.mu, sigma: p.sigma)).toList();

    final teamAWon = scoreA > scoreB;
    final teamBWon = scoreB > scoreA;

    final perfA = <double>[];
    for (final p in teamA) {
      final st = statsByPlayerId[p.id]!;
      perfA.add(
        computePerformanceScore(
          wonMatch: teamAWon,
          goals: st.goals,
          saves: st.saves,
          cleanSheet: st.cleanSheet,
          receivedMvpVote: st.receivedMvpVote,
          isPermanentGk: p.isPermanentGk,
          isRotationGk: st.isRotationGk,
        ),
      );
    }
    final perfB = <double>[];
    for (final p in teamB) {
      final st = statsByPlayerId[p.id]!;
      perfB.add(
        computePerformanceScore(
          wonMatch: teamBWon,
          goals: st.goals,
          saves: st.saves,
          cleanSheet: st.cleanSheet,
          receivedMvpVote: st.receivedMvpVote,
          isPermanentGk: p.isPermanentGk,
          isRotationGk: st.isRotationGk,
        ),
      );
    }

    late final List<int> ranks;
    if (scoreA > scoreB) {
      ranks = [0, 1];
    } else if (scoreB > scoreA) {
      ranks = [1, 0];
    } else {
      ranks = [0, 0];
    }

    final updated = _ts.rate(
      [ratingsA, ratingsB],
      ranks: ranks,
      weights: [
        _weightsFromPerformanceScores(perfA),
        _weightsFromPerformanceScores(perfB),
      ],
    );

    final newById = <String, Player>{};
    for (var i = 0; i < teamA.length; i++) {
      final pl = teamA[i];
      final r = updated[0][i];
      newById[pl.id] = pl.copyWith(
        mu: r.mu,
        sigma: r.sigma,
        matchesPlayed: pl.matchesPlayed + 1,
      );
    }
    for (var i = 0; i < teamB.length; i++) {
      final pl = teamB[i];
      final r = updated[1][i];
      newById[pl.id] = pl.copyWith(
        mu: r.mu,
        sigma: r.sigma,
        matchesPlayed: pl.matchesPlayed + 1,
      );
    }

    return roster
        .map((p) => newById[p.id] ?? p)
        .toList(growable: false);
  }

  /// Funcția Φ pentru aproximarea probabilității de victorie (CDF normală standard).
  double _phi(double x) {
    return 0.5 * (1 + _erf(x / math.sqrt(2)));
  }

  /// Aproximare Abramowitz–Stegun pentru erf (aceeași idee ca în TrueSkill).
  double _erf(double x) {
    const p = 0.3275911;
    const a1 = 0.254829592;
    const a2 = -0.284496736;
    const a3 = 1.421413741;
    const a4 = -1.453152027;
    const a5 = 1.061405429;
    final sign = x < 0 ? -1.0 : 1.0;
    final absX = x.abs();
    final t = 1.0 / (1.0 + p * absX);
    final y = 1.0 -
        (((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t * math.exp(-absX * absX));
    return sign * y;
  }
}
