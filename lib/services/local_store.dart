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
  static const _v4 = 4;

  static Future<LocalStore> open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, _dbName);
    final db = await openDatabase(
      path,
      version: _v4,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE players (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  mu REAL NOT NULL,
  sigma REAL NOT NULL,
  is_permanent_gk INTEGER NOT NULL,
  matches_played INTEGER NOT NULL
);
''');

        await db.execute('''
CREATE TABLE matches (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL,
  score_a INTEGER NOT NULL,
  score_b INTEGER NOT NULL,
  duration_minutes INTEGER NOT NULL,
  synced INTEGER NOT NULL
);
''');

        await db.execute('''
CREATE TABLE match_player_stats (
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
            'saves': s.saves,
            'is_rotation_gk': s.isRotationGk ? 1 : 0,
            'received_mvp_vote': s.receivedMvpVote ? 1 : 0,
            'received_gk_vote': s.receivedGkVote ? 1 : 0,
            'clean_sheet': s.cleanSheet ? 1 : 0,
            'synced': synced ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
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
    return rows
        .map(
          (r) => Match(
            id: r['id']! as String,
            createdAt: DateTime.parse(r['created_at']! as String),
            scoreA: (r['score_a']! as num).toInt(),
            scoreB: (r['score_b']! as num).toInt(),
            durationMinutes: (r['duration_minutes']! as num).toInt(),
          ),
        )
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
          final match = Match(
            id: r['id']! as String,
            createdAt: DateTime.parse(r['created_at']! as String),
            scoreA: (r['score_a']! as num).toInt(),
            scoreB: (r['score_b']! as num).toInt(),
            durationMinutes: (r['duration_minutes']! as num).toInt(),
          );
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
            saves: (r['saves']! as num).toInt(),
            isRotationGk: (r['is_rotation_gk']! as int) != 0,
            receivedMvpVote: (r['received_mvp_vote']! as int) != 0,
            receivedGkVote: (r['received_gk_vote']! as int) != 0,
            cleanSheet: (r['clean_sheet']! as int) != 0,
          ),
        )
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

  Map<String, Object?> _playerToRow(Player p) => {
        'id': p.id,
        'name': p.name,
        'mu': p.mu,
        'sigma': p.sigma,
        'is_permanent_gk': p.isPermanentGk ? 1 : 0,
        'matches_played': p.matchesPlayed,
      };

  Player _rowToPlayer(Map<String, Object?> row) {
    return Player(
      id: row['id']! as String,
      name: row['name']! as String,
      mu: (row['mu']! as num).toDouble(),
      sigma: (row['sigma']! as num).toDouble(),
      isPermanentGk: (row['is_permanent_gk']! as int) != 0,
      matchesPlayed: (row['matches_played']! as num).toInt(),
    );
  }
}
