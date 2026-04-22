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
  })  : _local = localStore,
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
  String? _lastError;
  bool _loading = false;

  List<Player> get players => List.unmodifiable(_players);
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  MatchmakingResult? get lastMatch => _lastMatch;
  String? get lastError => _lastError;
  bool get isLoading => _loading;

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
        try {
          final remote = await _supabase.fetchPlayers();
          final remoteById = {for (final p in remote) p.id: p};
          final remoteIds = remoteById.keys.toSet();

          // Remote ca sursă pentru aceleași id-uri; păstrăm jucători existenți doar pe device.
          final merged = <Player>[
            ...remote,
            for (final lp in local)
              if (!remoteIds.contains(lp.id)) lp,
          ];
          merged.sort((a, b) => a.name.compareTo(b.name));
          await _local.replaceAllPlayers(merged);

          for (final p in merged) {
            if (!remoteIds.contains(p.id)) {
              try {
                await _supabase.upsertPlayer(p);
              } on SimfException catch (e) {
                _lastError = e.message;
              }
            }
          }
          local = merged;
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
      }
      _players = local;
    } catch (e, st) {
      _lastError = 'Nu s-au putut încărca jucătorii: $e';
      debugPrintStack(stackTrace: st);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> addPlayer({
    required String name,
    required bool isPermanentGk,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final p = Player(
      id: _uuid.v4(),
      name: trimmed,
      isPermanentGk: isPermanentGk,
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
    notifyListeners();
    return _lastMatch!;
  }

  void clearMatch() {
    _lastMatch = null;
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

    final statsMap = {for (final s in stats) s.playerId: s};
    final updated = _ranking.applyMatchToPlayers(
      roster: _players,
      scoreA: scoreA,
      scoreB: scoreB,
      statsByPlayerId: statsMap,
      teamA: match.teamA,
      teamB: match.teamB,
    );

    for (final p in updated) {
      await _local.upsertPlayer(p);
    }
    if (_supabase.isReady) {
      try {
        await _supabase.upsertPlayers(updated);
        final m = Match(
          id: _uuid.v4(),
          createdAt: DateTime.now().toUtc(),
          scoreA: scoreA,
          scoreB: scoreB,
        );
        final withIds = stats
            .map((s) => MatchPlayerStats(
                  matchId: m.id,
                  playerId: s.playerId,
                  team: s.team,
                  goals: s.goals,
                  saves: s.saves,
                  isRotationGk: s.isRotationGk,
                  receivedMvpVote: s.receivedMvpVote,
                  cleanSheet: s.cleanSheet,
                ))
            .toList();
        await _supabase.insertMatchWithStats(match: m, stats: withIds);
      } on SimfException catch (e) {
        _lastError = e.message;
      }
    }

    _players = updated..sort((a, b) => a.name.compareTo(b.name));
    _lastMatch = null;
    _selectedIds.clear();
    notifyListeners();
  }

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }
}
