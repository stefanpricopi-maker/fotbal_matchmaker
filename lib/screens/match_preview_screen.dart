import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/simf_controller.dart';
import '../services/ranking_service.dart';
import '../theme/simf_theme.dart';
import 'match_entry_screen.dart';

/// Ecran intermediar: arată doar componența echipelor generate.
class MatchPreviewScreen extends StatelessWidget {
  const MatchPreviewScreen({super.key});

  double _starsForPlayer({
    required Player player,
    required double minSkill,
    required double maxSkill,
  }) {
    if (maxSkill <= minSkill + 1e-9) return 2.5;
    final t = ((player.conservativeSkill - minSkill) / (maxSkill - minSkill))
        .clamp(0.0, 1.0);
    final raw = 0.5 + t * 4.5; // 0.5..5.0
    // Snap la 0.5
    return (raw * 2).round() / 2.0;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SimfController>();
    final match = ctrl.lastMatch;
    if (match == null) {
      return const Scaffold(
        body: Center(child: Text('Nu există echipe generate.')),
      );
    }

    final ranking = RankingService();
    final winPct = (ranking.winProbabilityTeamA(teamA: match.teamA, teamB: match.teamB) *
            100)
        .clamp(0, 100);

    final all = [...match.teamA, ...match.teamB];
    final skills = all.map((p) => p.conservativeSkill).toList(growable: false);
    final minSkill = skills.reduce((a, b) => a < b ? a : b);
    final maxSkill = skills.reduce((a, b) => a > b ? a : b);

    double stars(Player p) => _starsForPlayer(
          player: p,
          minSkill: minSkill,
          maxSkill: maxSkill,
        );

    int teamScorePct(List<Player> team) {
      if (team.isEmpty) return 0;
      final sum = team.fold<double>(0, (s, p) => s + stars(p));
      final maxSum = team.length * 5.0;
      return ((sum / maxSum) * 100).round().clamp(0, 100);
    }

    final scoreA = teamScorePct(match.teamA);
    final scoreB = teamScorePct(match.teamB);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Echipe generate'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                'Șansă A: ${winPct.toStringAsFixed(0)}%',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _TeamPreviewPanel(
                    title: 'Echipa A (Roșu)',
                    scorePct: scoreA,
                    color: SimfTheme.teamRed,
                    players: match.teamA,
                    starsFor: stars,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _TeamPreviewPanel(
                    title: 'Echipa B (Albastru)',
                    scorePct: scoreB,
                    color: SimfTheme.teamBlue,
                    players: match.teamB,
                    starsFor: stars,
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Generează iar'),
                      onPressed: () {
                        ctrl.generateTeams();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Introducere scor'),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const MatchEntryScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamPreviewPanel extends StatelessWidget {
  const _TeamPreviewPanel({
    required this.title,
    required this.scorePct,
    required this.color,
    required this.players,
    required this.starsFor,
  });

  final String title;
  final int scorePct;
  final Color color;
  final List<Player> players;
  final double Function(Player) starsFor;

  List<Widget> _buildStars(double stars) {
    const on = Icon(Icons.star, size: 16, color: Colors.amber);
    const half = Icon(Icons.star_half, size: 16, color: Colors.amber);
    final off = Icon(
      Icons.star_border,
      size: 16,
      color: Colors.white.withValues(alpha: 0.28),
    );

    final full = stars.floor();
    final hasHalf = (stars - full).abs() > 1e-9;
    final out = <Widget>[];
    for (var i = 0; i < 5; i++) {
      if (i < full) {
        out.add(on);
      } else if (i == full && hasHalf) {
        out.add(half);
      } else {
        out.add(off);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            color: color.withValues(alpha: 0.25),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    '$scorePct',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: players.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = players[i];
                final stars = starsFor(p);
                return ListTile(
                  dense: true,
                  title: Text(
                    p.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  trailing: Tooltip(
                    message:
                        'Skill: ${p.conservativeSkill.toStringAsFixed(1)}  •  Stele: ${stars.toStringAsFixed(1)}',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _buildStars(stars),
                    ),
                  ),
                  subtitle: p.isPermanentGk ? const Text('Portar permanent') : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

