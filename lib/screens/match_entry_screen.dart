import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/simf_exception.dart';
import '../models/models.dart';
import '../providers/simf_controller.dart';
import '../services/ranking_service.dart';
import 'match_history_screen.dart';
import '../theme/simf_theme.dart';

/// Stare editabilă pentru un jucător în ecranul post-meci (tally + toggles).
class _LineStat {
  _LineStat({
    required this.player,
    required this.team,
  });

  final Player player;
  final MatchTeam team;
  int goals = 0;
  bool rotationGk = false;
  bool gkOfMatch = false;
  bool mvp = false;
}

/// Split-screen: stânga echipa A (roșu), dreapta echipa B (albastru).
class MatchEntryScreen extends StatefulWidget {
  const MatchEntryScreen({super.key});

  @override
  State<MatchEntryScreen> createState() => _MatchEntryScreenState();
}

class _MatchEntryScreenState extends State<MatchEntryScreen> {
  final List<_LineStat> _lines = [];
  final RankingService _ranking = RankingService();
  int _scoreA = 0;
  int _scoreB = 0;
  bool _busy = false;

  int get _sumGoalsA => _lines
      .where((l) => l.team == MatchTeam.a)
      .fold<int>(0, (s, l) => s + l.goals);
  int get _sumGoalsB => _lines
      .where((l) => l.team == MatchTeam.b)
      .fold<int>(0, (s, l) => s + l.goals);
  bool get _goalsMatchScore => _sumGoalsA == _scoreA && _sumGoalsB == _scoreB;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_lines.isEmpty) {
      final match = context.read<SimfController>().lastMatch;
      if (match != null) {
        for (final p in match.teamA) {
          _lines.add(_LineStat(player: p, team: MatchTeam.a));
        }
        for (final p in match.teamB) {
          _lines.add(_LineStat(player: p, team: MatchTeam.b));
        }
      }
    }
  }

  List<_LineStat> get _teamALines =>
      _lines.where((l) => l.team == MatchTeam.a).toList();
  List<_LineStat> get _teamBLines =>
      _lines.where((l) => l.team == MatchTeam.b).toList();

  void _setMvpExclusive(_LineStat target) {
    setState(() {
      if (target.mvp) {
        target.mvp = false;
      } else {
        for (final l in _lines) {
          if (l.team == target.team) l.mvp = false;
        }
        target.mvp = true;
      }
    });
  }

  void _setGkOfMatchExclusive(_LineStat target) {
    if (!target.rotationGk) return;
    setState(() {
      if (target.gkOfMatch) {
        target.gkOfMatch = false;
      } else {
        for (final l in _lines) {
          l.gkOfMatch = false;
        }
        target.gkOfMatch = true;
      }
    });
  }

  Future<void> _submit() async {
    final ctrl = context.read<SimfController>();
    final match = ctrl.lastMatch;
    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nu există echipe active.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final stats = <MatchPlayerStats>[];
      for (final line in _lines) {
        stats.add(
          MatchPlayerStats(
            matchId: '',
            playerId: line.player.id,
            team: line.team,
            goals: line.goals,
            isRotationGk: line.rotationGk,
            receivedMvpVote: line.mvp,
            receivedGkVote: line.gkOfMatch,
          ),
        );
      }

      await ctrl.finalizeMatch(
        scoreA: _scoreA,
        scoreB: _scoreB,
        stats: stats,
      );

      if (!mounted) return;
      final goHistory = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Meci salvat'),
          content: const Text('Ratingurile au fost actualizate.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Gata'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.history),
              label: const Text('Vezi istoric'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      if (goHistory == true && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const MatchHistoryScreen(),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Meci salvat și ratinguri actualizate.'),
            action: SnackBarAction(
              label: 'Istoric',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MatchHistoryScreen(),
                  ),
                );
              },
            ),
          ),
        );
      }
    } on SimfException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final match = context.watch<SimfController>().lastMatch;
    if (match == null) {
      return const Scaffold(
        body: Center(child: Text('Generează echipe din fluxul de meci.')),
      );
    }

    final winPct = (_ranking.winProbabilityTeamA(
              teamA: match.teamA,
              teamB: match.teamB,
            ) *
            100)
        .clamp(0.0, 100.0)
        .toDouble();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Introducere scor'),
      ),
      body: Column(
        children: [
          _WinChanceChips(winPctA: winPct),
          _ScoreBar(
            scoreA: _scoreA,
            scoreB: _scoreB,
            onChangeA: (v) => setState(() => _scoreA = v),
            onChangeB: (v) => setState(() => _scoreB = v),
          ),
          if (!_goalsMatchScore)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text(
                'Goluri jucători ≠ scor: A $_sumGoalsA/$_scoreA • B $_sumGoalsB/$_scoreB',
                style: TextStyle(color: Colors.orange.shade300),
              ),
            ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _TeamPanel(
                    title: 'Echipa A (Roșu)',
                    color: SimfTheme.teamRed,
                    lines: _teamALines,
                    onChanged: () => setState(() {}),
                    onMvp: _setMvpExclusive,
                    onGkOfMatch: _setGkOfMatchExclusive,
                    mvpEnabled: true,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _TeamPanel(
                    title: 'Echipa B (Albastru)',
                    color: SimfTheme.teamBlue,
                    lines: _teamBLines,
                    onChanged: () => setState(() {}),
                    onMvp: _setMvpExclusive,
                    onGkOfMatch: _setGkOfMatchExclusive,
                    mvpEnabled: true,
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      (_busy || !_goalsMatchScore) ? null : _submit,
                  icon: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_busy ? 'Se salvează…' : 'Finalizează meciul'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip-uri pentru șansele de câștig (echitabil vizual pentru A și B).
class _WinChanceChips extends StatelessWidget {
  const _WinChanceChips({required this.winPctA});

  final double winPctA;

  @override
  Widget build(BuildContext context) {
    final a = winPctA.clamp(0.0, 100.0);
    final b = (100.0 - a).clamp(0.0, 100.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Row(
        children: [
          Expanded(
            child: Chip(
              avatar: Icon(
                Icons.trending_up,
                size: 18,
                color: SimfTheme.teamRed.withValues(alpha: 0.95),
              ),
              label: Text('Șansă A: ${a.toStringAsFixed(0)}%'),
              side: BorderSide(
                color: SimfTheme.teamRed.withValues(alpha: 0.45),
              ),
              backgroundColor: SimfTheme.teamRed.withValues(alpha: 0.14),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Chip(
              avatar: Icon(
                Icons.trending_up,
                size: 18,
                color: SimfTheme.teamBlue.withValues(alpha: 0.95),
              ),
              label: Text('Șansă B: ${b.toStringAsFixed(0)}%'),
              side: BorderSide(
                color: SimfTheme.teamBlue.withValues(alpha: 0.45),
              ),
              backgroundColor: SimfTheme.teamBlue.withValues(alpha: 0.14),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamPanel extends StatelessWidget {
  const _TeamPanel({
    required this.title,
    required this.color,
    required this.lines,
    required this.onChanged,
    required this.onMvp,
    required this.onGkOfMatch,
    required this.mvpEnabled,
  });

  final String title;
  final Color color;
  final List<_LineStat> lines;
  final VoidCallback onChanged;
  final void Function(_LineStat) onMvp;
  final void Function(_LineStat) onGkOfMatch;
  final bool mvpEnabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.42),
                  color.withValues(alpha: 0.12),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: color.withValues(alpha: 0.55),
                  width: 1,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: Colors.white,
                      shadows: const [
                        Shadow(
                          blurRadius: 6,
                          color: Colors.black38,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(top: 6, bottom: 12),
              itemCount: lines.length,
              separatorBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Divider(
                  height: 1,
                  color: SimfTheme.outline.withValues(alpha: 0.45),
                ),
              ),
              itemBuilder: (context, i) {
                final line = lines[i];
                return _PlayerRow(
                  line: line,
                  accent: color,
                  onChanged: onChanged,
                  onMvp: mvpEnabled ? () => onMvp(line) : null,
                  onGkOfMatch:
                      line.rotationGk ? () => onGkOfMatch(line) : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.line,
    required this.accent,
    required this.onChanged,
    required this.onMvp,
    required this.onGkOfMatch,
  });

  final _LineStat line;
  final Color accent;
  final VoidCallback onChanged;
  final VoidCallback? onMvp;
  final VoidCallback? onGkOfMatch;

  @override
  Widget build(BuildContext context) {
    final p = line.player;
    const iconSize = 22.0;
    const btnW = 40.0;
    const btnH = 40.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: accent.withValues(alpha: 0.38),
            width: 0.9,
          ),
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: 0.14),
              SimfTheme.surface2.withValues(alpha: 0.65),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      p.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                const Icon(Icons.sports_soccer, size: iconSize, color: Colors.white70),
                const SizedBox(width: 2),
                IconButton(
                  tooltip: 'Gol -1',
                  constraints: const BoxConstraints.tightFor(
                    width: btnW,
                    height: btnH,
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    if (line.goals > 0) line.goals--;
                    onChanged();
                  },
                  icon: const Icon(Icons.remove_circle_outline, size: iconSize),
                ),
                SizedBox(
                  width: 22,
                  child: Text(
                    '${line.goals}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: accent,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Gol +1',
                  constraints: const BoxConstraints.tightFor(
                    width: btnW,
                    height: btnH,
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    line.goals++;
                    onChanged();
                  },
                  icon: Icon(Icons.add_circle, size: iconSize, color: accent),
                ),
                if (!p.isPermanentGk)
                  IconButton(
                    tooltip: 'Portar rotație',
                    onPressed: () {
                      line.rotationGk = !line.rotationGk;
                      if (!line.rotationGk) line.gkOfMatch = false;
                      onChanged();
                    },
                    icon: Icon(
                      Icons.sports_handball,
                      color: line.rotationGk ? accent : Colors.grey,
                    ),
                  ),
                IconButton(
                  tooltip: line.rotationGk
                      ? 'Portarul meciului (1 singur)'
                      : 'Bifează mai întâi portar rotație',
                  onPressed: line.rotationGk ? onGkOfMatch : null,
                  icon: Icon(
                    Icons.shield_outlined,
                    color: line.gkOfMatch ? Colors.amber : Colors.white38,
                  ),
                ),
                IconButton(
                  tooltip: 'MVP (max. 1 per echipă)',
                  onPressed: onMvp,
                  icon: Icon(
                    line.mvp ? Icons.star : Icons.star_border,
                    color: line.mvp
                        ? Colors.amber
                        : Colors.grey,
                  ),
                ),
              ],
            ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({
    required this.scoreA,
    required this.scoreB,
    required this.onChangeA,
    required this.onChangeB,
  });

  final int scoreA;
  final int scoreB;
  final ValueChanged<int> onChangeA;
  final ValueChanged<int> onChangeB;

  @override
  Widget build(BuildContext context) {
    Widget side({
      required String label,
      required int value,
      required Color color,
      required ValueChanged<int> onChange,
    }) {
      return Expanded(
        child: Column(
          children: [
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(onPressed: () => onChange((value - 1).clamp(0, 99)), icon: const Icon(Icons.remove)),
                Text('$value', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                IconButton(onPressed: () => onChange((value + 1).clamp(0, 99)), icon: const Icon(Icons.add)),
              ],
            ),
          ],
        ),
      );
    }

    return Material(
      elevation: 0,
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              SimfTheme.teamRed.withValues(alpha: 0.14),
              SimfTheme.surface2.withValues(alpha: 0.5),
              SimfTheme.teamBlue.withValues(alpha: 0.14),
            ],
          ),
          border: Border(
            bottom: BorderSide(
              color: SimfTheme.outline.withValues(alpha: 0.65),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              side(
                label: 'Scor A',
                value: scoreA,
                color: SimfTheme.teamRed,
                onChange: onChangeA,
              ),
              side(
                label: 'Scor B',
                value: scoreB,
                color: SimfTheme.teamBlue,
                onChange: onChangeB,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
