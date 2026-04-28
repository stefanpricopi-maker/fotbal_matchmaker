import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/simf_exception.dart';
import '../models/models.dart';
import '../providers/simf_controller.dart';
import '../theme/simf_theme.dart';
import 'match_preview_screen.dart';

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Adaugă lista de jucători pentru joc + generare echipe.
class MatchSetupScreen extends StatefulWidget {
  const MatchSetupScreen({super.key});

  @override
  State<MatchSetupScreen> createState() => _MatchSetupScreenState();
}

class _MatchSetupScreenState extends State<MatchSetupScreen> {
  final TextEditingController _pasteCtrl = TextEditingController();
  bool _importBusy = false;
  bool _autoCreateMissing = true;
  bool _manualMode = false;
  final Map<String, MatchTeam> _manualTeams = {};

  @override
  void dispose() {
    _pasteCtrl.dispose();
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

  String _norm(String s) {
    final cleaned = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    return _stripDiacritics(cleaned).toLowerCase();
  }

  ({String baseName, bool hintPermanentGk}) _extractNameAndHints(String raw) {
    final lower = _norm(raw);
    final hintPermanentGk = lower.contains('portar') || lower.contains('gk');
    final withoutParens = raw.replaceAll(RegExp(r'\(.*?\)'), '').trim();
    final cleaned = withoutParens
        .replaceAll(RegExp(r'\bportar\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bgk\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return (
      baseName: cleaned.isEmpty ? raw.trim() : cleaned,
      hintPermanentGk: hintPermanentGk,
    );
  }

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final prev = List<int>.generate(b.length + 1, (i) => i);
    final curr = List<int>.filled(b.length + 1, 0);

    for (var i = 1; i <= a.length; i++) {
      curr[0] = i;
      final ca = a.codeUnitAt(i - 1);
      for (var j = 1; j <= b.length; j++) {
        final cb = b.codeUnitAt(j - 1);
        final cost = (ca == cb) ? 0 : 1;
        final del = prev[j] + 1;
        final ins = curr[j - 1] + 1;
        final sub = prev[j - 1] + cost;
        curr[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      for (var j = 0; j <= b.length; j++) {
        prev[j] = curr[j];
      }
    }
    return prev[b.length];
  }

  double _similarityScore(String typed, String candidate) {
    final t = _norm(typed);
    final c = _norm(candidate);
    if (t.isEmpty || c.isEmpty) return 0;

    // token overlap bonus
    final tTokens = t.split(' ').where((e) => e.isNotEmpty).toSet();
    final cTokens = c.split(' ').where((e) => e.isNotEmpty).toSet();
    final inter = tTokens.intersection(cTokens).length.toDouble();
    final union = (tTokens.union(cTokens).length).toDouble().clamp(1, 9999);
    final jaccard = inter / union;

    // edit similarity
    final d = _levenshtein(t, c).toDouble();
    final maxLen = (t.length > c.length ? t.length : c.length).toDouble();
    final editSim = (1.0 - (d / maxLen)).clamp(0.0, 1.0);

    // substring bonus (ex: "cristi" in "cristi f")
    final subBonus = (c.contains(t) || t.contains(c)) ? 0.12 : 0.0;

    return (0.55 * editSim + 0.45 * jaccard + subBonus).clamp(0.0, 1.0);
  }

  List<String> _parseWhatsAppNames(String raw) {
    final parts = raw
        .split(RegExp(r'[\n,;]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) {
          // eliminăm "1. ", "- ", "• " etc.
          final s = e.replaceFirst(RegExp(r'^\s*[\-\•\*\d]+\s*[\.\)]?\s*'), '');
          return s.trim();
        })
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    // dedupe păstrând ordinea (WhatsApp poate conține duplicate)
    final seen = <String>{};
    final out = <String>[];
    for (final p in parts) {
      final k = _norm(p);
      if (seen.add(k)) out.add(p);
    }
    return out;
  }

  Future<Player?> _askPickCandidate({
    required String typedName,
    required List<Player> candidates,
  }) async {
    var picked = candidates.first;
    return showDialog<Player?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Alege jucătorul corect'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Din WhatsApp: "$typedName"'),
              const SizedBox(height: 12),
              RadioGroup<Player>(
                groupValue: picked,
                onChanged: (v) {
                  if (v == null) return;
                  setLocal(() => picked = v);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final p in candidates)
                      RadioListTile<Player>(
                        value: p,
                        title: Text(p.name),
                        subtitle: Text(
                          'μ=${p.mu.toStringAsFixed(1)}  σ=${p.sigma.toStringAsFixed(1)}',
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Sari peste'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, picked),
              child: const Text('Alege'),
            ),
          ],
        ),
      ),
    );
  }

  Future<Player?> _showCreatePlayerDialog({
    required String initialName,
    required bool initialPermanentGk,
  }) async {
    final ctrl = context.read<SimfController>();
    final nameCtrl = TextEditingController(text: initialName);
    var permanentGk = initialPermanentGk;
    final created = await showDialog<Player?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
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
                onChanged: (v) => setLocal(() => permanentGk = v ?? false),
                title: const Text('Portar permanent'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Renunță'),
            ),
            FilledButton(
              onPressed: () async {
                final p = await ctrl.addPlayer(
                  name: nameCtrl.text,
                  isPermanentGk: permanentGk,
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx, p);
              },
              child: const Text('Salvează'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    return created;
  }

  Future<Player?> _askPickFuzzy({
    required String typedName,
    required List<Player> allPlayers,
    required String suggestedName,
    required bool suggestedPermanentGk,
  }) async {
    final scored =
        allPlayers
            .map((p) => (p: p, score: _similarityScore(typedName, p.name)))
            .where((e) => e.score > 0.25)
            .toList(growable: false)
          ..sort((a, b) => b.score.compareTo(a.score));

    var query = '';
    Player? picked;

    return showDialog<Player?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          List<(Player, double)> filtered() {
            if (query.trim().isEmpty) {
              return scored.take(10).map((e) => (e.p, e.score)).toList();
            }
            final qn = _norm(query);
            final list =
                allPlayers
                    .map((p) => (p, _similarityScore(qn, p.name)))
                    .where((e) => e.$2 > 0.15)
                    .toList()
                  ..sort((a, b) => b.$2.compareTo(a.$2));
            return list.take(20).toList();
          }

          final options = filtered();
          if (picked == null && options.isNotEmpty) picked = options.first.$1;

          return AlertDialog(
            title: const Text('Nu am găsit match exact'),
            scrollable: true,
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Din WhatsApp: "$typedName"'),
                  const SizedBox(height: 12),
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Caută în jucători',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setLocal(() => query = v),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () async {
                      final created = await _showCreatePlayerDialog(
                        initialName: suggestedName,
                        initialPermanentGk: suggestedPermanentGk,
                      );
                      if (created == null) return;
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx, created);
                    },
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Jucător nou'),
                  ),
                  const SizedBox(height: 8),
                  if (options.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Nu găsesc nimic asemănător. Poți schimba căutarea sau să sari peste.',
                      ),
                    )
                  else
                    SizedBox(
                      width: double.maxFinite,
                      height: 260,
                      child: RadioGroup<Player>(
                        groupValue: picked,
                        onChanged: (v) => setLocal(() => picked = v),
                        child: ListView.builder(
                          itemCount: options.length,
                          itemBuilder: (context, i) {
                            final p = options[i].$1;
                            final score = options[i].$2;
                            return RadioListTile<Player>(
                              value: p,
                              title: Text(p.name),
                              subtitle: Text(
                                'Asemănare: ${(score * 100).toStringAsFixed(0)}%  •  μ=${p.mu.toStringAsFixed(1)}',
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Sari peste'),
              ),
              FilledButton(
                onPressed: picked == null
                    ? null
                    : () => Navigator.pop(ctx, picked),
                child: const Text('Alege'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showImportMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      ),
    );
  }

  Future<void> _importFromWhatsApp() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final ctrl = context.read<SimfController>();
    final store = ctrl.localStore;
    final raw = _pasteCtrl.text;
    final names = _parseWhatsAppNames(raw);
    if (names.isEmpty) {
      _showImportMessage(
        'Nu am găsit niciun nume. Lipește lista în câmp (textul gri „Ex:” nu se numără) sau scrie câte un nume pe rând.',
      );
      return;
    }

    setState(() => _importBusy = true);
    try {
      final selected = <String>{};
      var aliasHits = 0;
      var exactHits = 0;
      var manualPicks = 0;
      var autoCreated = 0;
      var skipped = 0;

      for (final typed in names) {
        final extracted = _extractNameAndHints(typed);
        final aliasKey = _norm(typed);

        // 1) Alias învățat anterior (WhatsApp string exact normalizat → playerId)
        final aliasId = await store.resolveAliasToPlayerId(aliasKey);
        if (aliasId != null) {
          final p = ctrl.players.where((e) => e.id == aliasId).firstOrNull;
          if (p != null) {
            selected.add(p.id);
            aliasHits++;
            continue;
          }
        }

        final key = _norm(extracted.baseName);
        final candidates = ctrl.players
            .where((p) => _norm(p.name) == key)
            .toList(growable: false);

        if (candidates.isEmpty) {
          if (_autoCreateMissing) {
            final created = await ctrl.addPlayer(
              name: extracted.baseName,
              isPermanentGk: extracted.hintPermanentGk,
            );
            if (created != null) {
              selected.add(created.id);
              autoCreated++;
              await store.upsertAlias(alias: aliasKey, playerId: created.id);
            } else {
              skipped++;
            }
          } else {
            // Nu avem match exact → modală cu sugestii (fuzzy) + căutare manuală.
            final picked = await _askPickFuzzy(
              typedName: typed,
              allPlayers: ctrl.players,
              suggestedName: extracted.baseName,
              suggestedPermanentGk: extracted.hintPermanentGk,
            );
            if (picked != null) {
              selected.add(picked.id);
              manualPicks++;
              await store.upsertAlias(alias: aliasKey, playerId: picked.id);
            } else {
              skipped++;
            }
          }
          continue;
        }
        if (candidates.length == 1) {
          selected.add(candidates[0].id);
          exactHits++;
          await store.upsertAlias(alias: aliasKey, playerId: candidates[0].id);
          continue;
        }

        final picked = await _askPickCandidate(
          typedName: typed,
          candidates: candidates,
        );
        if (picked != null) {
          selected.add(picked.id);
          manualPicks++;
          await store.upsertAlias(alias: aliasKey, playerId: picked.id);
        } else {
          skipped++;
        }
      }

      ctrl.setSelection(selected);

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import finalizat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Total: ${names.length}'),
              const SizedBox(height: 8),
              Text('Selectați: ${selected.length}'),
              const SizedBox(height: 8),
              Text('Alias (auto): $aliasHits'),
              Text('Match exact (auto): $exactHits'),
              Text('Ales manual: $manualPicks'),
              Text('Creați automat: $autoCreated'),
              Text('Săriți: $skipped'),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e, st) {
      debugPrint('Import WhatsApp eșuat: $e\n$st');
      if (mounted) {
        _showImportMessage('Import eșuat: $e');
      }
    } finally {
      if (mounted) setState(() => _importBusy = false);
    }
  }

  /// Bandă compactă: context + câți jucători sunt deja în selecție.
  Widget _introStrip(SimfController ctrl) {
    final theme = Theme.of(context);
    final n = ctrl.selectedIds.length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  SimfTheme.pitchGreenLight.withValues(alpha: 0.38),
                  SimfTheme.teamBlue.withValues(alpha: 0.14),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: SimfTheme.outline.withValues(alpha: 0.55),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.groups_2_outlined,
                    size: 30,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pregătire meci',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Lipește lista din WhatsApp, importă în selecție, apoi generează echipe.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.72),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: SimfTheme.surface.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: SimfTheme.outline.withValues(alpha: 0.75),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        '$n selectați',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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

  Widget _autoCreateTile(BuildContext context) {
    final subtitleStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: Colors.white60);
    return SwitchListTile.adaptive(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      value: _autoCreateMissing,
      onChanged: _importBusy
          ? null
          : (v) => setState(() => _autoCreateMissing = v),
      secondary: Icon(
        Icons.person_add_alt_1_outlined,
        color: SimfTheme.pitchGreenLight.withValues(alpha: 0.95),
      ),
      title: const Text('Jucători noi automat'),
      subtitle: Text(
        'Dacă un nume nu există în app, îl creează fără să te întrebe.',
        style: subtitleStyle,
      ),
    );
  }

  Widget _pasteEditorCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  SimfTheme.teamBlue.withValues(alpha: 0.32),
                  SimfTheme.pitchGreen.withValues(alpha: 0.1),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: SimfTheme.outline.withValues(alpha: 0.55),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.forum_outlined,
                    size: 24,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mesajul de pe grup',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Câte un nume pe rând. Pentru portar: „(portar)” sau GK în text.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.72),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: TextField(
                controller: _pasteCtrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  alignLabelWithHint: true,
                  hintText: 'Dan Nicoară\nJoshua\nAlex (portar)\n…',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateTeams(SimfController ctrl) async {
    try {
      String? draftId;
      if (_manualMode) {
        final aIds = _manualTeams.entries
            .where((e) => e.value == MatchTeam.a)
            .map((e) => e.key);
        final bIds = _manualTeams.entries
            .where((e) => e.value == MatchTeam.b)
            .map((e) => e.key);
        ctrl.setManualTeams(teamAIds: aIds, teamBIds: bIds);
        draftId = await ctrl.saveDraftMatchFromActiveTeams();
      } else {
        ctrl.generateTeams();
      }
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MatchPreviewScreen(draftMatchId: draftId),
        ),
      );
    } on SimfException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Widget _importButton(BuildContext context) {
    return FilledButton.icon(
      style: SimfTheme.wideFilledButton(context),
      onPressed: _importBusy ? null : _importFromWhatsApp,
      icon: _importBusy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.playlist_add_check_rounded),
      label: const Text('Importă în selecția meciului'),
    );
  }

  Widget _generateButton(BuildContext context, SimfController ctrl) {
    final n = ctrl.selectedIds.length;
    final aCnt = _manualTeams.values.where((t) => t == MatchTeam.a).length;
    final bCnt = _manualTeams.values.where((t) => t == MatchTeam.b).length;
    final ready = _manualMode ? (aCnt > 0 && bCnt > 0) : (n >= 2);
    return FilledButton.icon(
      style: SimfTheme.wideFilledButton(context),
      onPressed: !ready ? null : () async => _generateTeams(ctrl),
      icon: const Icon(Icons.shuffle_rounded),
      label: Text(
        _manualMode
            ? (ready
                  ? 'Continuă cu echipe manuale (A $aCnt / B $bCnt)'
                  : 'Alege echipe manuale (min. 1 / 1)')
            : (ready ? 'Generare echipe ($n)' : 'Generare echipe (min. 2)'),
      ),
    );
  }

  Future<void> _openManualTeamsDialog(SimfController ctrl) async {
    final all = [...ctrl.players]..sort((a, b) => a.name.compareTo(b.name));
    final map = Map<String, MatchTeam>.from(_manualTeams);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          int cnt(MatchTeam t) => map.values.where((e) => e == t).length;
          final aCnt = cnt(MatchTeam.a);
          final bCnt = cnt(MatchTeam.b);

          Widget chip({
            required String label,
            required bool selected,
            required VoidCallback onTap,
            required Color color,
          }) {
            return InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(999),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? color.withValues(alpha: 0.22)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected
                        ? color.withValues(alpha: 0.85)
                        : Colors.white24,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? color : Colors.white70,
                  ),
                ),
              ),
            );
          }

          return AlertDialog(
            title: const Text('Alege echipele manual'),
            content: SizedBox(
              width: 680,
              height: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text('A: $aCnt  •  B: $bCnt'),
                      ),
                      TextButton.icon(
                        onPressed: () => setLocal(map.clear),
                        icon: const Icon(Icons.clear_all),
                        label: const Text('Golește'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (all.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text(
                          'Nu ai niciun jucător disponibil.\n\n'
                          'Ieși din dialog și adaugă jucători din „SIMF — Jucători”\n'
                          'sau importă din WhatsApp, apoi revino aici.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.white70, height: 1.35),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: all.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: SimfTheme.outline.withValues(alpha: 0.35),
                        ),
                        itemBuilder: (context, i) {
                          final p = all[i];
                          final t = map[p.id];
                          return ListTile(
                            dense: true,
                            title: Text(p.name),
                            subtitle: p.isPermanentGk
                                ? const Text('Portar permanent')
                                : null,
                            trailing: Wrap(
                              spacing: 8,
                              children: [
                                chip(
                                  label: 'A',
                                  selected: t == MatchTeam.a,
                                  color: SimfTheme.teamRed,
                                  onTap: () => setLocal(() {
                                    if (t == MatchTeam.a) {
                                      map.remove(p.id);
                                    } else {
                                      map[p.id] = MatchTeam.a;
                                    }
                                  }),
                                ),
                                chip(
                                  label: 'B',
                                  selected: t == MatchTeam.b,
                                  color: SimfTheme.teamBlue,
                                  onTap: () => setLocal(() {
                                    if (t == MatchTeam.b) {
                                      map.remove(p.id);
                                    } else {
                                      map[p.id] = MatchTeam.b;
                                    }
                                  }),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Închide'),
              ),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _manualTeams
                      ..clear()
                      ..addAll(map);
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Salvează'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _manualTeamsCard(BuildContext context, SimfController ctrl) {
    final aCnt = _manualTeams.values.where((t) => t == MatchTeam.a).length;
    final bCnt = _manualTeams.values.where((t) => t == MatchTeam.b).length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _manualMode,
              onChanged: (v) => setState(() => _manualMode = v),
              secondary: Icon(
                Icons.rule_folder_outlined,
                color: SimfTheme.pitchGreenLight.withValues(alpha: 0.95),
              ),
              title: const Text('Aleg echipele manual (A/B)'),
              subtitle: Text(
                'Temporar: alegi tu componența echipelor, apoi introduci scorul.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.white60),
              ),
            ),
            if (_manualMode) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                style: SimfTheme.wideFilledButton(context),
                onPressed: () => _openManualTeamsDialog(ctrl),
                icon: const Icon(Icons.groups_2_outlined),
                label: Text('Alege jucători (A $aCnt / B $bCnt)'),
              ),
              const SizedBox(height: 6),
              Text(
                'Tip: dacă ai importat din WhatsApp, poți alege doar din acei jucători (sau din tot rosterul).',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.white54),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _clearButton(BuildContext context) {
    return OutlinedButton.icon(
      style: SimfTheme.wideOutlinedButton(context),
      onPressed: _importBusy ? null : () => setState(() => _pasteCtrl.clear()),
      icon: const Icon(Icons.backspace_outlined, size: 20),
      label: const Text('Golește câmpul'),
    );
  }

  Widget _selectionHint(SimfController ctrl) {
    final n = ctrl.selectedIds.length;
    final theme = Theme.of(context);
    return Text(
      n == 0
          ? 'După import vei vedea câți jucători sunt selectați pentru meci.'
          : '$n jucători selectați pentru următorul meci.',
      style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
    );
  }

  Widget _actionsPanel(
    BuildContext context,
    SimfController ctrl, {
    bool fillVertical = false,
  }) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fillVertical ? MainAxisSize.max : MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  SimfTheme.amber.withValues(alpha: 0.22),
                  SimfTheme.pitchGreen.withValues(alpha: 0.08),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: SimfTheme.outline.withValues(alpha: 0.55),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                children: [
                  Icon(
                    Icons.touch_app_outlined,
                    size: 24,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Acțiuni',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _importButton(context),
                const SizedBox(height: 10),
                _generateButton(context, ctrl),
                const SizedBox(height: 10),
                _clearButton(context),
                const SizedBox(height: 12),
                Divider(
                  height: 1,
                  color: SimfTheme.outline.withValues(alpha: 0.65),
                ),
                const SizedBox(height: 4),
                _autoCreateTile(context),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _selectionHint(ctrl),
                ),
              ],
            ),
          ),
          if (fillVertical) const Spacer(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SimfController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Adaugă listă jucători pentru joc')),
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              const outer = EdgeInsets.fromLTRB(16, 10, 16, 16);
              final wide = constraints.maxWidth >= 760;

              if (wide) {
                return Padding(
                  padding: outer,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _introStrip(ctrl),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 58,
                              child: _pasteEditorCard(context),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 34,
                              child: ListView(
                                children: [
                                  _actionsPanel(
                                    context,
                                    ctrl,
                                    fillVertical: false,
                                  ),
                                  const SizedBox(height: 12),
                                  _manualTeamsCard(context, ctrl),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Padding(
                padding: outer,
                child: Builder(
                  builder: (context) {
                    // Pe ecrane joase, `Column` poate overflow-ui. Folosim scroll + înălțime
                    // explicită pentru editor, ca să păstrăm UI-ul utilizabil.
                    final h = constraints.maxHeight;
                    final pasteH = (h * 0.38).clamp(220.0, 420.0);
                    return ListView(
                      children: [
                        _introStrip(ctrl),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: pasteH,
                          child: _pasteEditorCard(context),
                        ),
                        const SizedBox(height: 14),
                        _actionsPanel(context, ctrl, fillVertical: false),
                        const SizedBox(height: 12),
                        _manualTeamsCard(context, ctrl),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
