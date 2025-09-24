/*/*import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/supabase_client.dart';

class HsePage extends StatefulWidget {
  const HsePage({super.key});
  @override
  State<HsePage> createState() => _HsePageState();
}

class _HsePageState extends State<HsePage> {
  final _sb = SB.client;

  // ------- rôle / droits (lecture suffit ici) -------
  String? _role;
  bool _loadingRole = true;

  // ------- ids des états HSE -------
  String? _etatDonneId;
  String? _etatPreteId;

  // cache emplacements
  final Map<String, String> _salleName = {}; // salleId -> 'Salle'
  final Map<String, String> _sallePath = {}; // salleId -> 'Site / Bâtiment / Salle'

  // cache équipements (pour Historique)
  final Map<String, Map<String, dynamic>> _equipCache = {};

  // dates d’entrée en HSE (pour Actuels)
  final Map<String, DateTime> _hseDateByEquip = {}; // equip_id -> created_at (vers donné/prêté)

  // recherche Historique
  final _histSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadHseEtatIds();
  }

  Future<void> _loadRole() async {
    setState(() => _loadingRole = true);
    try {
      final u = _sb.auth.currentUser;
      String? role = u?.userMetadata?['role'] as String?;
      if (u != null) {
        final delays = [0, 300, 800, 1500];
        for (final d in delays) {
          if (d > 0) await Future.delayed(Duration(milliseconds: d));
          try {
            final r = await _sb.from('users').select('role').eq('id', u.id).maybeSingle();
            final dbRole = r?['role'] as String?;
            if (dbRole != null && dbRole.isNotEmpty) { role = dbRole; break; }
          } catch (_) {}
        }
      }
      setState(() => _role = role ?? 'visiteur');
    } finally {
      if (mounted) setState(() => _loadingRole = false);
    }
  }
  /// Sélectionne *plusieurs* lignes avec `col = id` pour chacun des `ids`,
/// en faisant des requêtes simples `.eq()` et en fusionnant les résultats.
/// Compatible avec toutes les versions de supabase-dart.
Future<List<Map<String, dynamic>>> _selectManyByIds(
  String table,
  String col,
  Iterable<String> ids, {
  String cols = '*',
}) async {
  final out = <Map<String, dynamic>>[];
  for (final id in ids.where((e) => e.trim().isNotEmpty)) {
    try {
      final res = await SB.client
          .from(table)
          .select(cols)
          .eq(col, id);
      out.addAll(List<Map<String, dynamic>>.from(res as List));
    } catch (_) {
      // on ignore silencieusement; continue
    }
  }
  return out;
}


  Future<void> _loadHseEtatIds() async {
  try {
    final res = await _sb.from('etats').select('id, nom');
    final list = List<Map<String, dynamic>>.from(res as List);

    _etatNameById.clear();
    String? donneId;
    String? preteId;

    for (final e in list) {
      final id  = e['id'] as String?;
      final nom = (e['nom'] as String?) ?? '';
      if (id == null) continue;

      _etatNameById[id] = nom;
      final k = _normalize(nom); // ex: "prêté" -> "prete", "donné" -> "donne"

      // capture le premier correspondant trouvé (si plusieurs variantes existent)
      if (donneId == null && k == 'donne') donneId = id;
      if (preteId == null && k == 'prete') preteId = id;
    }

    setState(() {
      _etatDonneId = donneId;
      _etatPreteId = preteId;
    });
  } catch (_) {
    // ignore silencieusement; la page fonctionnera quand même via _etatNameById (si possible)
  }
}


  // ==================== Onglet ACTUELS ====================
Widget _buildActuelsTab() {
  // on stream tout puis filtre localement via _isHseEtat
  final stream = _sb
      .from('equipements')
      .stream(primaryKey: ['id'])
      .order('updated_at', ascending: false);

  return Column(
    children: [
      if (_loadingRole) const LinearProgressIndicator(minHeight: 2),

      Expanded(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: stream,
          builder: (_, snap) {
            if (snap.hasError) return Center(child: Text('Erreur: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());

            final all = snap.data!;
            final rows = all.where((e) => _isHseEtat(e['etat_id'])).toList();
            if (rows.isEmpty) {
              return const Center(child: Text('Aucun équipement en état « donné » ou « prêté ».'));
            }

            // précharger emplacements et dates HSE (inchangé)
            _ensureSallePaths(rows.map((e) => e['salle_id'] as String?).whereType<String>().toSet());
            final idsHse = <String>[
              if (_etatDonneId != null) _etatDonneId!,
              if (_etatPreteId != null) _etatPreteId!,
            ];
            _ensureHseDates(rows.map((e) => e['id'] as String?).whereType<String>().toSet(), idsHse);

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(8),
              decoration: _tableBox(),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text(' ')), // info
                    DataColumn(label: Text('N° série')),
                    DataColumn(label: Text('Modèle')),
                    DataColumn(label: Text('Marque')),
                    DataColumn(label: Text('État')),
                    DataColumn(label: Text('Date entrée HSE')),
                    DataColumn(label: Text('Emplacement')),
                    DataColumn(label: Text('Attribué à')),
                  ],
                  rows: rows.map((e) {
                    final sallePath = (e['salle_id'] != null)
                        ? (_sallePath[e['salle_id']] ?? _salleName[e['salle_id']] ?? '—')
                        : '—';
                    final d = _hseDateByEquip[e['id']];
                    return DataRow(cells: [
                      DataCell(IconButton(
                        icon: const Icon(Icons.info_outline),
                        tooltip: 'Détails',
                        onPressed: () => _showEquipDetails(e, sallePath),
                      )),
                      DataCell(Text(e['numero_serie'] ?? '—')),
                      DataCell(Text(e['modele'] ?? '—')),
                      DataCell(Text(e['marque'] ?? '—')),
                      DataCell(Text(_etatLabelFor(e['etat_id']))),
                      DataCell(Text(d == null ? '—' : _fmtTs(d))),
                      DataCell(Text(sallePath)),
                      DataCell(Text(e['attribue_a'] ?? '—')),
                    ]);
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

/*
Widget _buildActuelsTab() {
  final ids = <String>[
    if (_etatDonneId != null) _etatDonneId!,
    if (_etatPreteId != null) _etatPreteId!,
  ];
  if (ids.isEmpty) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Text(
          "Les états « donné » / « prêté » n’ont pas été trouvés.\n"
          "Créez-les dans la table 'etats' pour afficher les équipements HSE.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700),
        ),
      ),
    );
  }

  // On stream tout puis on filtre localement sur etat_id ∈ ids
  final stream = _sb
      .from('equipements')
      .stream(primaryKey: ['id'])
      .order('updated_at', ascending: false);

  return Column(
    children: [
      if (_loadingRole) const LinearProgressIndicator(minHeight: 2),

      Expanded(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: stream,
          builder: (_, snap) {
            if (snap.hasError) return Center(child: Text('Erreur: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());

            final all = snap.data!;
            final rows = all.where((e) => ids.contains(e['etat_id'] as String?)).toList();
            if (rows.isEmpty) {
              return const Center(child: Text('Aucun équipement en état « donné » ou « prêté ».'));
            }

            // précharger emplacements et dates HSE
            _ensureSallePaths(rows.map((e) => e['salle_id'] as String?).whereType<String>().toSet());
            _ensureHseDates(rows.map((e) => e['id'] as String?).whereType<String>().toSet(), ids);

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(8),
              decoration: _tableBox(),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text(' ')), // info
                    DataColumn(label: Text('N° série')),
                    DataColumn(label: Text('Modèle')),
                    DataColumn(label: Text('Marque')),
                    DataColumn(label: Text('État')),
                    DataColumn(label: Text('Date entrée HSE')),
                    DataColumn(label: Text('Emplacement')),
                    DataColumn(label: Text('Attribué à')),
                  ],
                  rows: rows.map((e) {
                    final sallePath = (e['salle_id'] != null)
                        ? (_sallePath[e['salle_id']] ?? _salleName[e['salle_id']] ?? '—')
                        : '—';
                    final d = _hseDateByEquip[e['id']];
                    return DataRow(cells: [
                      DataCell(IconButton(
                        icon: const Icon(Icons.info_outline),
                        tooltip: 'Détails',
                        onPressed: () => _showEquipDetails(e, sallePath),
                      )),
                      DataCell(Text(e['numero_serie'] ?? '—')),
                      DataCell(Text(e['modele'] ?? '—')),
                      DataCell(Text(e['marque'] ?? '—')),
                      DataCell(Text(_etatLabelFor(e['etat_id']))),
                      DataCell(Text(d == null ? '—' : _fmtTs(d))),
                      DataCell(Text(sallePath)),
                      DataCell(Text(e['attribue_a'] ?? '—')),
                    ]);
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}*/
// --- cache des noms d'états ---
final Map<String, String> _etatNameById = {}; // etat_id -> nom

// Normalisation simple: minuscule, sans accents, sans espaces/ponctuation
String _normalize(String s) {
  String x = s.toLowerCase();
  const repl = {
    'à':'a','á':'a','â':'a','ä':'a',
    'ç':'c',
    'é':'e','è':'e','ê':'e','ë':'e',
    'î':'i','ï':'i',
    'ô':'o','ö':'o',
    'ù':'u','ú':'u','û':'u','ü':'u',
    'ÿ':'y',
    'œ':'oe','æ':'ae',
    'ß':'ss',
    '’':"'", // apostrophes courbes -> simples
  };
  repl.forEach((k,v) { x = x.replaceAll(k, v); });
  x = x.replaceAll(RegExp(r'[^a-z0-9]'), ''); // retire ponctuation/espaces
  return x;
}

// Dit si un etat_id correspond à "donné" ou "prêté"
// (utilise les IDs si connus, sinon retombe sur le nom via le cache)
bool _isHseEtat(dynamic etatId) {
  final id = etatId?.toString();
  if (id == null) return false;
  if (_etatDonneId != null && id == _etatDonneId) return true;
  if (_etatPreteId != null && id == _etatPreteId) return true;

  final nom = _etatNameById[id];
  if (nom == null) return false;
  final k = _normalize(nom);
  // toutes les variantes normalisées vont donner 'donne' ou 'prete'
  return (k == 'donne' || k == 'prete');
}


  // date d’entrée en HSE = date de l’événement historique où new_etat_id ∈ {donné, prêté}
  Future<void> _ensureHseDates(Set<String> equipIds, List<String> hseEtatIds) async {
    final missing = equipIds.where((id) => !_hseDateByEquip.containsKey(id)).toSet();
    if (missing.isEmpty) return;
    try {
      final list = List<Map<String, dynamic>>.from(
        await _sb.from('equipements_hist')
          .select('equipement_id, new_etat_id, created_at')
          .filter('equipement_id', 'in', _inCsv(missing))
          .filter('new_etat_id', 'in', _inCsv(hseEtatIds))
          .order('created_at', ascending: false) as List
      );
      // garder la plus RÉCENTE bascule (ou la première, selon votre préférence)
      for (final r in list) {
        final k = r['equipement_id'] as String?;
        if (k == null) continue;
        if (_hseDateByEquip.containsKey(k)) continue; // déjà renseigné par un created_at plus récent
        final d = _parseTs(r['created_at']);
        if (d != null) _hseDateByEquip[k] = d;
      }
      if (mounted) setState(() {});
    } catch (_) {
      // si la table n’existe pas encore → pas de date
    }
  }

  // ==================== Onglet HISTORIQUE ====================
Widget _buildHistoriqueTab() {
  // On stream tout l’historique puis on filtre localement via _isHseEtat(new_etat_id)
  final stream = _sb
      .from('equipements_hist') // nécessite la table d’historique
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false);

  return Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _histSearchCtrl,
                decoration: InputDecoration(
                  hintText: 'Rechercher (date 2025-09-11 ou 11/09/2025, série, modèle, marque, site/salle, e-mail...)',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () { _histSearchCtrl.clear(); setState(() {}); },
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      ),

      Expanded(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: stream,
          builder: (_, snap) {
            if (snap.hasError) {
              final msg = snap.error.toString();
              final friendly = msg.contains('PGRST205')
                  ? "Historique indisponible. Créez la table 'public.equipements_hist' (et ses policies), puis exécutez : NOTIFY pgrst, 'reload schema';"
                  : msg;
              return Center(child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text('Erreur: $friendly'),
              ));
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());

            final all = snap.data!;
            final onlyHse = all.where((r) => _isHseEtat(r['new_etat_id'])).toList();
            if (onlyHse.isEmpty) return const Center(child: Text('Aucun événement HSE (donné/prêté).'));

            _ensureEquipCache(onlyHse.map((r) => r['equipement_id'] as String?).whereType<String>().toSet());

            final q = _histSearchCtrl.text.trim();
            final filtered = onlyHse.where((r) => _histRowMatches(r, q)).toList();
            if (filtered.isEmpty) return const Center(child: Text('Aucun résultat.'));

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(8),
              decoration: _tableBox(),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text(' ')), // info
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Équipement')),
                    DataColumn(label: Text('Nouveau état')),
                    DataColumn(label: Text('Ancien état')),
                    DataColumn(label: Text('Technicien')),
                  ],
                  rows: filtered.map((r) {
                    final e = _equipCache[r['equipement_id']];
                    final equipLabel = (e == null)
                        ? '—'
                        : '${e['numero_serie'] ?? ''} • ${e['modele'] ?? ''} • ${e['marque'] ?? ''}'.trim();
                    return DataRow(cells: [
                      DataCell(IconButton(
                        icon: const Icon(Icons.info_outline),
                        tooltip: 'Détails événement',
                        onPressed: () => _showHistDetails(r, e),
                      )),
                      DataCell(Text(_fmtTs(r['created_at']))),
                      DataCell(Text(equipLabel.isEmpty ? '—' : equipLabel)),
                      DataCell(Text(_etatLabelFor(r['new_etat_id']))),
                      DataCell(Text(_etatLabelFor(r['old_etat_id']))),
                      DataCell(Text(r['created_by_email'] ?? '—')),
                    ]);
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

  
  void _showEquipDetails(Map<String, dynamic> e, String sallePath) {
    showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: const Text('Détails équipement'),
        content: SizedBox(
          width: 460,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            _kv('N° série', e['numero_serie']),
            _kv('Modèle', e['modele']),
            _kv('Marque', e['marque']),
            _kv('Type', e['type']),
            _kv('Emplacement', sallePath),
            _kv('Attribué à', e['attribue_a']),
            _kv('État', _etatLabelFor(e['etat_id'])),
            _kv('Date achat', _fmtDateOnly(e['date_achat'])),
          ]),
        ),
        actions: [TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Fermer'))],
      );
    });
  }

  void _showHistDetails(Map<String, dynamic> r, Map<String, dynamic>? e) {
    final equipLabel = (e == null)
        ? '—'
        : '${e['numero_serie'] ?? ''} • ${e['modele'] ?? ''} • ${e['marque'] ?? ''}'.trim();
    showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: const Text('Détails HSE'),
        content: SizedBox(
          width: 480,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            _kv('Équipement', equipLabel),
            _kv('Date', _fmtTs(r['created_at'])),
            _kv('Ancien état', _etatLabelFor(r['old_etat_id'])),
            _kv('Nouveau état', _etatLabelFor(r['new_etat_id'])),
            _kv('Technicien', r['created_by_email']),
          ]),
        ),
        actions: [TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Fermer'))],
      );
    });
  }

  // ==================== Helpers data ====================

  // label pour etat_id (très simple ici)
 String _etatLabelFor(dynamic etatId) {
  final id = etatId?.toString();
  if (id == null) return '—';
  // si on a le nom exact en cache, l'utiliser
  final fromCache = _etatNameById[id];
  if (fromCache != null && fromCache.trim().isNotEmpty) return fromCache;

  // sinon, labels minimaux pour HSE
  if (_etatDonneId != null && id == _etatDonneId) return 'donné';
  if (_etatPreteId != null && id == _etatPreteId) return 'prêté';
  return '—';
}


  Future<void> _ensureEquipCache(Set<String> ids) async {
    final missing = ids.where((id) => !_equipCache.containsKey(id)).toSet();
    if (missing.isEmpty) return;
    try {
      final list = List<Map<String, dynamic>>.from(
        await _sb.from('equipements')
          .select('id, numero_serie, modele, marque, type, salle_id')
          .filter('id', 'in', _inCsv(missing)) as List
      );
      for (final m in list) {
        _equipCache[m['id'] as String] = m;
      }
      _ensureSallePaths(list.map((e) => e['salle_id'] as String?).whereType<String>().toSet());
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _ensureSallePaths(Set<String> ids) async {
    final missing = ids.where((id) => !_sallePath.containsKey(id)).toSet();
    if (missing.isEmpty) return;

    try {
      final salles = List<Map<String, dynamic>>.from(
        await _sb.from('salles').select('id, nom, batiment_id').filter('id','in', _inCsv(missing)) as List
      );
      for (final s in salles) _salleName[s['id'] as String] = (s['nom'] as String?) ?? '—';

      final batIds = salles.map((s) => s['batiment_id'] as String?).whereType<String>().toSet();
      if (batIds.isEmpty) return;

      final bats = List<Map<String, dynamic>>.from(
        await _sb.from('batiments').select('id, nom, site_id').filter('id','in', _inCsv(batIds)) as List
      );

      final siteIds = bats.map((b) => b['site_id'] as String?).whereType<String>().toSet();
      final sites = siteIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await _sb.from('sites').select('id, nom').filter('id','in', _inCsv(siteIds)) as List
            );

      final batById  = { for (final b in bats)  b['id'] as String : b };
      final siteById = { for (final s in sites) s['id'] as String : s };

      for (final s in salles) {
        final b = batById[s['batiment_id']];
        final siteName = (b != null && siteById[b['site_id']] != null)
            ? (siteById[b['site_id']]?['nom'] as String? ?? '—')
            : '—';
        final batName  = b != null ? (b['nom'] as String? ?? '—') : '—';
        final salName  = (s['nom'] as String?) ?? '—';
        _sallePath[s['id'] as String] = '$siteName / $batName / $salName';
      }

      if (mounted) setState(() {});
    } catch (_) {}
  }

  // filtre “intelligent” sur historique
  bool _histRowMatches(Map<String, dynamic> r, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;

    // date
    final qDate = _tryParseUserDate(q);
    if (qDate != null) {
      if (_sameDay(_parseTs(r['created_at']), qDate)) return true;
    }

    // textes
    final e = _equipCache[r['equipement_id']];
    final strings = <String>[
      r['created_by_email']?.toString() ?? '',
      _etatLabelFor(r['new_etat_id']),
      _etatLabelFor(r['old_etat_id']),
      if (e != null) ...[
        e['numero_serie']?.toString() ?? '',
        e['modele']?.toString() ?? '',
        e['marque']?.toString() ?? '',
        e['type']?.toString() ?? '',
        _sallePath[e['salle_id']] ?? _salleName[e['salle_id']] ?? '',
      ]
    ].map((s) => s.toLowerCase()).toList();

    return strings.any((s) => s.contains(q));
  }

  // ==================== Helpers UI / format ====================

  static BoxDecoration _tableBox() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0,3))],
  );

  static Widget _kv(String k, dynamic v) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      SizedBox(width: 160, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
      Expanded(child: Text(v?.toString() ?? '—')),
    ]),
  );

  static String _inCsv(Iterable<String> ids) => '(${ids.map((e) => '"$e"').join(',')})';

  static DateTime? _tryParseUserDate(String q) {
    String s = q.trim();
    final re = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$'); // dd/mm/yyyy
    final m = re.firstMatch(s);
    if (m != null) {
      s = '${m.group(3)}-${m.group(2)!.padLeft(2, '0')}-${m.group(1)!.padLeft(2, '0')}';
    }
    try {
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
        return DateTime.parse('$s 00:00:00');
      }
    } catch (_) {}
    return null;
  }

  static bool _sameDay(DateTime? a, DateTime b) {
    if (a == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String _fmtDateOnly(dynamic ts) {
    final d = _parseTs(ts); if (d == null) return '—';
    return '${d.year}-${_2(d.month)}-${_2(d.day)}';
  }

  static String _fmtTs(dynamic ts) {
    final d = _parseTs(ts); if (d == null) return '—';
    return '${d.year}-${_2(d.month)}-${_2(d.day)} ${_2(d.hour)}:${_2(d.minute)}';
  }

  static DateTime? _parseTs(dynamic ts) {
    if (ts == null) return null;
    try { return DateTime.parse(ts.toString()).toLocal(); } catch (_) { return null; }
  }

  static String _2(int x) => x.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: TabBar(tabs: [Tab(text: 'Actuels'), Tab(text: 'Historique')]),
          ),
          Expanded(
            child: TabBarView(children: [
              _HseActuelsHost(),
              _HseHistoriqueHost(),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Petits hôtes pour forcer la reconstruction des onglets avec le State parent.
class _HseActuelsHost extends StatelessWidget {
  const _HseActuelsHost();
  @override
  Widget build(BuildContext context) {
    return (context.findAncestorStateOfType<_HsePageState>()!)._buildActuelsTab();
  }
}

class _HseHistoriqueHost extends StatelessWidget {
  const _HseHistoriqueHost();
  @override
  Widget build(BuildContext context) {
    return (context.findAncestorStateOfType<_HsePageState>()!)._buildHistoriqueTab();
  }
}*/
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/supabase_client.dart';

class HsePage extends StatefulWidget {
  const HsePage({super.key});
  @override
  State<HsePage> createState() => _HsePageState();
}

class _HsePageState extends State<HsePage> {
  final _sb = SB.client;

  // ------- rôle / droits (lecture suffit ici) -------
  String? _role;
  bool _loadingRole = true;

  // ------- ids des états HSE (seulement donné + mis au rebut) -------
  String? _etatDonneId;
  String? _etatRebutId;

  // cache emplacements
  final Map<String, String> _salleName = {}; // salleId -> 'Salle'
  final Map<String, String> _sallePath = {}; // salleId -> 'Site / Bâtiment / Salle'

  // cache équipements (pour Historique)
  final Map<String, Map<String, dynamic>> _equipCache = {};

  // dates d’entrée HSE (pour Actuels)
  final Map<String, DateTime> _hseDateByEquip = {}; // equip_id -> created_at (vers donné/rebut)

  // recherche Historique
  final _histSearchCtrl = TextEditingController();

  // --- cache des noms d'états ---
  final Map<String, String> _etatNameById = {}; // etat_id -> nom

  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadHseEtatIds();
  }
  

  Future<void> _loadRole() async {
    setState(() => _loadingRole = true);
    try {
      final u = _sb.auth.currentUser;
      String? role = u?.userMetadata?['role'] as String?;
      if (u != null) {
        final delays = [0, 300, 800, 1500];
        for (final d in delays) {
          if (d > 0) await Future.delayed(Duration(milliseconds: d));
          try {
            final r = await _sb.from('users').select('role').eq('id', u.id).maybeSingle();
            final dbRole = r?['role'] as String?;
            if (dbRole != null && dbRole.isNotEmpty) { role = dbRole; break; }
          } catch (_) {}
        }
      }
      setState(() => _role = role ?? 'visiteur');
    } finally {
      if (mounted) setState(() => _loadingRole = false);
    }
  }

  Future<void> _loadHseEtatIds() async {
    try {
      final res = await _sb.from('etats').select('id, nom');
      final list = List<Map<String, dynamic>>.from(res as List);

      _etatNameById.clear();
      String? donneId;
      String? rebutId;

      for (final e in list) {
        final id  = e['id'] as String?;
        final nom = (e['nom'] as String?) ?? '';
        if (id == null) continue;

        _etatNameById[id] = nom;
        final k = _normalize(nom); // ex: "mis au rebut" -> "misaurebut", "donné" -> "donne"

        if (donneId == null && k == 'donne') donneId = id;
        if (rebutId == null && (k.contains('rebut') || k == 'misaurebut')) rebutId = id;
      }

      setState(() {
        _etatDonneId = donneId;
        _etatRebutId = rebutId;
      });
    } catch (_) {
      // silencieux
    }
  }
  

  // ==================== Onglet ACTUELS ====================
  Widget _buildActuelsTab() {
    // on stream tout puis filtre localement via _isHseEtat (donné/rebut)
    final stream = _sb
        .from('equipements')
        .stream(primaryKey: ['id'])
        .order('updated_at', ascending: false);

    return Column(
      children: [
        if (_loadingRole) const LinearProgressIndicator(minHeight: 2),

        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: stream,
            builder: (_, snap) {
              if (snap.hasError) return Center(child: Text('Erreur: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());

              final all = snap.data!;
              final rows = all.where((e) => _isHseEtat(e['etat_id'])).toList();
              if (rows.isEmpty) {
                return const Center(child: Text('Aucun équipement en état « donné » ou « mis au rebut ».'));
              }

              // précharger emplacements et dates HSE
              _ensureSallePaths(rows.map((e) => e['salle_id'] as String?).whereType<String>().toSet());
              final idsHse = <String>[
                if (_etatDonneId != null) _etatDonneId!,
                if (_etatRebutId != null) _etatRebutId!,
              ];
              _ensureHseDates(rows.map((e) => e['id'] as String?).whereType<String>().toSet(), idsHse);

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(8),
                decoration: _tableBox(),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text(' ')), // info
                      DataColumn(label: Text('N° série')),
                      DataColumn(label: Text('Modèle')),
                      DataColumn(label: Text('Marque')),
                      DataColumn(label: Text('État')),
                      DataColumn(label: Text('Date entrée HSE')),
                      DataColumn(label: Text('Emplacement')),
                      DataColumn(label: Text('Attribué à')),
                    ],
                    rows: rows.map((e) {
                      final sallePath = (e['salle_id'] != null)
                          ? (_sallePath[e['salle_id']] ?? _salleName[e['salle_id']] ?? '—')
                          : '—';
                      final d = _hseDateByEquip[e['id']];
                      return DataRow(cells: [
                        DataCell(IconButton(
                          icon: const Icon(Icons.info_outline),
                          tooltip: 'Détails',
                          onPressed: () => _showEquipDetails(e, sallePath),
                        )),
                        DataCell(Text(e['numero_serie'] ?? '—')),
                        DataCell(Text(e['modele'] ?? '—')),
                        DataCell(Text(e['marque'] ?? '—')),
                        DataCell(Text(_etatLabelFor(e['etat_id']))),
                        DataCell(Text(d == null ? '—' : _fmtTs(d))),
                        DataCell(Text(sallePath)),
                        DataCell(Text(e['attribue_a'] ?? '—')),
                      ]);
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==================== Onglet HISTORIQUE ====================
  Widget _buildHistoriqueTab() {
    // On stream tout l’historique puis on filtre localement via _isHseEtat(new_etat_id)
    final stream = _sb
        .from('equipements_hist') // nécessite la table d’historique
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _histSearchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Rechercher',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () { _histSearchCtrl.clear(); setState(() {}); },
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: stream,
            builder: (_, snap) {
              if (snap.hasError) {
                final msg = snap.error.toString();
                final friendly = msg.contains('PGRST205')
                    ? "Historique indisponible."
                    : msg;
                return Center(child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text('Erreur: $friendly'),
                ));
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());

              final all = snap.data!;
              final onlyHse = all.where((r) => _isHseEtat(r['new_etat_id'])).toList();
              if (onlyHse.isEmpty) return const Center(child: Text('Aucun événement HSE (donné/mis au rebut).'));

              _ensureEquipCache(onlyHse.map((r) => r['equipement_id'] as String?).whereType<String>().toSet());

              final q = _histSearchCtrl.text.trim();
              final filtered = onlyHse.where((r) => _histRowMatches(r, q)).toList();
              if (filtered.isEmpty) return const Center(child: Text('Aucun résultat.'));

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(8),
                decoration: _tableBox(),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text(' ')), // info
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Équipement')),
                      DataColumn(label: Text('Nouveau état')),
                      DataColumn(label: Text('Ancien état')),
                      DataColumn(label: Text('Technicien')),
                    ],
                    rows: filtered.map((r) {
                      final e = _equipCache[r['equipement_id']];
                      final equipLabel = (e == null)
                          ? '—'
                          : '${e['numero_serie'] ?? ''} • ${e['modele'] ?? ''} • ${e['marque'] ?? ''}'.trim();
                      return DataRow(cells: [
                        DataCell(IconButton(
                          icon: const Icon(Icons.info_outline),
                          tooltip: 'Détails événement',
                          onPressed: () => _showHistDetails(r, e),
                        )),
                        DataCell(Text(_fmtTs(r['created_at']))),
                        DataCell(Text(equipLabel.isEmpty ? '—' : equipLabel)),
                        DataCell(Text(_etatLabelFor(r['new_etat_id']))),
                        DataCell(Text(_etatLabelFor(r['old_etat_id']))),
                        DataCell(Text(r['created_by_email'] ?? '—')),
                      ]);
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==================== Helpers de sélection ====================
  

  // Dit si etat_id correspond à "donné" ou "mis au rebut"
  bool _isHseEtat(dynamic etatId) {
    final id = etatId?.toString();
    if (id == null) return false;
    if (_etatDonneId != null && id == _etatDonneId) return true;
    if (_etatRebutId != null && id == _etatRebutId) return true;

    final nom = _etatNameById[id];
    if (nom == null) return false;
    final k = _normalize(nom);
    return (k == 'donne' || k.contains('rebut') || k == 'misaurebut');
  }
bool _histRowMatches(Map<String, dynamic> r, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;

  // Match sur la DATE (YYYY-MM-DD ou DD/MM/YYYY)
  final qDate = _tryParseUserDate(q);
  if (qDate != null && _sameDay(_parseTs(r['created_at']), qDate)) {
    return true;
  }

  // Match sur texte: technicien, états, infos équipement, emplacement
  final e = _equipCache[r['equipement_id']];
  final strings = <String>[
    r['created_by_email']?.toString() ?? '',
    _etatLabelFor(r['new_etat_id']),
    _etatLabelFor(r['old_etat_id']),
    if (e != null) ...[
      e['numero_serie']?.toString() ?? '',
      e['modele']?.toString() ?? '',
      e['marque']?.toString() ?? '',
      e['type']?.toString() ?? '',
      _sallePath[e['salle_id']] ?? _salleName[e['salle_id']] ?? '',
    ],
  ].map((s) => s.toLowerCase()).toList();

  return strings.any((s) => s.contains(q));
}

  // date d’entrée en HSE = date de l’événement historique où new_etat_id ∈ {donné, mis au rebut}
  Future<void> _ensureHseDates(Set<String> equipIds, List<String> hseEtatIds) async {
    final missing = equipIds.where((id) => !_hseDateByEquip.containsKey(id)).toSet();
    if (missing.isEmpty) return;
    if (hseEtatIds.isEmpty) return;
    try {
      final list = List<Map<String, dynamic>>.from(
        await _sb.from('equipements_hist')
            .select('equipement_id, new_etat_id, created_at')
            .filter('equipement_id', 'in', _inCsv(missing))
            .filter('new_etat_id', 'in', _inCsv(hseEtatIds))
            .order('created_at', ascending: false) as List
      );
      // on garde la bascule la PLUS RÉCENTE vers HSE
      for (final r in list) {
        final k = r['equipement_id'] as String?;
        if (k == null) continue;
        if (_hseDateByEquip.containsKey(k)) continue; // déjà renseigné (créé plus récent)
        final d = _parseTs(r['created_at']);
        if (d != null) _hseDateByEquip[k] = d;
      }
      if (mounted) setState(() {});
    } catch (_) {
      // si la table n’existe pas encore → pas de date
    }
  }

  Future<void> _ensureEquipCache(Set<String> ids) async {
    final missing = ids.where((id) => !_equipCache.containsKey(id)).toSet();
    if (missing.isEmpty) return;
    try {
      final list = List<Map<String, dynamic>>.from(
        await _sb.from('equipements')
            .select('id, numero_serie, modele, marque, type, host_name, salle_id')
            .filter('id', 'in', _inCsv(missing)) as List
      );
      for (final m in list) {
        _equipCache[m['id'] as String] = m;
      }
      _ensureSallePaths(list.map((e) => e['salle_id'] as String?).whereType<String>().toSet());
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _ensureSallePaths(Set<String> ids) async {
    final missing = ids.where((id) => !_sallePath.containsKey(id)).toSet();
    if (missing.isEmpty) return;

    try {
      final salles = List<Map<String, dynamic>>.from(
        await _sb.from('salles').select('id, nom, batiment_id').filter('id','in', _inCsv(missing)) as List
      );
      for (final s in salles) _salleName[s['id'] as String] = (s['nom'] as String?) ?? '—';

      final batIds = salles.map((s) => s['batiment_id'] as String?).whereType<String>().toSet();
      if (batIds.isEmpty) return;

      final bats = List<Map<String, dynamic>>.from(
        await _sb.from('batiments').select('id, nom, site_id').filter('id','in', _inCsv(batIds)) as List
      );

      final siteIds = bats.map((b) => b['site_id'] as String?).whereType<String>().toSet();
      final sites = siteIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await _sb.from('sites').select('id, nom').filter('id','in', _inCsv(siteIds)) as List
            );

      final batById  = { for (final b in bats)  b['id'] as String : b };
      final siteById = { for (final s in sites) s['id'] as String : s };

      for (final s in salles) {
        final b = batById[s['batiment_id']];
        final siteName = (b != null && siteById[b['site_id']] != null)
            ? (siteById[b['site_id']]?['nom'] as String? ?? '—')
            : '—';
        final batName  = b != null ? (b['nom'] as String? ?? '—') : '—';
        final salName  = (s['nom'] as String?) ?? '—';
        _sallePath[s['id'] as String] = '$siteName / $batName / $salName';
      }

      if (mounted) setState(() {});
    } catch (_) {}
  }

  // ==================== UI dialogs ====================

  void _showEquipDetails(Map<String, dynamic> e, String sallePath) {
    showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: const Text('Détails équipement'),
        content: SizedBox(
          width: 460,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            _kv('N° série', e['numero_serie']),
            _kv('Modèle', e['modele']),
            _kv('Marque', e['marque']),
            _kv('Type', e['type']),
            _kv('Emplacement', sallePath),
            _kv('Attribué à', e['attribue_a']),
            _kv('État', _etatLabelFor(e['etat_id'])),
            _kv('Date achat', _fmtDateOnly(e['date_achat'])),
          ]),
        ),
        actions: [TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Fermer'))],
      );
    });
  }

  void _showHistDetails(Map<String, dynamic> r, Map<String, dynamic>? e) {
    final equipLabel = (e == null)
        ? '—'
        : '${e['numero_serie'] ?? ''} • ${e['host_name'] ?? ''} • ${e['marque'] ?? ''}'.trim();
    showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: const Text('Détails HSE'),
        content: SizedBox(
          width: 480,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            _kv('Équipement', equipLabel),
            _kv('Date', _fmtTs(r['created_at'])),
            _kv('Ancien état', _etatLabelFor(r['old_etat_id'])),
            _kv('Nouveau état', _etatLabelFor(r['new_etat_id'])),
            _kv('Technicien', r['created_by_email']),
          ]),
        ),
        actions: [TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Fermer'))],
      );
    });
  }

  // ==================== Helpers divers ====================

  String _etatLabelFor(dynamic etatId) {
    final id = etatId?.toString();
    if (id == null) return '—';
    final fromCache = _etatNameById[id];
    if (fromCache != null && fromCache.trim().isNotEmpty) return fromCache;
    if (_etatDonneId != null && id == _etatDonneId) return 'donné';
    if (_etatRebutId != null && id == _etatRebutId) return 'mis au rebut';
    return '—';
  }

  // Normalisation simple: minuscule + accents retirés + sans ponctuation/espaces
  String _normalize(String s) {
    String x = s.toLowerCase();
    const repl = {
      'à':'a','á':'a','â':'a','ä':'a',
      'ç':'c',
      'é':'e','è':'e','ê':'e','ë':'e',
      'î':'i','ï':'i',
      'ô':'o','ö':'o',
      'ù':'u','ú':'u','û':'u','ü':'u',
      'ÿ':'y',
      'œ':'oe','æ':'ae',
      'ß':'ss',
      '’':"'", // apostrophes courbes -> simples
    };
    repl.forEach((k,v) { x = x.replaceAll(k, v); });
    x = x.replaceAll(RegExp(r'[^a-z0-9]'), ''); // retire ponctuation/espaces
    return x;
  }

  static BoxDecoration _tableBox() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0,3))],
  );

  static Widget _kv(String k, dynamic v) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      SizedBox(width: 160, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
      Expanded(child: Text(v?.toString() ?? '—')),
    ]),
  );

  static String _inCsv(Iterable<String> ids) => '(${ids.map((e) => '"$e"').join(',')})';

  static DateTime? _tryParseUserDate(String q) {
    String s = q.trim();
    final re = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$'); // dd/mm/yyyy
    final m = re.firstMatch(s);
    if (m != null) {
      s = '${m.group(3)}-${m.group(2)!.padLeft(2, '0')}-${m.group(1)!.padLeft(2, '0')}';
    }
    try {
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
        return DateTime.parse('$s 00:00:00');
      }
    } catch (_) {}
    return null;
  }

  static bool _sameDay(DateTime? a, DateTime b) {
    if (a == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String _fmtDateOnly(dynamic ts) {
    final d = _parseTs(ts); if (d == null) return '—';
    return '${d.year}-${_2(d.month)}-${_2(d.day)}';
  }

  static String _fmtTs(dynamic ts) {
    final d = _parseTs(ts); if (d == null) return '—';
    return '${d.year}-${_2(d.month)}-${_2(d.day)} ${_2(d.hour)}:${_2(d.minute)}';
  }

  static DateTime? _parseTs(dynamic ts) {
    if (ts == null) return null;
    try { return DateTime.parse(ts.toString()).toLocal(); } catch (_) { return null; }
  }

  static String _2(int x) => x.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: TabBar(tabs: [Tab(text: 'Actuels'), Tab(text: 'Historique')]),
          ),
          Expanded(
            child: TabBarView(children: [
              _HseActuelsHost(),
              _HseHistoriqueHost(),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Petits hôtes pour forcer la reconstruction des onglets avec le State parent.
class _HseActuelsHost extends StatelessWidget {
  const _HseActuelsHost();
  @override
  Widget build(BuildContext context) {
    return (context.findAncestorStateOfType<_HsePageState>()!)._buildActuelsTab();
  }
}

class _HseHistoriqueHost extends StatelessWidget {
  const _HseHistoriqueHost();
  @override
  Widget build(BuildContext context) {
    return (context.findAncestorStateOfType<_HsePageState>()!)._buildHistoriqueTab();
  }
}
*/
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/supabase_client.dart';
import 'package:gepi/pages/pdf_exporter.dart'; // <- export PDF

class HsePage extends StatefulWidget {
  const HsePage({super.key});
  @override
  State<HsePage> createState() => _HsePageState();
}

class _HsePageState extends State<HsePage> {
  final _sb = SB.client;

  // ------- rôle / droits (lecture suffit ici) -------
  String? _role;
  bool _loadingRole = true;

  // ------- ids des états HSE (seulement donné + mis au rebut) -------
  String? _etatDonneId;
  String? _etatRebutId;

  // cache emplacements
  final Map<String, String> _salleName = {}; // salleId -> 'Salle'
  final Map<String, String> _sallePath = {}; // salleId -> 'Site / Bâtiment / Salle'

  // cache équipements (pour Historique)
  final Map<String, Map<String, dynamic>> _equipCache = {};

  // dates d’entrée HSE (pour Actuels)
  final Map<String, DateTime> _hseDateByEquip = {}; // equip_id -> created_at (vers donné/rebut)

  // recherche Historique
  final _histSearchCtrl = TextEditingController();

  // --- cache des noms d'états ---
  final Map<String, String> _etatNameById = {}; // etat_id -> nom

  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadHseEtatIds();
  }

  Future<void> _loadRole() async {
    setState(() => _loadingRole = true);
    try {
      final u = _sb.auth.currentUser;
      String? role = u?.userMetadata?['role'] as String?;
      if (u != null) {
        final delays = [0, 300, 800, 1500];
        for (final d in delays) {
          if (d > 0) await Future.delayed(Duration(milliseconds: d));
          try {
            final r = await _sb.from('users').select('role').eq('id', u.id).maybeSingle();
            final dbRole = r?['role'] as String?;
            if (dbRole != null && dbRole.isNotEmpty) { role = dbRole; break; }
          } catch (_) {}
        }
      }
      setState(() => _role = role ?? 'visiteur');
    } finally {
      if (mounted) setState(() => _loadingRole = false);
    }
  }

  Future<void> _loadHseEtatIds() async {
    try {
      final res = await _sb.from('etats').select('id, nom');
      final list = List<Map<String, dynamic>>.from(res as List);

      _etatNameById.clear();
      String? donneId;
      String? rebutId;

      for (final e in list) {
        final id  = e['id'] as String?;
        final nom = (e['nom'] as String?) ?? '';
        if (id == null) continue;

        _etatNameById[id] = nom;
        final k = _normalize(nom); // ex: "mis au rebut" -> "misaurebut", "donné" -> "donne"

        if (donneId == null && k == 'donne') donneId = id;
        if (rebutId == null && (k.contains('rebut') || k == 'misaurebut')) rebutId = id;
      }

      setState(() {
        _etatDonneId = donneId;
        _etatRebutId = rebutId;
      });
    } catch (_) {
      // silencieux
    }
  }

  // ==================== EXPORTS PDF ====================

  Future<void> _exportActuels(List<Map<String, dynamic>> rows) async {
    final headers = ['N° série','Modèle','Marque','État','Date entrée HSE','Emplacement','Attribué à'];
    final data = rows.map((e) {
      final sallePath = (e['salle_id'] != null)
          ? (_sallePath[e['salle_id']] ?? _salleName[e['salle_id']] ?? '—')
          : '—';
      final d = _hseDateByEquip[e['id']];
      return [
        (e['numero_serie'] ?? '—').toString(),
        (e['modele'] ?? '—').toString(),
        (e['marque'] ?? '—').toString(),
        _etatLabelFor(e['etat_id']),
        d == null ? '—' : _fmtTs(d.toIso8601String()),
        sallePath,
        (e['attribue_a'] ?? '—').toString(),
      ];
    }).toList();

    await PdfExporter.exportDataTable(
      title: 'Équipements HSE (donné / mis au rebut)',
      subtitle: 'Export du tableau — onglet Actuels',
      headers: headers,
      rows: data,
      landscape: true,
    );
  }

  Future<void> _exportHistorique(List<Map<String, dynamic>> rows) async {
    final headers = ['Date','Équipement','Nouveau état','Ancien état','Technicien'];
    final data = rows.map((r) {
      final e = _equipCache[r['equipement_id']];
      final equipLabel = (e == null)
          ? '—'
          : '${e['numero_serie'] ?? ''} • ${e['modele'] ?? ''} • ${e['marque'] ?? ''}'.trim();
      return [
        _fmtTs(r['created_at']),
        equipLabel.isEmpty ? '—' : equipLabel,
        _etatLabelFor(r['new_etat_id']),
        _etatLabelFor(r['old_etat_id']),
        (r['created_by_email'] ?? '—').toString(),
      ];
    }).toList();

    await PdfExporter.exportDataTable(
      title: 'Historique HSE',
      subtitle: 'Export du tableau — onglet Historique',
      headers: headers,
      rows: data,
      landscape: true,
    );
  }

  // ==================== Onglet ACTUELS ====================
  Widget _buildActuelsTab() {
    // on stream tout puis filtre localement via _isHseEtat (donné/rebut)
    final stream = _sb
        .from('equipements')
        .stream(primaryKey: ['id'])
        .order('updated_at', ascending: false);

    return Column(
      children: [
        if (_loadingRole) const LinearProgressIndicator(minHeight: 2),

        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: stream,
            builder: (_, snap) {
              if (snap.hasError) return Center(child: Text('Erreur: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());

              final all = snap.data!;
              final rows = all.where((e) => _isHseEtat(e['etat_id'])).toList();
              if (rows.isEmpty) {
                return const Center(child: Text('Aucun équipement en état « donné » ou « mis au rebut ».'));
              }

              // précharger emplacements et dates HSE
              _ensureSallePaths(rows.map((e) => e['salle_id'] as String?).whereType<String>().toSet());
              final idsHse = <String>[
                if (_etatDonneId != null) _etatDonneId!,
                if (_etatRebutId != null) _etatRebutId!,
              ];
              _ensureHseDates(rows.map((e) => e['id'] as String?).whereType<String>().toSet(), idsHse);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left:16, right:16, bottom:6),
                    child: Row(
                      children: [
                        Chip(label: Text('${rows.length} résultat${rows.length>1?'s':''}')),
                        const Spacer(),
                        Tooltip(
                          message: 'Télécharger en PDF',
                          child: IconButton(
                            icon: const Icon(Icons.download),
                            onPressed: () => _exportActuels(rows),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: _tableBox(),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text(' ')), // info
                              DataColumn(label: Text('N° série')),
                              DataColumn(label: Text('Modèle')),
                              DataColumn(label: Text('Marque')),
                              DataColumn(label: Text('État')),
                              DataColumn(label: Text('Date entrée HSE')),
                              DataColumn(label: Text('Emplacement')),
                              DataColumn(label: Text('Attribué à')),
                            ],
                            rows: rows.map((e) {
                              final sallePath = (e['salle_id'] != null)
                                  ? (_sallePath[e['salle_id']] ?? _salleName[e['salle_id']] ?? '—')
                                  : '—';
                              final d = _hseDateByEquip[e['id']];
                              return DataRow(cells: [
                                DataCell(IconButton(
                                  icon: const Icon(Icons.info_outline),
                                  tooltip: 'Détails',
                                  onPressed: () => _showEquipDetails(e, sallePath),
                                )),
                                DataCell(Text(e['numero_serie'] ?? '—')),
                                DataCell(Text(e['modele'] ?? '—')),
                                DataCell(Text(e['marque'] ?? '—')),
                                DataCell(Text(_etatLabelFor(e['etat_id']))),
                                DataCell(Text(d == null ? '—' : _fmtTs(d.toIso8601String()))),
                                DataCell(Text(sallePath)),
                                DataCell(Text(e['attribue_a'] ?? '—')),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ==================== Onglet HISTORIQUE ====================
  Widget _buildHistoriqueTab() {
    // On stream tout l’historique puis on filtre localement via _isHseEtat(new_etat_id)
    final stream = _sb
        .from('equipements_hist') // nécessite la table d’historique
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _histSearchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Rechercher',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () { _histSearchCtrl.clear(); setState(() {}); },
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: stream,
            builder: (_, snap) {
              if (snap.hasError) {
                final msg = snap.error.toString();
                final friendly = msg.contains('PGRST205')
                    ? "Historique indisponible."
                    : msg;
                return Center(child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text('Erreur: $friendly'),
                ));
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());

              final all = snap.data!;
              final onlyHse = all.where((r) => _isHseEtat(r['new_etat_id'])).toList();
              if (onlyHse.isEmpty) return const Center(child: Text('Aucun événement HSE (donné/mis au rebut).'));

              _ensureEquipCache(onlyHse.map((r) => r['equipement_id'] as String?).whereType<String>().toSet());

              final q = _histSearchCtrl.text.trim();
              final filtered = onlyHse.where((r) => _histRowMatches(r, q)).toList();
              if (filtered.isEmpty) return const Center(child: Text('Aucun résultat.'));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left:16, right:16, bottom:6),
                    child: Row(
                      children: [
                        Chip(label: Text('${filtered.length} événement${filtered.length>1?'s':''}')),
                        const Spacer(),
                        Tooltip(
                          message: 'Télécharger en PDF',
                          child: IconButton(
                            icon: const Icon(Icons.download),
                            onPressed: () => _exportHistorique(filtered),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: _tableBox(),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text(' ')), // info
                              DataColumn(label: Text('Date')),
                              DataColumn(label: Text('Équipement')),
                              DataColumn(label: Text('Nouveau état')),
                              DataColumn(label: Text('Ancien état')),
                              DataColumn(label: Text('Technicien')),
                            ],
                            rows: filtered.map((r) {
                              final e = _equipCache[r['equipement_id']];
                              final equipLabel = (e == null)
                                  ? '—'
                                  : '${e['numero_serie'] ?? ''} • ${e['modele'] ?? ''} • ${e['marque'] ?? ''}'.trim();
                              return DataRow(cells: [
                                DataCell(IconButton(
                                  icon: const Icon(Icons.info_outline),
                                  tooltip: 'Détails événement',
                                  onPressed: () => _showHistDetails(r, e),
                                )),
                                DataCell(Text(_fmtTs(r['created_at']))),
                                DataCell(Text(equipLabel.isEmpty ? '—' : equipLabel)),
                                DataCell(Text(_etatLabelFor(r['new_etat_id']))),
                                DataCell(Text(_etatLabelFor(r['old_etat_id']))),
                                DataCell(Text(r['created_by_email'] ?? '—')),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ==================== Helpers de sélection ====================

  // Dit si etat_id correspond à "donné" ou "mis au rebut"
  bool _isHseEtat(dynamic etatId) {
    final id = etatId?.toString();
    if (id == null) return false;
    if (_etatDonneId != null && id == _etatDonneId) return true;
    if (_etatRebutId != null && id == _etatRebutId) return true;

    final nom = _etatNameById[id];
    if (nom == null) return false;
    final k = _normalize(nom);
    return (k == 'donne' || k.contains('rebut') || k == 'misaurebut');
  }

  bool _histRowMatches(Map<String, dynamic> r, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;

    // Match sur la DATE (YYYY-MM-DD ou DD/MM/YYYY)
    final qDate = _tryParseUserDate(q);
    if (qDate != null && _sameDay(_parseTs(r['created_at']), qDate)) {
      return true;
    }

    // Match sur texte: technicien, états, infos équipement, emplacement
    final e = _equipCache[r['equipement_id']];
    final strings = <String>[
      r['created_by_email']?.toString() ?? '',
      _etatLabelFor(r['new_etat_id']),
      _etatLabelFor(r['old_etat_id']),
      if (e != null) ...[
        e['numero_serie']?.toString() ?? '',
        e['modele']?.toString() ?? '',
        e['marque']?.toString() ?? '',
        e['type']?.toString() ?? '',
        _sallePath[e['salle_id']] ?? _salleName[e['salle_id']] ?? '',
      ],
    ].map((s) => s.toLowerCase()).toList();

    return strings.any((s) => s.contains(q));
  }

  // date d’entrée en HSE = date de l’événement historique où new_etat_id ∈ {donné, mis au rebut}
  Future<void> _ensureHseDates(Set<String> equipIds, List<String> hseEtatIds) async {
    final missing = equipIds.where((id) => !_hseDateByEquip.containsKey(id)).toSet();
    if (missing.isEmpty) return;
    if (hseEtatIds.isEmpty) return;
    try {
      final list = List<Map<String, dynamic>>.from(
        await _sb.from('equipements_hist')
            .select('equipement_id, new_etat_id, created_at')
            .filter('equipement_id', 'in', _inCsv(missing))
            .filter('new_etat_id', 'in', _inCsv(hseEtatIds))
            .order('created_at', ascending: false) as List
      );
      // on garde la bascule la PLUS RÉCENTE vers HSE
      for (final r in list) {
        final k = r['equipement_id'] as String?;
        if (k == null) continue;
        if (_hseDateByEquip.containsKey(k)) continue; // déjà renseigné (créé plus récent)
        final d = _parseTs(r['created_at']);
        if (d != null) _hseDateByEquip[k] = d;
      }
      if (mounted) setState(() {});
    } catch (_) {
      // si la table n’existe pas encore → pas de date
    }
  }

  Future<void> _ensureEquipCache(Set<String> ids) async {
    final missing = ids.where((id) => !_equipCache.containsKey(id)).toSet();
    if (missing.isEmpty) return;
    try {
      final list = List<Map<String, dynamic>>.from(
        await _sb.from('equipements')
            .select('id, numero_serie, modele, marque, type, host_name, salle_id')
            .filter('id', 'in', _inCsv(missing)) as List
      );
      for (final m in list) {
        _equipCache[m['id'] as String] = m;
      }
      _ensureSallePaths(list.map((e) => e['salle_id'] as String?).whereType<String>().toSet());
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _ensureSallePaths(Set<String> ids) async {
    final missing = ids.where((id) => !_sallePath.containsKey(id)).toSet();
    if (missing.isEmpty) return;

    try {
      final salles = List<Map<String, dynamic>>.from(
        await _sb.from('salles').select('id, nom, batiment_id').filter('id','in', _inCsv(missing)) as List
      );
      for (final s in salles) _salleName[s['id'] as String] = (s['nom'] as String?) ?? '—';

      final batIds = salles.map((s) => s['batiment_id'] as String?).whereType<String>().toSet();
      if (batIds.isEmpty) return;

      final bats = List<Map<String, dynamic>>.from(
        await _sb.from('batiments').select('id, nom, site_id').filter('id','in', _inCsv(batIds)) as List
      );

      final siteIds = bats.map((b) => b['site_id'] as String?).whereType<String>().toSet();
      final sites = siteIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await _sb.from('sites').select('id, nom').filter('id','in', _inCsv(siteIds)) as List
            );

      final batById  = { for (final b in bats)  b['id'] as String : b };
      final siteById = { for (final s in sites) s['id'] as String : s };

      for (final s in salles) {
        final b = batById[s['batiment_id']];
        final siteName = (b != null && siteById[b['site_id']] != null)
            ? (siteById[b['site_id']]?['nom'] as String? ?? '—')
            : '—';
        final batName  = b != null ? (b['nom'] as String? ?? '—') : '—';
        final salName  = (s['nom'] as String?) ?? '—';
        _sallePath[s['id'] as String] = '$siteName / $batName / $salName';
      }

      if (mounted) setState(() {});
    } catch (_) {}
  }

  // ==================== UI dialogs ====================

  void _showEquipDetails(Map<String, dynamic> e, String sallePath) {
    showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: const Text('Détails équipement'),
        content: SizedBox(
          width: 460,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            _kv('N° série', e['numero_serie']),
            _kv('Modèle', e['modele']),
            _kv('Marque', e['marque']),
            _kv('Type', e['type']),
            _kv('Emplacement', sallePath),
            _kv('Attribué à', e['attribue_a']),
            _kv('État', _etatLabelFor(e['etat_id'])),
            _kv('Date achat', _fmtDateOnly(e['date_achat'])),
          ]),
        ),
        actions: [TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Fermer'))],
      );
    });
  }

  void _showHistDetails(Map<String, dynamic> r, Map<String, dynamic>? e) {
    final equipLabel = (e == null)
        ? '—'
        : '${e['numero_serie'] ?? ''} • ${e['host_name'] ?? ''} • ${e['marque'] ?? ''}'.trim();
    showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: const Text('Détails HSE'),
        content: SizedBox(
          width: 480,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            _kv('Équipement', equipLabel),
            _kv('Date', _fmtTs(r['created_at'])),
            _kv('Ancien état', _etatLabelFor(r['old_etat_id'])),
            _kv('Nouveau état', _etatLabelFor(r['new_etat_id'])),
            _kv('Technicien', r['created_by_email']),
          ]),
        ),
        actions: [TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Fermer'))],
      );
    });
  }

  // ==================== Helpers divers ====================

  String _etatLabelFor(dynamic etatId) {
    final id = etatId?.toString();
    if (id == null) return '—';
    final fromCache = _etatNameById[id];
    if (fromCache != null && fromCache.trim().isNotEmpty) return fromCache;
    if (_etatDonneId != null && id == _etatDonneId) return 'donné';
    if (_etatRebutId != null && id == _etatRebutId) return 'mis au rebut';
    return '—';
  }

  // Normalisation simple: minuscule + accents retirés + sans ponctuation/espaces
  String _normalize(String s) {
    String x = s.toLowerCase();
    const repl = {
      'à':'a','á':'a','â':'a','ä':'a',
      'ç':'c',
      'é':'e','è':'e','ê':'e','ë':'e',
      'î':'i','ï':'i',
      'ô':'o','ö':'o',
      'ù':'u','ú':'u','û':'u','ü':'u',
      'ÿ':'y',
      'œ':'oe','æ':'ae',
      'ß':'ss',
      '’':"'", // apostrophes courbes -> simples
    };
    repl.forEach((k,v) { x = x.replaceAll(k, v); });
    x = x.replaceAll(RegExp(r'[^a-z0-9]'), ''); // retire ponctuation/espaces
    return x;
  }

  static BoxDecoration _tableBox() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0,3))],
  );

  static Widget _kv(String k, dynamic v) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      SizedBox(width: 160, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
      Expanded(child: Text(v?.toString() ?? '—')),
    ]),
  );

  static String _inCsv(Iterable<String> ids) => '(${ids.map((e) => '"$e"').join(',')})';

  static DateTime? _tryParseUserDate(String q) {
    String s = q.trim();
    final re = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$'); // dd/mm/yyyy
    final m = re.firstMatch(s);
    if (m != null) {
      s = '${m.group(3)}-${m.group(2)!.padLeft(2, '0')}-${m.group(1)!.padLeft(2, '0')}';
    }
    try {
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
        return DateTime.parse('$s 00:00:00');
      }
    } catch (_) {}
    return null;
  }

  static bool _sameDay(DateTime? a, DateTime b) {
    if (a == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String _fmtDateOnly(dynamic ts) {
    final d = _parseTs(ts); if (d == null) return '—';
    return '${d.year}-${_2(d.month)}-${_2(d.day)}';
  }

  static String _fmtTs(dynamic ts) {
    final d = _parseTs(ts); if (d == null) return '—';
    return '${d.year}-${_2(d.month)}-${_2(d.day)} ${_2(d.hour)}:${_2(d.minute)}';
  }

  static DateTime? _parseTs(dynamic ts) {
    if (ts == null) return null;
    try { return DateTime.parse(ts.toString()).toLocal(); } catch (_) { return null; }
  }

  static String _2(int x) => x.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: TabBar(tabs: [Tab(text: 'Actuels'), Tab(text: 'Historique')]),
          ),
          Expanded(
            child: TabBarView(children: [
              _HseActuelsHost(),
              _HseHistoriqueHost(),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Petits hôtes pour forcer la reconstruction des onglets avec le State parent.
class _HseActuelsHost extends StatelessWidget {
  const _HseActuelsHost();
  @override
  Widget build(BuildContext context) {
    return (context.findAncestorStateOfType<_HsePageState>()!)._buildActuelsTab();
    }
}

class _HseHistoriqueHost extends StatelessWidget {
  const _HseHistoriqueHost();
  @override
  Widget build(BuildContext context) {
    return (context.findAncestorStateOfType<_HsePageState>()!)._buildHistoriqueTab();
  }
}
