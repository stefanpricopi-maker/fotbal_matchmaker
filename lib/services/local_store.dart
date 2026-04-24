import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

/// Persistență locală SQLite (specificație 4.2 — sincronizare offline-first).
///
/// Stochează jucători local; integrarea cu `SupabaseService` poate urca
/// modificările când rețeaua revine.
class LocalStore {
  LocalStore._(this._db);

  final Database _db;

  static const _dbName = 'simf.db';
  static const _v7 = 7;

  static Future<LocalStore> open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, _dbName);
    final db = await openDatabase(
      path,
      version: _v7,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE players (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  mu REAL NOT NULL,
  sigma REAL NOT NULL,
  is_permanent_gk INTEGER NOT NULL,
  matches_played INTEGER NOT NULL,
  updated_at TEXT
);
''');

        await db.execute('''
CREATE TABLE matches (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL,
  score_a INTEGER NOT NULL,
  score_b INTEGER NOT NULL,
  duration_minutes INTEGER NOT NULL,
  updated_at TEXT,
  synced INTEGER NOT NULL
);
''');

        await db.execute('''
CREATE TABLE match_player_stats (
  match_id TEXT NOT NULL,
  player_id TEXT NOT NULL,
  team TEXT NOT NULL,
  goals INTEGER NOT NULL,
  is_rotation_gk INTEGER NOT NULL,
  received_mvp_vote INTEGER NOT NULL,
  received_gk_vote INTEGER NOT NULL,
  synced INTEGER NOT NULL,
  PRIMARY KEY (match_id, player_id),
  FOREIGN KEY (match_id) REFERENCES matches (id) ON DELETE CASCADE
);
''');

        await db.execute('''
CREATE TABLE player_aliases (
  alias TEXT PRIMARY KEY,
  player_id TEXT NOT NULL
);
''');
      },
      onConfigure: (db) async {
        // Required for FOREIGN KEY constraints (SQLite).
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
CREATE TABLE IF NOT EXISTS matches (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL,
  score_a INTEGER NOT NULL,
  score_b INTEGER NOT NULL,
  duration_minutes INTEGER NOT NULL,
  synced INTEGER NOT NULL
);
''');
          await db.execute('''
CREATE TABLE IF NOT EXISTS match_player_stats (
  match_id TEXT NOT NULL,
  player_id TEXT NOT NULL,
  team TEXT NOT NULL,
  goals INTEGER NOT NULL,
  saves INTEGER NOT NULL,
  is_rotation_gk INTEGER NOT NULL,
  received_mvp_vote INTEGER NOT NULL,
  received_gk_vote INTEGER NOT NULL,
  clean_sheet INTEGER NOT NULL,
  synced INTEGER NOT NULL,
  PRIMARY KEY (match_id, player_id),
  FOREIGN KEY (match_id) REFERENCES matches (id) ON DELETE CASCADE
);
''');
        }
        if (oldVersion < 3) {
          await db.execute('''
CREATE TABLE IF NOT EXISTS player_aliases (
  alias TEXT PRIMARY KEY,
  player_id TEXT NOT NULL
);
''');
        }
        if (oldVersion < 4) {
          // add column for goalkeeper of match vote
          await db.execute(
            'ALTER TABLE match_player_stats ADD COLUMN received_gk_vote INTEGER NOT NULL DEFAULT 0;',
          );
        }
        if (oldVersion < 5) {
          await db.execute('ALTER TABLE players ADD COLUMN updated_at TEXT;');
          // Backfill: treat existing rows as "now" so merge doesn't wipe them.
          await db.execute(
            "UPDATE players SET updated_at = COALESCE(updated_at, datetime('now'))",
          );
        }
        if (oldVersion < 6) {
          await db.execute('ALTER TABLE matches ADD COLUMN updated_at TEXT;');
          await db.execute(
            'UPDATE matches SET updated_at = COALESCE(updated_at, created_at)',
          );
        }
        if (oldVersion < 7) {
          await db.execute('''
CREATE TABLE match_player_stats_new (
  match_id TEXT NOT NULL,
  player_id TEXT NOT NULL,
  team TEXT NOT NULL,
  goals INTEGER NOT NULL,
  is_rotation_gk INTEGER NOT NULL,
  received_mvp_vote INTEGER NOT NULL,
  received_gk_vote INTEGER NOT NULL,
  synced INTEGER NOT NULL,
  PRIMARY KEY (match_id, player_id),
  FOREIGN KEY (match_id) REFERENCES matches (id) ON DELETE CASCADE
);
''');
          await db.execute('''
INSERT INTO match_player_stats_new (
  match_id, player_id, team, goals,
  is_rotation_gk, received_mvp_vote, received_gk_vote, synced
)
SELECT
  match_id, player_id, team, goals,
  is_rotation_gk, received_mvp_vote, received_gk_vote, synced
FROM match_player_stats;
''');
          await db.execute('DROP TABLE match_player_stats;');
          await db.execute(
            'ALTER TABLE match_player_stats_new RENAME TO match_player_stats;',
          );
        }
      },
    );
    return LocalStore._(db);
  }

  Future<List<Player>> getPlayers() async {
    final rows = await _db.query('players', orderBy: 'name COLLATE NOCASE');
    return rows.map(_rowToPlayer).toList();
  }

  Future<void> upsertPlayer(Player player) async {
    await _db.insert(
      'players',
      _playerToRow(player),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deletePlayer(String id) async {
    await _db.delete('players', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> replaceAllPlayers(List<Player> players) async {
    await _db.transaction((txn) async {
      await txn.delete('players');
      for (final p in players) {
        await txn.insert('players', _playerToRow(p));
      }
    });
  }

  Future<int> deleteDemoSeed() async {
    // Ștergem jucătorii Demo + meciurile care îi conțin (dev only).
    return _db.transaction((txn) async {
      final demoPlayers = await txn.query(
        'players',
        columns: ['id'],
        where: 'LOWER(name) LIKE ?',
        whereArgs: ['demo %'],
      );
      final demoIds =
          demoPlayers.map((r) => r['id']! as String).toList(growable: false);
      if (demoIds.isEmpty) return 0;

      // Matches care conțin demo players.
      final inArgs = List.filled(demoIds.length, '?').join(',');
      final matchRows = await txn.rawQuery(
        'SELECT DISTINCT match_id FROM match_player_stats WHERE player_id IN ($inArgs)',
        demoIds,
      );
      final matchIds = matchRows
          .map((r) => r['match_id'] as String)
          .toList(growable: false);

      if (matchIds.isNotEmpty) {
        final inMatches = List.filled(matchIds.length, '?').join(',');
        await txn.delete(
          'match_player_stats',
          where: 'match_id IN ($inMatches)',
          whereArgs: matchIds,
        );
        await txn.delete(
          'matches',
          where: 'id IN ($inMatches)',
          whereArgs: matchIds,
        );
      }

      await txn.delete(
        'player_aliases',
        where: 'player_id IN ($inArgs)',
        whereArgs: demoIds,
      );
      final deletedPlayers = await txn.delete(
        'players',
        where: 'id IN ($inArgs)',
        whereArgs: demoIds,
      );
      return deletedPlayers;
    });
  }

  Future<void> insertMatchWithStats({
    required Match match,
    required List<MatchPlayerStats> stats,
    required bool synced,
  }) async {
    await _db.transaction((txn) async {
      await txn.insert(
        'matches',
        {
          'id': match.id,
          'created_at': match.createdAt.toUtc().toIso8601String(),
          'score_a': match.scoreA,
          'score_b': match.scoreB,
          'duration_minutes': match.durationMinutes,
          'updated_at': (match.updatedAt ?? match.createdAt)
              .toUtc()
              .toIso8601String(),
          'synced': synced ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (final s in stats) {
        await txn.insert(
          'match_player_stats',
          {
            'match_id': match.id,
            'player_id': s.playerId,
            'team': s.team.dbValue,
            'goals': s.goals,
            'is_rotation_gk': s.isRotationGk ? 1 : 0,
            'received_mvp_vote': s.receivedMvpVote ? 1 : 0,
            'received_gk_vote': s.receivedGkVote ? 1 : 0,
            'synced': synced ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Șterge complet meciul + statisticile, apoi le re-inserează (ex.: remote LWW).
  Future<void> replaceMatchAndStats({
    required Match match,
    required List<MatchPlayerStats> stats,
    required bool synced,
  }) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'match_player_stats',
        where: 'match_id = ?',
        whereArgs: [match.id],
      );
      await txn.delete('matches', where: 'id = ?', whereArgs: [match.id]);
      await txn.insert(
        'matches',
        {
          'id': match.id,
          'created_at': match.createdAt.toUtc().toIso8601String(),
          'score_a': match.scoreA,
          'score_b': match.scoreB,
          'duration_minutes': match.durationMinutes,
          'updated_at': (match.updatedAt ?? match.createdAt)
              .toUtc()
              .toIso8601String(),
          'synced': synced ? 1 : 0,
        },
      );
      for (final s in stats) {
        await txn.insert(
          'match_player_stats',
          {
            'match_id': match.id,
            'player_id': s.playerId,
            'team': s.team.dbValue,
            'goals': s.goals,
            'is_rotation_gk': s.isRotationGk ? 1 : 0,
            'received_mvp_vote': s.receivedMvpVote ? 1 : 0,
            'received_gk_vote': s.receivedGkVote ? 1 : 0,
            'synced': synced ? 1 : 0,
          },
        );
      }
    });
  }

  Future<void> markMatchSynced(String matchId) async {
    await _db.transaction((txn) async {
      await txn.update(
        'matches',
        {'synced': 1},
        where: 'id = ?',
        whereArgs: [matchId],
      );
      await txn.update(
        'match_player_stats',
        {'synced': 1},
        where: 'match_id = ?',
        whereArgs: [matchId],
      );
    });
  }

  Future<List<Match>> getUnsyncedMatches() async {
    final rows = await _db.query(
      'matches',
      where: 'synced = 0',
      orderBy: 'created_at ASC',
    );
    return rows.map(_matchFromTableRow).toList(growable: false);
  }

  Future<List<({Match match, bool synced})>> getAllMatchesWithSync() async {
    final rows = await _db.query('matches', orderBy: 'created_at ASC');
    return rows
        .map((r) {
          final match = _matchFromTableRow(r);
          final synced = (r['synced']! as int) != 0;
          return (match: match, synced: synced);
        })
        .toList(growable: false);
  }

  Future<List<({Match match, bool synced})>> getRecentMatches({
    int limit = 50,
  }) async {
    final rows = await _db.query(
      'matches',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows
        .map((r) {
          final match = _matchFromTableRow(r);
          final synced = (r['synced']! as int) != 0;
          return (match: match, synced: synced);
        })
        .toList(growable: false);
  }

  Future<List<MatchPlayerStats>> getStatsForMatch(String matchId) async {
    final rows = await _db.query(
      'match_player_stats',
      where: 'match_id = ?',
      whereArgs: [matchId],
      orderBy: 'team ASC, player_id ASC',
    );
    return rows
        .map(
          (r) => MatchPlayerStats(
            matchId: r['match_id']! as String,
            playerId: r['player_id']! as String,
            team: MatchTeam.fromDb(r['team']! as String),
            goals: (r['goals']! as num).toInt(),
            isRotationGk: (r['is_rotation_gk']! as int) != 0,
            receivedMvpVote: (r['received_mvp_vote']! as int) != 0,
            receivedGkVote: (r['received_gk_vote']! as int) != 0,
          ),
        )
        .toList(growable: false);
  }

  /// Istoric meciuri pentru un jucător, paginat (ORDER BY meci desc).
  Future<List<({Match match, MatchPlayerStats stat, bool synced})>>
      getPlayerMatchHistoryPage({
    required String playerId,
    required int limit,
    required int offset,
  }) async {
    final rows = await _db.rawQuery(
      '''
SELECT
  m.id AS m_id,
  m.created_at AS m_created_at,
  m.score_a AS m_score_a,
  m.score_b AS m_score_b,
  m.duration_minutes AS m_duration,
  m.updated_at AS m_updated_at,
  m.synced AS m_synced,
  s.team AS s_team,
  s.player_id AS s_player_id,
  s.goals AS s_goals,
  s.is_rotation_gk AS s_rot_gk,
  s.received_mvp_vote AS s_mvp,
  s.received_gk_vote AS s_gk_vote
FROM match_player_stats s
INNER JOIN matches m ON m.id = s.match_id
WHERE s.player_id = ?
ORDER BY datetime(m.created_at) DESC
LIMIT ? OFFSET ?
''',
      [playerId, limit, offset],
    );

    return rows
        .map((r) {
          final match = _matchFromHistoryJoinRow(r);
          final stat = MatchPlayerStats(
            matchId: r['m_id']! as String,
            playerId: r['s_player_id']! as String,
            team: MatchTeam.fromDb(r['s_team']! as String),
            goals: (r['s_goals']! as num).toInt(),
            isRotationGk: (r['s_rot_gk']! as int) != 0,
            receivedMvpVote: (r['s_mvp']! as int) != 0,
            receivedGkVote: (r['s_gk_vote']! as int) != 0,
          );
          final synced = (r['m_synced']! as int) != 0;
          return (match: match, stat: stat, synced: synced);
        })
        .toList(growable: false);
  }

  Future<Map<String, int>> getGoalsByPlayerId() async {
    final rows = await _db.rawQuery(
      '''
SELECT player_id, COALESCE(SUM(goals), 0) AS goals_sum
FROM match_player_stats
GROUP BY player_id
''',
    );
    final out = <String, int>{};
    for (final r in rows) {
      final id = r['player_id'] as String;
      final g = (r['goals_sum'] as num?)?.toInt() ?? 0;
      out[id] = g;
    }
    return out;
  }

  /// Agregate per jucător, din istoricul local de meciuri.
  ///
  /// Returnează doar jucătorii care apar în `match_player_stats`.
  Future<Map<String, ({
    int goals,
    int matches,
    int mvpCount,
    int gkOfMatchCount,
    DateTime? lastMatchAt,
  })>> getPlayerAggregates() async {
    final rows = await _db.rawQuery(
      '''
SELECT
  s.player_id AS player_id,
  COALESCE(SUM(s.goals), 0) AS goals_sum,
  COUNT(*) AS matches_cnt,
  COALESCE(SUM(s.received_mvp_vote), 0) AS mvp_cnt,
  COALESCE(SUM(s.received_gk_vote), 0) AS gk_cnt,
  MAX(m.created_at) AS last_match_at
FROM match_player_stats s
LEFT JOIN matches m ON m.id = s.match_id
GROUP BY s.player_id
''',
    );

    final out = <String, ({
      int goals,
      int matches,
      int mvpCount,
      int gkOfMatchCount,
      DateTime? lastMatchAt,
    })>{};

    for (final r in rows) {
      final id = r['player_id'] as String;
      final goals = (r['goals_sum'] as num?)?.toInt() ?? 0;
      final matches = (r['matches_cnt'] as num?)?.toInt() ?? 0;
      final mvpCount = (r['mvp_cnt'] as num?)?.toInt() ?? 0;
      final gkCount = (r['gk_cnt'] as num?)?.toInt() ?? 0;
      final lastRaw = r['last_match_at'] as String?;
      final last = lastRaw == null ? null : DateTime.tryParse(lastRaw);
      out[id] = (
        goals: goals,
        matches: matches,
        mvpCount: mvpCount,
        gkOfMatchCount: gkCount,
        lastMatchAt: last,
      );
    }
    return out;
  }

  Future<String?> resolveAliasToPlayerId(String alias) async {
    final rows = await _db.query(
      'player_aliases',
      columns: ['player_id'],
      where: 'alias = ?',
      whereArgs: [alias],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['player_id'] as String?;
  }

  Future<void> upsertAlias({
    required String alias,
    required String playerId,
  }) async {
    await _db.insert(
      'player_aliases',
      {'alias': alias, 'player_id': playerId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Match _matchFromTableRow(Map<String, Object?> r) {
    final updatedRaw = r['updated_at'] as String?;
    return Match(
      id: r['id']! as String,
      createdAt: DateTime.parse(r['created_at']! as String),
      scoreA: (r['score_a']! as num).toInt(),
      scoreB: (r['score_b']! as num).toInt(),
      durationMinutes: (r['duration_minutes']! as num).toInt(),
      updatedAt: updatedRaw != null ? DateTime.tryParse(updatedRaw) : null,
    );
  }

  Match _matchFromHistoryJoinRow(Map<String, Object?> r) {
    final updatedRaw = r['m_updated_at'] as String?;
    return Match(
      id: r['m_id']! as String,
      createdAt: DateTime.parse(r['m_created_at']! as String),
      scoreA: (r['m_score_a']! as num).toInt(),
      scoreB: (r['m_score_b']! as num).toInt(),
      durationMinutes: (r['m_duration']! as num).toInt(),
      updatedAt: updatedRaw != null ? DateTime.tryParse(updatedRaw) : null,
    );
  }

  Map<String, Object?> _playerToRow(Player p) => {
        'id': p.id,
        'name': p.name,
        'mu': p.mu,
        'sigma': p.sigma,
        'is_permanent_gk': p.isPermanentGk ? 1 : 0,
        'matches_played': p.matchesPlayed,
        'updated_at': p.updatedAt?.toUtc().toIso8601String(),
      };

  Player _rowToPlayer(Map<String, Object?> row) {
    return Player(
      id: row['id']! as String,
      name: row['name']! as String,
      mu: (row['mu']! as num).toDouble(),
      sigma: (row['sigma']! as num).toDouble(),
      isPermanentGk: (row['is_permanent_gk']! as int) != 0,
      matchesPlayed: (row['matches_played']! as num).toInt(),
      updatedAt: (row['updated_at'] as String?) != null
          ? DateTime.tryParse(row['updated_at'] as String)
          : null,
    );
  }
}
