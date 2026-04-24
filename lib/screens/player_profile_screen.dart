import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/simf_controller.dart';
import '../theme/simf_theme.dart';
import 'match_history_screen.dart';

/// Profil jucător + istoric meciuri cu încărcare paginată la scroll.
class PlayerProfileScreen extends StatefulWidget {
  const PlayerProfileScreen({super.key, required this.playerId});

  final String playerId;

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  static const int _pageSize = 15;

  final ScrollController _scroll = ScrollController();
  final List<({Match match, MatchPlayerStats stat, bool synced})> _rows = [];

  int _offset = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _ready = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPage());
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loading || !_hasMore) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _loadPage();
    }
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (_loading && !reset) return;
    if (!_hasMore && !reset) return;

    setState(() {
      _loading = true;
      if (reset) {
        _loadError = null;
        _hasMore = true;
      }
    });
    try {
      final store = context.read<SimfController>().localStore;
      final batch = await store.getPlayerMatchHistoryPage(
        playerId: widget.playerId,
        limit: _pageSize,
        offset: reset ? 0 : _offset,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _rows
            ..clear()
            ..addAll(batch);
        } else {
          _rows.addAll(batch);
        }
        _offset = _rows.length;
        _hasMore = batch.length >= _pageSize;
        _ready = true;
      });
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _loading || !_hasMore) return;
          if (!_scroll.hasClients) return;
          if (_scroll.position.maxScrollExtent < 80) {
            _loadPage();
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _ready = true;
        if (reset) {
          _rows.clear();
          _offset = 0;
          _hasMore = false;
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Player? _findPlayer(SimfController ctrl) {
    for (final p in ctrl.players) {
      if (p.id == widget.playerId) return p;
    }
    return null;
  }

  String _teamLabel(MatchTeam t) => t == MatchTeam.a ? 'Echipa A' : 'Echipa B';

  String _fmtWhen(DateTime utc) {
    final l = utc.toLocal();
    return '${l.day.toString().padLeft(2, '0')}.${l.month.toString().padLeft(2, '0')}.${l.year} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SimfController>();
    final p = _findPlayer(ctrl);

    return Scaffold(
      appBar: AppBar(
        title: Text(p?.name ?? 'Profil jucător'),
      ),
      body: p == null
          ? const Center(child: Text('Jucătorul nu mai există în listă.'))
          : RefreshIndicator(
              color: SimfTheme.pitchGreenLight,
              onRefresh: () async {
                await _loadPage(reset: true);
              },
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _SummaryCard(player: p, ctrl: ctrl)),
                  if (!_ready)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: _loadError != null
                            ? Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  _loadError!,
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : const CircularProgressIndicator(),
                      ),
                    )
                  else if (_rows.isEmpty && !_loading)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text('Niciun meci în istoric încă.')),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          if (i >= _rows.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: _loading
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : Text(
                                        _hasMore ? '' : '— Sfârșit listă —',
                                        style: Theme.of(context).textTheme.bodySmall,
                                        textAlign: TextAlign.center,
                                      ),
                              ),
                            );
                          }
                          final row = _rows[i];
                          final m = row.match;
                          final s = row.stat;
                          final teamColor =
                              s.team == MatchTeam.a ? SimfTheme.teamRed : SimfTheme.teamBlue;
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: ListTile(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        MatchHistoryDetailScreen(match: m),
                                  ),
                                );
                              },
                              title: Row(
                                children: [
                                  Text(
                                    '${m.scoreA} – ${m.scoreB}',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: teamColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: teamColor.withValues(alpha: 0.55)),
                                    ),
                                    child: Text(
                                      _teamLabel(s.team),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: teamColor,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: row.synced
                                          ? SimfTheme.pitchGreenLight.withValues(alpha: 0.18)
                                          : Colors.orange.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      row.synced ? 'Synced' : 'Offline',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: row.synced
                                            ? SimfTheme.pitchGreenLight
                                            : Colors.orange,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Wrap(
                                  spacing: 10,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(_fmtWhen(m.createdAt)),
                                    Text('${m.durationMinutes} min'),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.sports_soccer, size: 16),
                                        const SizedBox(width: 4),
                                        Text('Goluri: ${s.goals}'),
                                      ],
                                    ),
                                    if (s.isRotationGk)
                                      const Chip(
                                        label: Text('GK rot.', style: TextStyle(fontSize: 11)),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    if (s.receivedMvpVote)
                                      const Icon(Icons.star, color: SimfTheme.amber, size: 18),
                                    if (s.receivedGkVote)
                                      const Icon(Icons.shield, color: SimfTheme.amber, size: 18),
                                  ],
                                ),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                            ),
                          );
                        },
                        childCount: _rows.length + 1,
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.player, required this.ctrl});

  final Player player;
  final SimfController ctrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Rating & statistici',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _chip(Icons.show_chart, 'μ', player.mu.toStringAsFixed(2)),
                  _chip(Icons.waves, 'σ', player.sigma.toStringAsFixed(2)),
                  _chip(Icons.stars_outlined, 'μ−3σ', player.conservativeSkill.toStringAsFixed(1)),
                  _chip(Icons.sports_soccer, 'Meciuri', '${player.matchesPlayed}'),
                  _chip(Icons.sports_score, 'Goluri', '${ctrl.goalsForPlayer(player.id)}'),
                  _chip(
                    Icons.star_outline,
                    'MVP',
                    '${ctrl.mvpCountForPlayer(player.id)}',
                  ),
                  _chip(
                    Icons.shield_outlined,
                    'GK meci',
                    '${ctrl.gkOfMatchCountForPlayer(player.id)}',
                  ),
                  if (player.isPermanentGk)
                    _chip(Icons.sports_handball, 'Rol', 'Portar fix'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.white70),
        const SizedBox(width: 6),
        Text('$label: ', style: const TextStyle(color: Colors.white60, fontSize: 13)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }
}
