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
            icon: const Icon(Icons.groups_2_outlined),
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
              title: Text(p.name),
              subtitle: Text(
                'μ=${p.mu.toStringAsFixed(2)}  σ=${p.sigma.toStringAsFixed(2)}  '
                'meciuri: ${p.matchesPlayed}'
                '${p.isPermanentGk ? '  • GK' : ''}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
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
                },
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Adaugă'),
      ),
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
