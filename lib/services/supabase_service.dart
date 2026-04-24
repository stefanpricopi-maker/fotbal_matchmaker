import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/debug_log.dart';
import '../core/simf_exception.dart';
import '../models/models.dart';

/// Acces la tabelele `players`, `matches`, `match_player_stats` din Supabase.
///
/// Dacă aplicația nu este inițializată cu URL + cheie anonimă, metodele semnalează
/// clar o [SimfException] — fluxul UI poate continua doar cu [LocalStore].
class SupabaseService {
  static String _pgDetail(PostgrestException e) {
    final parts = <String>[];
    if (e.code != null && e.code!.trim().isNotEmpty) {
      parts.add('code ${e.code}');
    }
    if (e.message.trim().isNotEmpty) parts.add(e.message.trim());
    final d = e.details?.toString().trim();
    if (d != null && d.isNotEmpty) parts.add('details: $d');
    final h = e.hint?.toString().trim();
    if (h != null && h.isNotEmpty) parts.add('hint: $h');
    return parts.isEmpty ? e.toString() : parts.join(' — ');
  }

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  bool get isReady => _client != null;

  void _requireClient() {
    if (_client == null) {
      throw SimfException(
        'Supabase nu este inițializat. Setează SUPABASE_URL și '
        'SUPABASE_ANON_KEY (dart-define) sau omit sincronizarea cloud.',
      );
    }
  }

  /// Încarcă toți jucătorii din cloud (ordonat după nume).
  Future<List<Player>> fetchPlayers() async {
    _requireClient();
    try {
      // #region agent log
      DebugLog.write(
        runId: 'pre-fix',
        hypothesisId: 'H1',
        location: 'supabase_service.dart:fetchPlayers',
        message: 'fetchPlayers start',
        data: const {'table': 'players'},
      );
      // #endregion
      final rows = await _client!.from('players').select().order('name');
      final list = rows as List<dynamic>;
      return list
          .map((e) => Player.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } on PostgrestException catch (e) {
      // #region agent log
      DebugLog.write(
        runId: 'pre-fix',
        hypothesisId: 'H2',
        location: 'supabase_service.dart:fetchPlayers',
        message: 'PostgrestException',
        data: {
          'code': e.code,
          'message': e.message,
          'details': e.details?.toString(),
          'hint': e.hint?.toString(),
        },
      );
      // #endregion
      throw SimfException(
        'Eroare la citirea jucătorilor din Supabase: ${_pgDetail(e)}',
        e,
      );
    } catch (e) {
      // #region agent log
      DebugLog.write(
        runId: 'pre-fix',
        hypothesisId: 'H3',
        location: 'supabase_service.dart:fetchPlayers',
        message: 'Non-Postgrest exception (likely network/TLS)',
        data: {'error': e.toString()},
      );
      // #endregion
      rethrow;
    }
  }

  Future<void> upsertPlayer(Player player) async {
    _requireClient();
    try {
      await _client!.from('players').upsert(player.toJson());
    } on PostgrestException catch (e) {
      throw SimfException(
        'Nu s-a putut salva jucătorul în Supabase: ${_pgDetail(e)}',
        e,
      );
    }
  }

  /// Upsert în lot (finalize meci — mai puține round-trip-uri).
  Future<void> upsertPlayers(List<Player> players) async {
    if (players.isEmpty) return;
    _requireClient();
    try {
      await _client!.from('players').upsert(
            players.map((p) => p.toJson()).toList(),
          );
    } on PostgrestException catch (e) {
      throw SimfException(
        'Nu s-au putut sincroniza jucătorii în Supabase: ${_pgDetail(e)}',
        e,
      );
    }
  }

  Future<void> deletePlayer(String id) async {
    _requireClient();
    try {
      await _client!.from('players').delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw SimfException(
        'Ștergerea jucătorului din Supabase a eșuat: ${_pgDetail(e)}',
        e,
      );
    }
  }

  /// Upsert meci + statistici (idempotent la reîncercări / LWW).
  Future<void> upsertMatchWithStats({
    required Match match,
    required List<MatchPlayerStats> stats,
  }) async {
    _requireClient();
    try {
      await _client!.from('matches').upsert(match.toJson());
    } on PostgrestException catch (e) {
      throw SimfException(
        'Salvare meci în Supabase eșuată: ${_pgDetail(e)}',
        e,
      );
    }
    if (stats.isEmpty) return;
    try {
      await _client!.from('match_player_stats').upsert(
            stats.map((s) => s.toJson()).toList(),
          );
    } on PostgrestException catch (e) {
      await _client!.from('matches').delete().eq('id', match.id);
      throw SimfException(
        'Statisticile nu s-au putut salva; meciul a fost anulat în cloud: '
        '${_pgDetail(e)}',
        e,
      );
    }
  }

  Future<List<Match>> fetchMatches() async {
    _requireClient();
    try {
      final rows = await _client!.from('matches').select().order('created_at');
      final list = rows as List<dynamic>;
      return list
          .map((e) => Match.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } on PostgrestException catch (e) {
      throw SimfException(
        'Eroare la citirea meciurilor din Supabase: ${_pgDetail(e)}',
        e,
      );
    }
  }

  Future<List<MatchPlayerStats>> fetchAllMatchPlayerStats() async {
    _requireClient();
    try {
      final rows = await _client!.from('match_player_stats').select();
      final list = rows as List<dynamic>;
      return list
          .map(
            (e) =>
                MatchPlayerStats.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw SimfException(
        'Eroare la citirea statisticilor de meci din Supabase: ${_pgDetail(e)}',
        e,
      );
    }
  }
}
