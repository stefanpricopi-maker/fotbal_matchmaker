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
  static const _v1 = 1;

  static Future<LocalStore> open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, _dbName);
    final db = await openDatabase(
      path,
      version: _v1,
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
