import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/simf_controller.dart';
import '../theme/simf_theme.dart';
import 'match_setup_screen.dart';

/// Lista jucătorilor + adăugare profil nou (SQLite + opțional Supabase).
class PlayerListScreen extends StatefulWidget {
  const PlayerListScreen({super.key});

  @override
  State<PlayerListScreen> createState() => _PlayerListScreenState();
}

class _PlayerListScreenState extends State<PlayerListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SimfController>().loadPlayers();
    });
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

  Future<void> _showRenameDialog(String currentName) async {
    final ctrl = TextEditingController(text: currentName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editează numele'),
        content: TextField(
          controller: ctrl,
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
    if (ok == true && mounted) {
      final newName = ctrl.text;
      // Caller handles applying.
      Navigator.of(context).pop(newName);
    }
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SimfController>();

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
      body: RefreshIndicator(
        color: SimfTheme.pitchGreenLight,
        onRefresh: ctrl.loadPlayers,
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: ctrl.players.length,
          itemBuilder: (context, index) {
            final p = ctrl.players[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                child: const Icon(Icons.person_outline, color: Colors.white70),
              ),
              title: Text(p.name),
              onTap: () async {
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
                      Text('goluri: ${ctrl.goalsForPlayer(p.id)}'),
                    ],
                  ),
                  if (p.isPermanentGk)
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.sports_handball,
                          size: 16,
                          color: Colors.amber,
                        ),
                        SizedBox(width: 4),
                        Text('GK'),
                      ],
                    ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Editează',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
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
                    },
                  ),
                  IconButton(
                    tooltip: 'Șterge',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final sure = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Ștergi jucătorul?'),
                          content:
                              Text('${p.name} va fi eliminat din lista locală.'),
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
                    },
                  ),
                ],
              ),
            );
          },
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
