import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/debug_log.dart';
import '../core/simf_exception.dart';
import '../models/models.dart';
import '../services/local_store.dart';
import '../services/matchmaking_engine.dart';
import '../services/ranking_service.dart';
import '../services/supabase_service.dart';

/// Stare globală SIMF: jucători, selecție, echipe generate, persistență.
class SimfController extends ChangeNotifier {
  SimfController({
    required LocalStore localStore,
    required SupabaseService supabaseService,
    required RankingService rankingService,
    required MatchmakingEngine matchmakingEngine,
    Uuid? uuid,
  }) : _local = localStore,
       _supabase = supabaseService,
       _ranking = rankingService,
       _matchmaking = matchmakingEngine,
       _uuid = uuid ?? const Uuid();

  final LocalStore _local;
  final SupabaseService _supabase;
  final RankingService _ranking;
  final MatchmakingEngine _matchmaking;
  final Uuid _uuid;

  List<Player> _players = [];
  final Set<String> _selectedIds = {};
  MatchmakingResult? _lastMatch;
  bool _lastMatchIsManual = false;
  String? _lastError;
  bool _loading = false;
  Map<
    String,
    ({
      int goals,
      int matches,
      int mvpCount,
      int gkOfMatchCount,
      DateTime? lastMatchAt,
    })
  >
  _aggByPlayerId = const {};

  List<Player> get players => List.unmodifiable(_players);
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  MatchmakingResult? get lastMatch => _lastMatch;
  bool get lastMatchIsManual => _lastMatchIsManual;
  String? get lastError => _lastError;
  bool get isLoading => _loading;
  int goalsForPlayer(String playerId) => _aggByPlayerId[playerId]?.goals ?? 0;
  int mvpCountForPlayer(String playerId) =>
      _aggByPlayerId[playerId]?.mvpCount ?? 0;
  int gkOfMatchCountForPlayer(String playerId) =>
      _aggByPlayerId[playerId]?.gkOfMatchCount ?? 0;
  DateTime? lastMatchAtForPlayer(String playerId) =>
      _aggByPlayerId[playerId]?.lastMatchAt;
  double goalsPerMatchForPlayer(String playerId) {
    final a = _aggByPlayerId[playerId];
    if (a == null || a.matches <= 0) return 0;
    return a.goals / a.matches;
  }

  LocalStore get localStore => _local;

  /// `true` dacă `Supabase.initialize` a rulat (URL + cheie anonimă).
  bool get hasCloudSync => _supabase.isReady;

  /// Încarcă din SQLite, îmbină cu Supabase (remote + jucători doar-local),
  /// persistă lista unificată local și urcă în cloud jucătorii lipsă din remote.
  Future<void> loadPlayers() async {
    _setLoading(true);
    _lastError = null;
    try {
      // #region agent log
      DebugLog.write(
        runId: 'pre-fix',
        hypothesisId: 'H4',
        location: 'simf_controller.dart:loadPlayers',
        message: 'loadPlayers start',
        data: {'cloudReady': _supabase.isReady},
      );
      // #endregion
      var local = await _local.getPlayers();
      if (_supabase.isReady) {
        // Best-effort: sincronizează întâi meciurile rămase local (offline-first).
        try {
          final pending = await _local.getUnsyncedMatches();
          for (final m in pending) {
            final stats = await _local.getStatsForMatch(m.id);
            await _supabase.upsertMatchWithStats(match: m, stats: stats);
            await _local.markMatchSynced(m.id);
          }
        } on SimfException catch (e) {
          _lastError = e.message;
        } catch (e) {
          _lastError = 'Nu s-au putut sincroniza meciurile locale: $e';
        }

        try {
          final remote = await _supabase.fetchPlayers();
          final remoteById = {for (final p in remote) p.id: p};
          final localById = {for (final p in local) p.id: p};
          final allIds = {...remoteById.keys, ...localById.keys};

          Player pickLww(Player? a, Player? b) {
            if (a == null) return b!;
            if (b == null) return a;
            final ta = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final tb = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            // last-write-wins; tie-break: remote wins (stable).
            if (tb.isAfter(ta)) return b;
            if (ta.isAfter(tb)) return a;
            return b;
          }

          final merged = <Player>[
            for (final id in allIds) pickLww(localById[id], remoteById[id]),
          ];
          final deduped = _dedupePlayersByName(merged);
          deduped.sort((a, b) => a.name.compareTo(b.name));
          await _local.replaceAllPlayers(deduped);

          // Push local-newer snapshots to remote (best-effort).
          for (final id in allIds) {
            final lp = localById[id];
            final rp = remoteById[id];
            if (lp == null) continue;
            final tl = lp.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final tr = rp?.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            if (rp == null || tl.isAfter(tr)) {
              try {
                await _supabase.upsertPlayer(lp);
              } on SimfException catch (e) {
                _lastError = e.message;
              } catch (_) {
                // best-effort
              }
            }
          }
          local = deduped;
        } on SimfException catch (e) {
          _lastError = e.message;
        } catch (e) {
          // #region agent log
          DebugLog.write(
            runId: 'pre-fix',
            hypothesisId: 'H3',
            location: 'simf_controller.dart:loadPlayers',
            message: 'Unexpected exception during fetchPlayers/merge',
            data: {'error': e.toString()},
          );
          // #endregion
          _lastError = 'Eroare rețea / TLS la Supabase: $e';
        }

        try {
          await _mergeRemoteMatchesLww();
        } on SimfException catch (e) {
          _lastError = e.message;
        } catch (e) {
          _lastError = 'Nu s-au putut îmbina meciurile din cloud: $e';
        }
      }
      _players = local;
      _aggByPlayerId = await _local.getPlayerAggregates();
    } catch (e, st) {
      _lastError = 'Nu s-au putut încărca jucătorii: $e';
      debugPrintStack(stackTrace: st);
    } finally {
      _setLoading(false);
    }
  }

  Future<Player?> addPlayer({
    required String name,
    required bool isPermanentGk,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;

    final existing = _findByNormalizedName(trimmed);
    if (existing != null) {
      // Nu creăm dubluri: întoarcem jucătorul existent.
      return existing;
    }

    final p = Player(
      id: _uuid.v4(),
      name: trimmed,
      isPermanentGk: isPermanentGk,
      updatedAt: DateTime.now().toUtc(),
    );

    await _local.upsertPlayer(p);
    if (_supabase.isReady) {
      try {
        await _supabase.upsertPlayer(p);
      } on SimfException catch (e) {
        _lastError = e.message;
      }
    }
    _players = [..._players, p]..sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
    return p;
  }

  Future<void> renamePlayer({
    required Player player,
    required String newName,
  }) async {
    await updatePlayer(player: player, newName: newName);
  }

  Future<void> updatePlayer({
    required Player player,
    String? newName,
    bool? isPermanentGk,
  }) async {
    final trimmed = (newName ?? player.name).trim();
    if (trimmed.isEmpty) return;

    final nameChanged = trimmed != player.name;
    final gkChanged =
        (isPermanentGk != null) && (isPermanentGk != player.isPermanentGk);
    if (!nameChanged && !gkChanged) return;

    if (nameChanged) {
      final targetNorm = _normName(trimmed);
      final conflict = _players.firstWhere(
        (p) => p.id != player.id && _normName(p.name) == targetNorm,
        orElse: () => const Player(id: '', name: ''),
      );
      if (conflict.id.isNotEmpty) {
        _lastError = 'Există deja un jucător cu numele "${conflict.name}".';
        notifyListeners();
        return;
      }
    }

    final updated = player.copyWith(
      name: trimmed,
      isPermanentGk: isPermanentGk ?? player.isPermanentGk,
      updatedAt: DateTime.now().toUtc(),
    );

    await _local.upsertPlayer(updated);
    if (_supabase.isReady) {
      try {
        await _supabase.upsertPlayer(updated);
      } on SimfException catch (e) {
        _lastError = e.message;
      }
    }

    _players =
        _players
            .map((p) => p.id == updated.id ? updated : p)
            .toList(growable: false)
          ..sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
  }

  Future<void> deletePlayer(Player player) async {
    await _local.deletePlayer(player.id);
    if (_supabase.isReady) {
      try {
        await _supabase.deletePlayer(player.id);
      } on SimfException catch (e) {
        _lastError = e.message;
      }
    }
    _players = _players.where((e) => e.id != player.id).toList();
    _selectedIds.remove(player.id);
    notifyListeners();
  }

  void toggleSelected(String id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
    } else {
      _selectedIds.add(id);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    notifyListeners();
  }

  void setSelection(Iterable<String> ids) {
    _selectedIds
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  void selectAllVisible() {
    _selectedIds
      ..clear()
      ..addAll(_players.map((e) => e.id));
    notifyListeners();
  }

  /// Rulează motorul de matchmaking pe jucătorii selectați.
  MatchmakingResult generateTeams() {
    final chosen = _players.where((p) => _selectedIds.contains(p.id)).toList();
    if (chosen.length < 2) {
      throw SimfException('Selectează cel puțin 2 jucători pentru meci.');
    }
    _lastMatch = _matchmaking.balanceTeams(chosen);
    _lastMatchIsManual = false;
    notifyListeners();
    return _lastMatch!;
  }

  /// Setează echipele manual (A/B) din rosterul curent.
  ///
  /// Folosit ca “variantă temporară” înainte să ne bazăm pe generator.
  MatchmakingResult setManualTeams({
    required Iterable<String> teamAIds,
    required Iterable<String> teamBIds,
  }) {
    final aSet = teamAIds.toSet();
    final bSet = teamBIds.toSet();
    if (aSet.isEmpty || bSet.isEmpty) {
      throw SimfException(
        'Alege cel puțin 1 jucător în Echipa A și 1 în Echipa B.',
      );
    }
    if (aSet.intersection(bSet).isNotEmpty) {
      throw SimfException('Un jucător nu poate fi în ambele echipe.');
    }

    final byId = {for (final p in _players) p.id: p};
    final teamA = <Player>[
      for (final id in aSet)
        if (byId[id] != null) byId[id]!,
    ];
    final teamB = <Player>[
      for (final id in bSet)
        if (byId[id] != null) byId[id]!,
    ];

    if (teamA.isEmpty || teamB.isEmpty) {
      throw SimfException(
        'Nu am găsit toți jucătorii selectați în rosterul curent.',
      );
    }

    // Păstrăm selecția (utilă dacă revii în ecran).
    _selectedIds
      ..clear()
      ..addAll(aSet)
      ..addAll(bSet);

    final sumA = teamA.fold<double>(0, (s, p) => s + p.mu);
    final sumB = teamB.fold<double>(0, (s, p) => s + p.mu);
    final winA = _ranking.winProbabilityTeamA(teamA: teamA, teamB: teamB);

    _lastMatch = MatchmakingResult(
      teamA: teamA,
      teamB: teamB,
      teamSumMuA: sumA,
      teamSumMuB: sumB,
      winChanceTeamA: winA,
    );
    _lastMatchIsManual = true;
    notifyListeners();
    return _lastMatch!;
  }

  void clearMatch() {
    _lastMatch = null;
    _lastMatchIsManual = false;
    notifyListeners();
  }

  /// Persistă meciul, aplică ratinguri și reîncarcă lista de jucători.
  Future<void> finalizeMatch({
    required int scoreA,
    required int scoreB,
    required List<MatchPlayerStats> stats,
  }) async {
    final match = _lastMatch;
    if (match == null) {
      throw SimfException('Nu există echipe generate pentru acest meci.');
    }

    final now = DateTime.now().toUtc();
    final m = Match(
      id: _uuid.v4(),
      createdAt: now,
      updatedAt: now,
      scoreA: scoreA,
      scoreB: scoreB,
    );
    final withIds = stats
        .map(
          (s) => MatchPlayerStats(
            matchId: m.id,
            playerId: s.playerId,
            team: s.team,
            goals: s.goals,
            isRotationGk: s.isRotationGk,
            receivedMvpVote: s.receivedMvpVote,
            receivedGkVote: s.receivedGkVote,
          ),
        )
        .toList(growable: false);

    final statsMap = {for (final s in stats) s.playerId: s};
    final updated = _ranking.applyMatchToPlayers(
      roster: _players,
      scoreA: scoreA,
      scoreB: scoreB,
      statsByPlayerId: statsMap,
      teamA: match.teamA,
      teamB: match.teamB,
    );

    final updatedWithTs = updated
        .map((p) => p.copyWith(updatedAt: now))
        .toList(growable: false);

    for (final p in updatedWithTs) {
      await _local.upsertPlayer(p);
    }

    // Offline-first: persistăm meciul + statistici local mereu.
    await _local.insertMatchWithStats(match: m, stats: withIds, synced: false);

    if (_supabase.isReady) {
      try {
        await _supabase.upsertPlayers(updatedWithTs);
        await _supabase.upsertMatchWithStats(match: m, stats: withIds);
        await _local.markMatchSynced(m.id);
      } on SimfException catch (e) {
        _lastError = e.message;
      }
    }

    _players = updatedWithTs..sort((a, b) => a.name.compareTo(b.name));
    _aggByPlayerId = await _local.getPlayerAggregates();
    _lastMatch = null;
    _selectedIds.clear();
    notifyListeners();
  }

  Future<void> finalizeExistingMatch({
    required String matchId,
    required int scoreA,
    required int scoreB,
    required List<MatchPlayerStats> stats,
  }) async {
    final match = _lastMatch;
    if (match == null) {
      throw SimfException('Nu există echipe active pentru acest meci.');
    }
    final existing = await _local.getMatchById(matchId);
    if (existing == null) {
      throw SimfException('Nu găsesc meciul draft în baza locală.');
    }

    final now = DateTime.now().toUtc();

    // Persistăm scorul pe match-ul existent (păstrăm createdAt).
    final m = existing.copyWith(scoreA: scoreA, scoreB: scoreB, updatedAt: now);

    final withIds = stats
        .map(
          (s) => MatchPlayerStats(
            matchId: matchId,
            playerId: s.playerId,
            team: s.team,
            goals: s.goals,
            isRotationGk: s.isRotationGk,
            receivedMvpVote: s.receivedMvpVote,
            receivedGkVote: s.receivedGkVote,
          ),
        )
        .toList(growable: false);

    final statsMap = {for (final s in stats) s.playerId: s};
    final updated = _ranking.applyMatchToPlayers(
      roster: _players,
      scoreA: scoreA,
      scoreB: scoreB,
      statsByPlayerId: statsMap,
      teamA: match.teamA,
      teamB: match.teamB,
    );

    final updatedWithTs = updated
        .map((p) => p.copyWith(updatedAt: now))
        .toList(growable: false);

    for (final p in updatedWithTs) {
      await _local.upsertPlayer(p);
    }

    // Update match + stats local (idempotent).
    await _local.insertMatchWithStats(match: m, stats: withIds, synced: false);

    if (_supabase.isReady) {
      try {
        await _supabase.upsertPlayers(updatedWithTs);
        await _supabase.upsertMatchWithStats(match: m, stats: withIds);
        await _local.markMatchSynced(matchId);
      } on SimfException catch (e) {
        _lastError = e.message;
      }
    }

    _players = updatedWithTs..sort((a, b) => a.name.compareTo(b.name));
    _aggByPlayerId = await _local.getPlayerAggregates();
    _lastMatch = null;
    _lastMatchIsManual = false;
    _selectedIds.clear();
    notifyListeners();
  }

  Future<String> saveDraftMatchFromActiveTeams({
    int durationMinutes = Match.defaultDuration,
  }) async {
    final match = _lastMatch;
    if (match == null) {
      throw SimfException('Nu există echipe active.');
    }

    final now = DateTime.now().toUtc();
    final matchId = _uuid.v4();

    final draft = Match(
      id: matchId,
      createdAt: now,
      updatedAt: now,
      scoreA: -1,
      scoreB: -1,
      durationMinutes: durationMinutes,
    );

    final stats = <MatchPlayerStats>[
      for (final p in match.teamA)
        MatchPlayerStats(
          matchId: matchId,
          playerId: p.id,
          team: MatchTeam.a,
          goals: 0,
          isRotationGk: false,
          receivedMvpVote: false,
          receivedGkVote: false,
        ),
      for (final p in match.teamB)
        MatchPlayerStats(
          matchId: matchId,
          playerId: p.id,
          team: MatchTeam.b,
          goals: 0,
          isRotationGk: false,
          receivedMvpVote: false,
          receivedGkVote: false,
        ),
    ];

    await _local.insertMatchWithStats(
      match: draft,
      stats: stats,
      synced: false,
    );
    return matchId;
  }

  Future<void> activateTeamsFromLocalMatch(String matchId) async {
    final stats = await _local.getStatsForMatch(matchId);
    if (stats.isEmpty) {
      throw SimfException('Nu există componență pentru acest meci.');
    }
    final byId = {for (final p in _players) p.id: p};
    final teamAIds = stats
        .where((s) => s.team == MatchTeam.a)
        .map((s) => s.playerId);
    final teamBIds = stats
        .where((s) => s.team == MatchTeam.b)
        .map((s) => s.playerId);
    final teamA = <Player>[
      for (final id in teamAIds)
        if (byId[id] != null) byId[id]!,
    ];
    final teamB = <Player>[
      for (final id in teamBIds)
        if (byId[id] != null) byId[id]!,
    ];
    if (teamA.isEmpty || teamB.isEmpty) {
      throw SimfException('Nu am găsit jucătorii acestui meci în roster.');
    }
    final sumA = teamA.fold<double>(0, (s, p) => s + p.mu);
    final sumB = teamB.fold<double>(0, (s, p) => s + p.mu);
    final winA = _ranking.winProbabilityTeamA(teamA: teamA, teamB: teamB);
    _lastMatch = MatchmakingResult(
      teamA: teamA,
      teamB: teamB,
      teamSumMuA: sumA,
      teamSumMuB: sumB,
      winChanceTeamA: winA,
    );
    _lastMatchIsManual = true;
    notifyListeners();
  }

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }

  /// Îmbină meciurile remote cu SQLite (LWW pe `updated_at` / `created_at`).
  Future<void> _mergeRemoteMatchesLww() async {
    final remoteMatches = await _supabase.fetchMatches();
    final allStats = await _supabase.fetchAllMatchPlayerStats();
    final statsByMatchId = <String, List<MatchPlayerStats>>{};
    for (final s in allStats) {
      statsByMatchId.putIfAbsent(s.matchId, () => []).add(s);
    }

    final localRows = await _local.getAllMatchesWithSync();
    final localById = {for (final r in localRows) r.match.id: r};

    for (final r in remoteMatches) {
      final remoteStats = statsByMatchId[r.id] ?? const <MatchPlayerStats>[];
      final localRow = localById[r.id];
      if (localRow == null) {
        await _local.replaceMatchAndStats(
          match: r,
          stats: remoteStats,
          synced: true,
        );
        continue;
      }

      final local = localRow.match;
      final tl = (local.updatedAt ?? local.createdAt).toUtc();
      final tr = (r.updatedAt ?? r.createdAt).toUtc();

      if (!tr.isBefore(tl)) {
        await _local.replaceMatchAndStats(
          match: r,
          stats: remoteStats,
          synced: true,
        );
      } else if (localRow.synced) {
        try {
          final localStats = await _local.getStatsForMatch(local.id);
          await _supabase.upsertMatchWithStats(match: local, stats: localStats);
        } on SimfException catch (e) {
          _lastError = e.message;
        } catch (_) {
          // best-effort
        }
      }
    }
  }

  Future<void> devSeedDemo({int playersCount = 14}) async {
    if (!kDebugMode) return;

    _setLoading(true);
    try {
      final r = math.Random(1337);

      final existingNames = _players
          .map((p) => p.name.trim().toLowerCase())
          .toSet();

      final created = <Player>[];
      for (var i = 1; i <= playersCount; i++) {
        final name = 'Demo ${i.toString().padLeft(2, '0')}';
        if (existingNames.contains(name.toLowerCase())) continue;

        final isPermGk = (i == 1 || i == 2);
        final mu = 18.0 + r.nextDouble() * 14.0;
        final sigma = 5.5 + r.nextDouble() * 3.0;

        final p = Player(
          id: _uuid.v4(),
          name: name,
          mu: mu,
          sigma: sigma,
          isPermanentGk: isPermGk,
          matchesPlayed: 0,
        );
        await _local.upsertPlayer(p);
        created.add(p);

        if (_supabase.isReady) {
          try {
            await _supabase.upsertPlayer(p);
          } catch (_) {
            // best-effort
          }
        }
      }

      final roster = [..._players, ...created]
        ..sort((a, b) => a.name.compareTo(b.name));
      _players = roster;

      final participants = roster
          .where((p) => p.name.toLowerCase().startsWith('demo '))
          .take(playersCount)
          .toList(growable: false);
      if (participants.length < 2) return;

      final teams = _matchmaking.balanceTeams(participants);
      final scoreA = 5;
      final scoreB = 4;

      final matchId = _uuid.v4();
      final mNow = DateTime.now().toUtc();
      final m = Match(
        id: matchId,
        createdAt: mNow,
        updatedAt: mNow,
        scoreA: scoreA,
        scoreB: scoreB,
      );

      final stats = <MatchPlayerStats>[];
      var remainingA = scoreA;
      var remainingB = scoreB;

      for (var i = 0; i < teams.teamA.length; i++) {
        final p = teams.teamA[i];
        final g = i == 0
            ? 2
            : (remainingA > 0 && r.nextDouble() < 0.45 ? 1 : 0);
        final goals = g.clamp(0, remainingA);
        remainingA -= goals;
        stats.add(
          MatchPlayerStats(
            matchId: matchId,
            playerId: p.id,
            team: MatchTeam.a,
            goals: goals,
            isRotationGk: !p.isPermanentGk && i == 1,
            receivedMvpVote: i == 0,
            receivedGkVote: (!p.isPermanentGk && i == 1),
          ),
        );
      }
      for (var i = 0; i < teams.teamB.length; i++) {
        final p = teams.teamB[i];
        final g = i == 0
            ? 2
            : (remainingB > 0 && r.nextDouble() < 0.45 ? 1 : 0);
        final goals = g.clamp(0, remainingB);
        remainingB -= goals;
        stats.add(
          MatchPlayerStats(
            matchId: matchId,
            playerId: p.id,
            team: MatchTeam.b,
            goals: goals,
            isRotationGk: !p.isPermanentGk && i == 1,
            receivedMvpVote: i == 0,
          ),
        );
      }
      if (remainingA > 0) {
        final idx = stats.indexWhere((s) => s.team == MatchTeam.a);
        if (idx >= 0) {
          stats[idx] = stats[idx].copyWith(
            goals: stats[idx].goals + remainingA,
          );
        }
      }
      if (remainingB > 0) {
        final idx = stats.indexWhere((s) => s.team == MatchTeam.b);
        if (idx >= 0) {
          stats[idx] = stats[idx].copyWith(
            goals: stats[idx].goals + remainingB,
          );
        }
      }

      await _local.insertMatchWithStats(match: m, stats: stats, synced: false);

      final statsById = {for (final s in stats) s.playerId: s};
      final updated = _ranking.applyMatchToPlayers(
        roster: roster,
        scoreA: scoreA,
        scoreB: scoreB,
        statsByPlayerId: statsById,
        teamA: teams.teamA,
        teamB: teams.teamB,
      );
      for (final p in updated) {
        await _local.upsertPlayer(p);
      }
      if (_supabase.isReady) {
        try {
          await _supabase.upsertPlayers(updated);
          await _supabase.upsertMatchWithStats(match: m, stats: stats);
          await _local.markMatchSynced(matchId);
        } catch (_) {
          // best-effort
        }
      }

      _players = updated..sort((a, b) => a.name.compareTo(b.name));
      _aggByPlayerId = await _local.getPlayerAggregates();
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> devClearDemoSeed() async {
    if (!kDebugMode) return;
    _setLoading(true);
    try {
      await _local.deleteDemoSeed();
      _players = await _local.getPlayers();
      _aggByPlayerId = await _local.getPlayerAggregates();
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> devResetAllLocalData() async {
    if (!kDebugMode) return;
    _setLoading(true);
    _lastError = null;
    try {
      await _local.clearAllData();
      _players = const [];
      _aggByPlayerId = const {};
      _selectedIds.clear();
      _lastMatch = null;
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> devCleanupDuplicatePlayersInCloud() async {
    if (!kDebugMode) return;
    if (!_supabase.isReady) {
      _lastError = 'Cleanup cloud: Supabase nu este configurat.';
      notifyListeners();
      return;
    }
    _setLoading(true);
    _lastError = null;
    try {
      final remotePlayers = await _supabase.fetchPlayers();
      final remoteStats = await _supabase.fetchAllMatchPlayerStats();

      // Group by normalized name.
      final groups = <String, List<Player>>{};
      for (final p in remotePlayers) {
        final key = _normName(p.name);
        (groups[key] ??= <Player>[]).add(p);
      }

      // Index stats by player and detect match conflicts for reassignment.
      final matchIdsByPlayer = <String, Set<String>>{};
      for (final s in remoteStats) {
        matchIdsByPlayer
            .putIfAbsent(s.playerId, () => <String>{})
            .add(s.matchId);
      }

      var deleted = 0;
      var reassigned = 0;
      var skipped = 0;

      for (final entry in groups.entries) {
        final list = entry.value;
        if (list.length <= 1) continue;

        list.sort((a, b) {
          final ta = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final tb = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return tb.compareTo(ta); // newest first
        });
        final winner = list.first;
        final losers = list.skip(1).toList(growable: false);

        final winnerMatches = matchIdsByPlayer[winner.id] ?? <String>{};

        for (final loser in losers) {
          final loserMatches = matchIdsByPlayer[loser.id] ?? <String>{};
          // Dacă winner și loser apar în același meci, reasignarea ar crea conflict PK.
          if (winnerMatches.intersection(loserMatches).isNotEmpty) {
            skipped++;
            continue;
          }

          if (loserMatches.isNotEmpty) {
            await _supabase.reassignMatchPlayerStatsPlayerId(
              fromPlayerId: loser.id,
              toPlayerId: winner.id,
            );
            reassigned++;
            winnerMatches.addAll(loserMatches);
          }

          await _supabase.deletePlayer(loser.id);
          deleted++;
        }
      }

      await loadPlayers();
      _lastError = null;
      DebugLog.write(
        runId: 'pre-fix',
        hypothesisId: 'H-CLEANUP',
        location: 'simf_controller.dart:devCleanupDuplicatePlayersInCloud',
        message: 'cloud duplicate cleanup done',
        data: {
          'deleted': deleted,
          'reassigned': reassigned,
          'skipped': skipped,
        },
      );
    } on SimfException catch (e) {
      _lastError = e.message;
    } catch (e) {
      _lastError = 'Cleanup cloud eșuat: $e';
    } finally {
      _setLoading(false);
    }
  }

  String _stripDiacritics(String s) {
    return s
        .replaceAll('ă', 'a')
        .replaceAll('â', 'a')
        .replaceAll('î', 'i')
        .replaceAll('ș', 's')
        .replaceAll('ş', 's')
        .replaceAll('ț', 't')
        .replaceAll('ţ', 't')
        .replaceAll('Ă', 'A')
        .replaceAll('Â', 'A')
        .replaceAll('Î', 'I')
        .replaceAll('Ș', 'S')
        .replaceAll('Ş', 'S')
        .replaceAll('Ț', 'T')
        .replaceAll('Ţ', 'T');
  }

  String _normName(String s) {
    final cleaned = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    return _stripDiacritics(cleaned).toLowerCase();
  }

  Player? _findByNormalizedName(String name) {
    final key = _normName(name);
    for (final p in _players) {
      if (_normName(p.name) == key) return p;
    }
    return null;
  }

  List<Player> _dedupePlayersByName(List<Player> players) {
    // Unicitate pe nume normalizat: păstrăm varianta cu updated_at mai nou;
    // la egalitate păstrăm prima (stabil).
    final byKey = <String, Player>{};
    for (final p in players) {
      final key = _normName(p.name);
      final cur = byKey[key];
      if (cur == null) {
        byKey[key] = p;
        continue;
      }
      final tc = cur.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tp = p.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (tp.isAfter(tc)) byKey[key] = p;
    }
    return byKey.values.toList(growable: false);
  }
}
