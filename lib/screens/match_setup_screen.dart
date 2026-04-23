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
              ...candidates.map(
                (p) => RadioListTile<Player>(
                  value: p,
                  groupValue: picked,
                  onChanged: (v) {
                    if (v == null) return;
                    setLocal(() => picked = v);
                  },
                  title: Text(p.name),
                  subtitle: Text(
                    'μ=${p.mu.toStringAsFixed(1)}  σ=${p.sigma.toStringAsFixed(1)}',
                  ),
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
    final scored = allPlayers
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
            final list = allPlayers
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
                      child: ListView.builder(
                        itemCount: options.length,
                        itemBuilder: (context, i) {
                          final p = options[i].$1;
                          final score = options[i].$2;
                          return RadioListTile<Player>(
                            value: p,
                            groupValue: picked,
                            onChanged: (v) => setLocal(() => picked = v),
                            title: Text(p.name),
                            subtitle: Text(
                              'Asemănare: ${(score * 100).toStringAsFixed(0)}%  •  μ=${p.mu.toStringAsFixed(1)}',
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
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Sari peste'),
              ),
              FilledButton(
                onPressed: picked == null ? null : () => Navigator.pop(ctx, picked),
                child: const Text('Alege'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _importFromWhatsApp() async {
    final ctrl = context.read<SimfController>();
    final store = ctrl.localStore;
    final raw = _pasteCtrl.text;
    final names = _parseWhatsAppNames(raw);
    if (names.isEmpty) return;

    setState(() => _importBusy = true);
    try {
      final selected = <String>{};

      for (final typed in names) {
        final extracted = _extractNameAndHints(typed);
        final aliasKey = _norm(typed);

        // 1) Alias învățat anterior (WhatsApp string exact normalizat → playerId)
        final aliasId = await store.resolveAliasToPlayerId(aliasKey);
        if (aliasId != null) {
          final p = ctrl.players.where((e) => e.id == aliasId).firstOrNull;
          if (p != null) {
            selected.add(p.id);
            continue;
          }
        }

        final key = _norm(extracted.baseName);
        final candidates = ctrl.players
            .where((p) => _norm(p.name) == key)
            .toList(growable: false);

        if (candidates.isEmpty) {
          // Nu avem match exact → modală cu sugestii (fuzzy) + căutare manuală.
          final picked = await _askPickFuzzy(
            typedName: typed,
            allPlayers: ctrl.players,
            suggestedName: extracted.baseName,
            suggestedPermanentGk: extracted.hintPermanentGk,
          );
          if (picked != null) {
            selected.add(picked.id);
            await store.upsertAlias(alias: aliasKey, playerId: picked.id);
          }
          continue;
        }
        if (candidates.length == 1) {
          selected.add(candidates[0].id);
          await store.upsertAlias(alias: aliasKey, playerId: candidates[0].id);
          continue;
        }

        final picked = await _askPickCandidate(
          typedName: typed,
          candidates: candidates,
        );
        if (picked != null) {
          selected.add(picked.id);
          await store.upsertAlias(alias: aliasKey, playerId: picked.id);
        }
      }

      ctrl.setSelection(selected);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import: ${selected.length}/${names.length} selectați.'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 110),
        ),
      );
    } finally {
      if (mounted) setState(() => _importBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SimfController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adaugă listă jucători pentru joc'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Lipește lista de pe WhatsApp (un nume per rând).',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _pasteCtrl,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Ex:\nAlex Z\nAnas\nCristi C',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _importBusy ? null : _importFromWhatsApp,
                        icon: _importBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.playlist_add_check),
                        label: Text(_importBusy ? 'Se importă…' : 'Importă și bifează'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      tooltip: 'Curăță',
                      onPressed: _importBusy
                          ? null
                          : () => setState(() => _pasteCtrl.text = ''),
                      icon: const Icon(Icons.clear),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: ctrl.selectedIds.length < 2
                      ? null
                      : () {
                          try {
                            ctrl.generateTeams();
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const MatchPreviewScreen(),
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
