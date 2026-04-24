import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/simf_controller.dart';
import '../theme/simf_theme.dart';
import 'match_setup_screen.dart';
import 'match_history_screen.dart';
import 'player_profile_screen.dart';

/// Lista jucătorilor + adăugare profil nou (SQLite + opțional Supabase).
class PlayerListScreen extends StatefulWidget {
  const PlayerListScreen({super.key});

  @override
  State<PlayerListScreen> createState() => _PlayerListScreenState();
}

enum _PlayerSort { name, skill, lastMatch, goals }
enum _PlayerRowAction { rename, delete }
enum _TopAction { devSeed, devClearSeed }

class _PlayerListScreenState extends State<PlayerListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  _PlayerSort _sort = _PlayerSort.name;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SimfController>().loadPlayers();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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

  String _norm(String s) => _stripDiacritics(s).toLowerCase();

  /// Gradient discret pe avatar, derivat din skill conservator (μ − 3σ).
  List<Color> _avatarGradient(Player p) {
    final t = (p.conservativeSkill / 40.0).clamp(0.0, 1.0);
    return [
      Color.lerp(SimfTheme.surface2, SimfTheme.pitchGreenLight, t * 0.88)!,
      Color.lerp(SimfTheme.card, SimfTheme.teamBlue, 0.32 + t * 0.45)!,
    ];
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final w = parts.first;
      return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
    }
    final a = parts.first[0].toUpperCase();
    final b = parts.last[0].toUpperCase();
    return '$a$b';
  }

  String _relativeDays(DateTime? dt) {
    if (dt == null) return '—';
    final d = DateTime.now().difference(dt).inDays;
    if (d <= 0) return 'azi';
    if (d == 1) return 'ieri';
    return '$d zile';
  }

  Future<void> _showAddDialog() async {
    final nameCtrl = TextEditingController();
    var permanentGk = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Jucător nou'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nume',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: permanentGk,
                    onChanged: (v) =>
                        setLocal(() => permanentGk = v ?? false),
                    title: const Text('Portar permanent'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Renunță'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Salvează'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok == true && mounted) {
      await context.read<SimfController>().addPlayer(
            name: nameCtrl.text,
            isPermanentGk: permanentGk,
          );
    }
    nameCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SimfController>();
    final q = _norm(_query.trim());
    final filtered = ctrl.players
        .where((p) => q.isEmpty || _norm(p.name).contains(q))
        .toList(growable: false);

    int cmp(Player a, Player b) {
      return switch (_sort) {
        _PlayerSort.name => a.name.compareTo(b.name),
        _PlayerSort.skill => b.conservativeSkill.compareTo(a.conservativeSkill),
        _PlayerSort.goals =>
          ctrl.goalsForPlayer(b.id).compareTo(ctrl.goalsForPlayer(a.id)),
        _PlayerSort.lastMatch =>
          (ctrl.lastMatchAtForPlayer(b.id)?.millisecondsSinceEpoch ?? 0)
              .compareTo(
                (ctrl.lastMatchAtForPlayer(a.id)?.millisecondsSinceEpoch ?? 0),
              ),
      };
    }
    final players = [...filtered]..sort(cmp);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Expanded(
              child: Text('SIMF — Jucători', overflow: TextOverflow.ellipsis),
            ),
            Icon(
              ctrl.hasCloudSync ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
              size: 22,
              color: ctrl.hasCloudSync
                  ? SimfTheme.pitchGreenLight
                  : Colors.white54,
            ),
          ],
        ),
        actions: [
          if (kDebugMode)
            PopupMenuButton<_TopAction>(
              tooltip: 'Dev tools',
              onSelected: (v) async {
                if (v == _TopAction.devSeed) {
                  await context.read<SimfController>().devSeedDemo();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Demo seed creat (jucători + 1 meci).'),
                      behavior: SnackBarBehavior.floating,
                      margin: EdgeInsets.fromLTRB(12, 0, 12, 24),
                    ),
                  );
                } else if (v == _TopAction.devClearSeed) {
                  await context.read<SimfController>().devClearDemoSeed();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Demo seed șters.'),
                      behavior: SnackBarBehavior.floating,
                      margin: EdgeInsets.fromLTRB(12, 0, 12, 24),
                    ),
                  );
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _TopAction.devSeed,
                  child: Text('Creează demo seed'),
                ),
                PopupMenuItem(
                  value: _TopAction.devClearSeed,
                  child: Text('Șterge demo seed'),
                ),
              ],
              icon: const Icon(Icons.developer_mode),
            ),
          PopupMenuButton<_PlayerSort>(
            tooltip: 'Sortare',
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (context) => const [
              PopupMenuItem(value: _PlayerSort.name, child: Text('Nume')),
              PopupMenuItem(value: _PlayerSort.skill, child: Text('Skill')),
              PopupMenuItem(value: _PlayerSort.lastMatch, child: Text('Ultimul meci')),
              PopupMenuItem(value: _PlayerSort.goals, child: Text('Goluri')),
            ],
            icon: const Icon(Icons.sort),
          ),
          IconButton(
            tooltip: 'Istoric meciuri',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MatchHistoryScreen(),
                ),
              );
            },
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: 'Meci nou',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MatchSetupScreen(),
                ),
              );
            },
            icon: const Icon(Icons.sports_soccer_outlined),
          ),
          IconButton(
            tooltip: 'Adaugă jucător',
            onPressed: _showAddDialog,
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              SimfTheme.pitchGreen.withValues(alpha: 0.18),
              SimfTheme.surface,
              SimfTheme.teamBlue.withValues(alpha: 0.10),
            ],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            color: SimfTheme.pitchGreenLight,
            onRefresh: ctrl.loadPlayers,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: players.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Caută jucător…',
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Șterge',
                                onPressed: () => setState(() {
                                  _query = '';
                                  _searchCtrl.text = '';
                                }),
                                icon: const Icon(Icons.clear),
                              ),
                      ),
                    ),
                  );
                }

                final p = players[index - 1];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: ListTile(
                    leading: Tooltip(
                      message: p.isPermanentGk
                          ? 'Portar permanent — apasă pentru profil'
                          : 'Apasă pentru profil',
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: _avatarGradient(p),
                              ),
                              border: Border.all(
                                color: SimfTheme.outline.withValues(alpha: 0.8),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.28),
                                  blurRadius: 5,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                _initials(p.name),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          if (p.isPermanentGk)
                            Positioned(
                              right: -3,
                              bottom: -3,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: SimfTheme.amber.withValues(alpha: 0.95),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: SimfTheme.surface,
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(
                                  Icons.sports_handball,
                                  size: 12,
                                  color: SimfTheme.surface,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    title: Text(p.name),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PlayerProfileScreen(playerId: p.id),
                        ),
                      );
                    },
                    subtitle: Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Tooltip(
                    message:
                        'μ (mu) = estimarea abilității curente (media distribuției). Mai mare = jucător mai bun.',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.show_chart,
                          size: 16,
                          color: SimfTheme.pitchGreenLight,
                        ),
                        const SizedBox(width: 4),
                        Text(p.mu.toStringAsFixed(2)),
                      ],
                    ),
                  ),
                  Tooltip(
                    message:
                        'σ (sigma) = incertitudinea ratingului. Mai mic = suntem mai siguri de valoare; mai mare = rating încă „neformatat”.',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.waves,
                          size: 16,
                          color: Colors.white60,
                        ),
                        const SizedBox(width: 4),
                        Text(p.sigma.toStringAsFixed(2)),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: 'Skill conservator (μ − 3σ). Folosit pentru echilibrări.',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.stars_outlined,
                          size: 16,
                          color: SimfTheme.amber,
                        ),
                        const SizedBox(width: 4),
                        Text(p.conservativeSkill.toStringAsFixed(1)),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.sports_soccer,
                        size: 16,
                        color: Colors.white60,
                      ),
                      const SizedBox(width: 4),
                      Text('meciuri: ${p.matchesPlayed}'),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.sports_score,
                        size: 16,
                        color: Colors.white60,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'goluri: ${ctrl.goalsForPlayer(p.id)} '
                        '(${ctrl.goalsPerMatchForPlayer(p.id).toStringAsFixed(2)}/meci)',
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.history,
                        size: 16,
                        color: Colors.white60,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'ultimul: ${_relativeDays(ctrl.lastMatchAtForPlayer(p.id))}',
                      ),
                    ],
                  ),
                  if (ctrl.mvpCountForPlayer(p.id) > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, size: 16, color: SimfTheme.amber),
                        const SizedBox(width: 4),
                        Text('${ctrl.mvpCountForPlayer(p.id)}'),
                      ],
                    ),
                  if (ctrl.gkOfMatchCountForPlayer(p.id) > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shield, size: 16, color: SimfTheme.amber),
                        const SizedBox(width: 4),
                        Text('${ctrl.gkOfMatchCountForPlayer(p.id)}'),
                      ],
                    ),
                ],
              ),
                    trailing: PopupMenuButton<_PlayerRowAction>(
                tooltip: 'Acțiuni',
                onSelected: (a) async {
                  if (a == _PlayerRowAction.rename) {
                    final nameCtrl = TextEditingController(text: p.name);
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Editează numele'),
                        content: TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nume',
                            border: OutlineInputBorder(),
                          ),
                          textCapitalization: TextCapitalization.words,
                          autofocus: true,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Renunță'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Salvează'),
                          ),
                        ],
                      ),
                    );
                    final newName = nameCtrl.text;
                    nameCtrl.dispose();
                    if (ok == true && context.mounted) {
                      await context.read<SimfController>().renamePlayer(
                            player: p,
                            newName: newName,
                          );
                    }
                  }
                  if (a == _PlayerRowAction.delete && context.mounted) {
                    final sure = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Ștergi jucătorul?'),
                        content: Text('${p.name} va fi eliminat din lista locală.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Nu'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Da'),
                          ),
                        ],
                      ),
                    );
                    if (sure == true && context.mounted) {
                      await context.read<SimfController>().deletePlayer(p);
                    }
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _PlayerRowAction.rename,
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined),
                        SizedBox(width: 8),
                        Text('Editează'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: _PlayerRowAction.delete,
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline),
                        SizedBox(width: 8),
                        Text('Șterge'),
                      ],
                    ),
                  ),
                ],
                      icon: const Icon(Icons.more_vert),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      floatingActionButton: null,
      bottomNavigationBar: ctrl.lastError != null
          ? Material(
              color: Colors.red.shade900,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    ctrl.lastError!,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
