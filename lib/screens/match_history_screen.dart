import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/simf_controller.dart';
import '../services/local_store.dart';
import '../theme/simf_theme.dart';

class MatchHistoryScreen extends StatelessWidget {
  const MatchHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SimfController>();
    final store = ctrl.localStore;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Istoric meciuri'),
      ),
      body: FutureBuilder<List<({Match match, bool synced})>>(
        future: store.getRecentMatches(limit: 100),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data ?? const [];
          if (data.isEmpty) {
            return const Center(child: Text('Nu există meciuri salvate încă.'));
          }

          return ListView.separated(
            itemCount: data.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = data[i].match;
              final synced = data[i].synced;
              final when = m.createdAt.toLocal();
              final subtitle =
                  '${when.day.toString().padLeft(2, '0')}.${when.month.toString().padLeft(2, '0')} '
                  '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}'
                  ' • ${m.durationMinutes} min';

              return ListTile(
                title: Row(
                  children: [
                    Text(
                      '${m.scoreA} - ${m.scoreB}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: synced
                            ? SimfTheme.pitchGreenLight.withValues(alpha: 0.2)
                            : Colors.orange.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: synced
                              ? SimfTheme.pitchGreenLight
                              : Colors.orange,
                        ),
                      ),
                      child: Text(
                        synced ? 'Synced' : 'Offline',
                        style: TextStyle(
                          fontSize: 12,
                          color: synced
                              ? SimfTheme.pitchGreenLight
                              : Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MatchHistoryDetailScreen(match: m),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class MatchHistoryDetailScreen extends StatelessWidget {
  const MatchHistoryDetailScreen({super.key, required this.match});

  final Match match;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SimfController>();
    final store = ctrl.localStore;
    final byId = {for (final p in ctrl.players) p.id: p.name};

    return Scaffold(
      appBar: AppBar(
        title: Text('Meci ${match.scoreA}-${match.scoreB}'),
      ),
      body: FutureBuilder<List<MatchPlayerStats>>(
        future: store.getStatsForMatch(match.id),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final stats = snap.data ?? const [];
          if (stats.isEmpty) {
            return const Center(child: Text('Nu există statistici pentru acest meci.'));
          }

          final a = stats.where((s) => s.team == MatchTeam.a).toList();
          final b = stats.where((s) => s.team == MatchTeam.b).toList();

          Widget teamBlock({
            required String title,
            required Color color,
            required List<MatchPlayerStats> lines,
          }) {
            return Expanded(
              child: Container(
                color: color.withValues(alpha: 0.08),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 8,
                      ),
                      color: color.withValues(alpha: 0.25),
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: lines.length,
                        itemBuilder: (context, i) {
                          final s = lines[i];
                          final name = byId[s.playerId] ?? s.playerId;
                          return ListTile(
                            title: Text(name),
                            subtitle: Text(
                              'G:${s.goals}  P:${s.saves}'
                              '${s.isRotationGk ? '  • GK rot.' : ''}'
                              '${s.cleanSheet ? '  • CS' : ''}',
                            ),
                            trailing: s.receivedMvpVote
                                ? const Icon(Icons.star, color: Colors.amber)
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Durată: ${match.durationMinutes} min • ${match.createdAt.toLocal()}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
                ),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    teamBlock(
                      title: 'Echipa A',
                      color: SimfTheme.teamRed,
                      lines: a,
                    ),
                    const VerticalDivider(width: 1),
                    teamBlock(
                      title: 'Echipa B',
                      color: SimfTheme.teamBlue,
                      lines: b,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

