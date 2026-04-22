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
  int saves = 0;
  bool rotationGk = false;
  bool cleanSheet = false;
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
  _MvpMode _mvpMode = _MvpMode.admin;

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

  bool _mvpEnabledForTeam(MatchTeam team) {
    return switch (_mvpMode) {
      _MvpMode.admin => true,
      _MvpMode.aVotes => team == MatchTeam.b, // A votează adversarii (B)
      _MvpMode.bVotes => team == MatchTeam.a, // B votează adversarii (A)
    };
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
            saves: line.saves,
            isRotationGk: line.rotationGk,
            receivedMvpVote: line.mvp,
            cleanSheet: line.cleanSheet,
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
        .clamp(0, 100);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Introducere scor'),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                const Text(
                  'Vot MVP:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SegmentedButton<_MvpMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: _MvpMode.admin,
                        label: Text('Admin'),
                        icon: Icon(Icons.admin_panel_settings_outlined),
                      ),
                      ButtonSegment(
                        value: _MvpMode.aVotes,
                        label: Text('A votează'),
                        icon: Icon(Icons.how_to_vote_outlined),
                      ),
                      ButtonSegment(
                        value: _MvpMode.bVotes,
                        label: Text('B votează'),
                        icon: Icon(Icons.how_to_vote_outlined),
                      ),
                    ],
                    selected: {_mvpMode},
                    onSelectionChanged: (s) {
                      if (s.isEmpty) return;
                      setState(() => _mvpMode = s.first);
                    },
                  ),
                ),
              ],
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
                    mvpEnabled: _mvpEnabledForTeam(MatchTeam.a),
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
                    mvpEnabled: _mvpEnabledForTeam(MatchTeam.b),
                  ),
                ),
              ],
            ),
          ),
          _ScoreBar(
            scoreA: _scoreA,
            scoreB: _scoreB,
            onChangeA: (v) => setState(() => _scoreA = v),
            onChangeB: (v) => setState(() => _scoreB = v),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _submit,
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

class _TeamPanel extends StatelessWidget {
  const _TeamPanel({
    required this.title,
    required this.color,
    required this.lines,
    required this.onChanged,
    required this.onMvp,
    required this.mvpEnabled,
  });

  final String title;
  final Color color;
  final List<_LineStat> lines;
  final VoidCallback onChanged;
  final void Function(_LineStat) onMvp;
  final bool mvpEnabled;

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
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView(
              children: lines
                  .map(
                    (line) => _PlayerRow(
                      line: line,
                      accent: color,
                      onChanged: onChanged,
                      onMvp: mvpEnabled ? () => onMvp(line) : null,
                    ),
                  )
                  .toList(),
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
  });

  final _LineStat line;
  final Color accent;
  final VoidCallback onChanged;
  final VoidCallback? onMvp;

  @override
  Widget build(BuildContext context) {
    final p = line.player;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (!p.isPermanentGk)
                  IconButton(
                    tooltip: 'Portar rotație',
                    onPressed: () {
                      line.rotationGk = !line.rotationGk;
                      onChanged();
                    },
                    icon: Icon(
                      Icons.sports_handball,
                      color: line.rotationGk ? accent : Colors.grey,
                    ),
                  ),
                IconButton(
                  tooltip: onMvp == null
                      ? 'MVP: selectează întâi cine votează (adversari)'
                      : 'MVP (vot adversari, max. 1 per echipă)',
                  onPressed: onMvp,
                  icon: Icon(
                    line.mvp ? Icons.star : Icons.star_border,
                    color: line.mvp
                        ? Colors.amber
                        : (onMvp == null ? Colors.grey.shade400 : Colors.grey),
                  ),
                ),
              ],
            ),
            _Tally(
              label: 'Goluri',
              value: line.goals,
              onMinus: () {
                if (line.goals > 0) line.goals--;
                onChanged();
              },
              onPlus: () {
                line.goals++;
                onChanged();
              },
              accent: accent,
            ),
            _Tally(
              label: 'Parade',
              value: line.saves,
              onMinus: () {
                if (line.saves > 0) line.saves--;
                onChanged();
              },
              onPlus: () {
                line.saves++;
                onChanged();
              },
              accent: accent,
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Clean sheet'),
              value: line.cleanSheet,
              onChanged: (v) {
                line.cleanSheet = v;
                onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}

enum _MvpMode { admin, aVotes, bVotes }

class _Tally extends StatelessWidget {
  const _Tally({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
    required this.accent,
  });

  final String label;
  final int value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(label)),
          IconButton.filledTonal(
            onPressed: onMinus,
            icon: const Icon(Icons.remove),
          ),
          Expanded(
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: accent,
              ),
            ),
          ),
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: accent),
            onPressed: onPlus,
            icon: const Icon(Icons.add),
          ),
        ],
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
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
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
    );
  }
}
