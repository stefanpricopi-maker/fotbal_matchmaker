import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/simf_exception.dart';
import '../providers/simf_controller.dart';
import '../theme/simf_theme.dart';
import 'match_entry_screen.dart';

/// Selectarea jucătorilor prezenți și generarea echipelor echilibrate.
class MatchSetupScreen extends StatelessWidget {
  const MatchSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SimfController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pregătire meci'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Selectează prezenții (${ctrl.selectedIds.length}/${ctrl.players.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: ctrl.players.isEmpty ? null : ctrl.selectAllVisible,
                  child: const Text('Toți'),
                ),
                TextButton(
                  onPressed: ctrl.clearSelection,
                  child: const Text('Reset'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: ctrl.players.length,
              itemBuilder: (context, index) {
                final p = ctrl.players[index];
                final selected = ctrl.selectedIds.contains(p.id);
                return CheckboxListTile(
                  value: selected,
                  onChanged: (_) => ctrl.toggleSelected(p.id),
                  title: Text(p.name),
                  secondary: p.isPermanentGk
                      ? const Icon(Icons.sports_soccer, color: Colors.amber)
                      : null,
                  subtitle: Text(
                    'Ordinal: ${p.conservativeSkill.toStringAsFixed(1)}',
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: SimfTheme.pitchGreenLight,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: ctrl.selectedIds.length < 2
                      ? null
                      : () {
                          try {
                            ctrl.generateTeams();
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const MatchEntryScreen(),
                              ),
                            );
                          } on SimfException catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.message)),
                            );
                          }
                        },
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Generare echipe'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
