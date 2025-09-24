/*/*import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/supabase_client.dart';

class MaintenancePage extends StatefulWidget {
  const MaintenancePage({super.key});
  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> {
  final _sb = SB.client;

  // ------- rôle / droits -------
  String? _role;
  bool _loadingRole = true;
  bool get _canWrite => _role == 'technicien' || _role == 'super-admin';

  // ------- référentiels -------
  String? _etatMaintenanceId; // id de l'état "en maintenance"
  final Map<String, String> _etatNames = {}; // id -> nom (si vous en avez besoin ensuite)

  // Emplacements: caches "Site / Bâtiment / Salle"
  final Map<String, String> _salleName = {}; // salleId -> 'Salle'
  final Map<String, String> _sallePath = {}; // salleId -> 'Site / Bâtiment / Salle'

  // ------- filtres / recherches -------
  final _histSearchCtrl = TextEditingController();

  // Interventions: cache des équipements (pour afficher série, modèle, marque)
  final Map<String, Map<String, dynamic>> _equipCache = {};

  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadEtatMaintenanceId();
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

  Future<void> _loadEtatMaintenanceId() async {
    try {
      final r = await _sb.from('etats').select('id, nom').ilike('nom', 'en maintenance').maybeSingle();
      if (r != null) {
        setState(() {
          _etatMaintenanceId = r['id'] as String?;
          if (r['id'] != null && r['nom'] != null) {
            _etatNames[r['id'] as String] = (r['nom'] as String);
          }
        });
      }
    } catch (_) {
      // silencieux: l’onglet liste affichera un hint si cet état n’existe pas
    }
  }

  // ==================== Onglet LISTE ====================

  Widget _buildListTab() {
    if (_etatMaintenanceId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            "L’état « en maintenance » n’a pas été trouvé.\n"
            "Créez-le dans la table 'etats' pour afficher la liste des équipements en maintenance.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ),
      );
    }

    final stream = _sb
        .from('equipements')
        .stream(primaryKey: ['id'])
        .eq('etat_id', _etatMaintenanceId as Object)
        .order('updated_at', ascending: false);

    return Column(
      children: [
        if (_loadingRole)
          const LinearProgressIndicator(minHeight: 2)
        else if (!_canWrite)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            color: Colors.amber.withOpacity(0.15),
            child: const Text("Lecture seule (visiteur). L’édition est réservée aux techniciens et super-admins."),
          ),

        // Barre d'actions
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: _canWrite ? () => _showAddInterventionDialog() : null,
                icon: const Icon(Icons.add),
                label: const Text('Nouvelle intervention'),
              ),
            ],
          ),
        ),

        // Tableau des équipements en maintenance
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: stream,
            builder: (_, snap) {
              if (snap.hasError) return Center(child: Text('Erreur: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final rows = snap.data!;
              if (rows.isEmpty) return const Center(child: Text('Aucun équipement en maintenance.'));

              // Prépare les chemins d’emplacement
              _ensureSallePaths(rows.map((e) => e['salle_id'] as String?).whereType<String>().toSet());

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))],
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text(' ')), // info
                      DataColumn(label: Text('N° série')),
                      DataColumn(label: Text('Modèle')),
                      DataColumn(label: Text('Marque')),
                      DataColumn(label: Text('Emplacement')),
                      DataColumn(label: Text('Attribué à')),
                      DataColumn(label: Text('Dernière modif')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: rows.map((e) {
                      final sallePath = (e['salle_id'] != null)
                          ? (_sallePath[e['salle_id']] ?? _salleName[e['salle_id']] ?? '—')
                          : '—';
                      return DataRow(cells: [
                        DataCell(IconButton(
                          icon: const Icon(Icons.info_outline),
                          tooltip: 'Détails',
                          onPressed: () => _showEquipDetails(e),
                        )),
                        DataCell(Text(e['numero_serie'] ?? '—')),
                        DataCell(Text(e['modele'] ?? '—')),
                        DataCell(Text(e['marque'] ?? '—')),
                        DataCell(Text(sallePath)),
                        DataCell(Text(e['attribue_a'] ?? '—')),
                        DataCell(Text(_fmtTs(e['updated_at']))),
                        DataCell(
                          Wrap(
                            spacing: 6,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.add_task_outlined),
                                tooltip: 'Ajouter une intervention',
                                onPressed: _canWrite ? () => _showAddInterventionDialog(forEquip: e) : null,
                              ),
                              IconButton(
                                icon: const Icon(Icons.history),
                                tooltip: 'Voir historique (filtré)',
                                onPressed: () => _openHistoryForEquip(e['id'] as String?),
                              ),
                            ],
                          ),
                        ),
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

  Widget _buildHistoryTab() {
    final stream = _sb
        .from('interventions') // ⚠️ nécessite la table 'public.interventions'
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    return Column(
      children: [
        // barre de recherche
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _histSearchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Rechercher (date 2025-09-11 ou 11/09/2025, série, modèle, marque, site/salle, technicien...)',
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
                    ? "Historique indisponible. Créez la table 'public.interventions' (et policies) puis exécutez : NOTIFY pgrst, 'reload schema';"
                    : msg;
                return Center(child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text('Erreur: $friendly'),
                ));
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());

              final rows = snap.data!;
              if (rows.isEmpty) return const Center(child: Text('Aucune intervention.'));

              // précharge les équipements référencés
              _ensureEquipCache(rows.map((r) => r['equipement_id'] as String?).whereType<String>().toSet());

              // filtre intelligent côté client
              final q = _histSearchCtrl.text.trim();
              final filtered = rows.where((r) => _histRowMatches(r, q)).toList();

              if (filtered.isEmpty) return const Center(child: Text('Aucun résultat.'));

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0,3))],
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text(' ')), // info
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Équipement')),
                      DataColumn(label: Text('Titre')),
                      DataColumn(label: Text('Statut')),
                      DataColumn(label: Text('Technicien')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: filtered.map((r) {
                      final e = _equipCache[r['equipement_id']];
                      final equipLabel = (e == null)
                          ? '—'
                          : '${e['numero_serie'] ?? ''} • ${e['modele'] ?? ''} • ${e['marque'] ?? ''}'.trim();
                      return DataRow(cells: [
                        DataCell(IconButton(
                          icon: const Icon(Icons.info_outline),
                          tooltip: 'Détails intervention',
                          onPressed: () => _showInterventionDetails(r),
                        )),
                        DataCell(Text(_fmtTs(r['created_at']))),
                        DataCell(Text(equipLabel.isEmpty ? '—' : equipLabel)),
                        DataCell(Text(r['titre'] ?? r['resume'] ?? '—')),
                        DataCell(Text(r['statut'] ?? '—')),
                        DataCell(Text(r['created_by_email'] ?? r['technicien_email'] ?? '—')),
                        DataCell(
                          Wrap(
                            spacing: 6,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.visibility),
                                tooltip: 'Voir',
                                onPressed: () => _showInterventionDetails(r),
                              ),
                              // placer ici des actions (clôturer, etc.) quand le back sera prêt
                            ],
                          ),
                        ),
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

  // ==================== Actions UI ====================

  void _showEquipDetails(Map<String, dynamic> e) {
    final sallePath = (e['salle_id'] != null)
        ? (_sallePath[e['salle_id']] ?? _salleName[e['salle_id']] ?? '—')
        : '—';
    showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: const Text('Détails équipement'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _kv('N° série', e['numero_serie']),
            _kv('Modèle', e['modele']),
            _kv('Marque', e['marque']),
            _kv('Type', e['type']),
            _kv('Emplacement', sallePath),
            _kv('Attribué à', e['attribue_a']),
            _kv('Date achat', _fmtDateOnly(e['date_achat'])),
            _kv('Date assignation', _fmtDateOnly(e['date_assignation'])),
            const Divider(),
            _kv('Dernière modif', _fmtTs(e['updated_at'])),
          ]),
        ),
        actions: [TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Fermer'))],
      );
    });
  }

  void _showInterventionDetails(Map<String, dynamic> r) {
    final e = _equipCache[r['equipement_id']];
    final equipLabel = (e == null)
        ? '—'
        : '${e['numero_serie'] ?? ''} • ${e['modele'] ?? ''} • ${e['marque'] ?? ''}'.trim();
    showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: const Text('Détails intervention'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _kv('Équipement', equipLabel),
            _kv('Titre', r['titre'] ?? r['resume']),
            _kv('Statut', r['statut']),
            _kv('Technicien', r['created_by_email'] ?? r['technicien_email']),
            _kv('Créée le', _fmtTs(r['created_at'])),
            _kv('Début', _fmtTs(r['date_debut'])),
            _kv('Fin', _fmtTs(r['date_fin'])),
            const SizedBox(height: 8),
            Text(r['description'] ?? '—'),
          ]),
        ),
        actions: [TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Fermer'))],
      );
    });
  }

  void _showAddInterventionDialog({Map<String, dynamic>? forEquip}) {
    // TODO: implémenter le vrai formulaire plus tard
    final serie = forEquip?['numero_serie'] ?? '—';
    final modele = forEquip?['modele'] ?? '—';
    showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: const Text('Nouvelle intervention'),
        content: Text(
          forEquip == null
              ? "Formulaire à implémenter.\n\nIci vous ouvrirez une intervention libre."
              : "Formulaire à implémenter.\n\nPréremplir avec:\n• Équipement: $serie • $modele",
        ),
        actions: [TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Fermer'))],
      );
    });
  }

  void _openHistoryForEquip(String? equipId) {
    if (equipId == null) return;
    // place un filtre simple dans la barre de recherche (n° de série si connu)
    final e = _equipCache[equipId];
    if (e != null && (e['numero_serie'] as String?)?.isNotEmpty == true) {
      _histSearchCtrl.text = e['numero_serie'] as String;
    } else {
      _histSearchCtrl.text = equipId;
    }
    setState(() {}); // l’onglet restera le même; laissez l’utilisateur cliquer sur "Historique"
  }

  // ==================== Helpers métiers ====================

  bool _histRowMatches(Map<String, dynamic> r, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;

    // date
    final qDate = _tryParseUserDate(q);
    if (qDate != null) {
      if (_sameDay(_parseTs(r['date_debut']), qDate) ||
          _sameDay(_parseTs(r['date_fin']), qDate) ||
          _sameDay(_parseTs(r['created_at']), qDate)) {
        return true;
      }
    }

    // textes intervention
    final strings = <String>[
      r['titre']?.toString() ?? '',
      r['resume']?.toString() ?? '',
      r['description']?.toString() ?? '',
      r['statut']?.toString() ?? '',
      r['created_by_email']?.toString() ?? r['technicien_email']?.toString() ?? '',
    ].map((s) => s.toLowerCase()).toList();

    // infos équipement liées
    final e = _equipCache[r['equipement_id']];
    if (e != null) {
      strings.addAll([
        e['numero_serie']?.toString() ?? '',
        e['modele']?.toString() ?? '',
        e['marque']?.toString() ?? '',
        e['type']?.toString() ?? '',
      ].map((s) => s.toLowerCase()));
      strings.add(_sallePath[e['salle_id']]?.toLowerCase() ?? _salleName[e['salle_id']]?.toLowerCase() ?? '');
    }

    return strings.any((s) => s.contains(q));
  }

  Future<void> _ensureEquipCache(Set<String> ids) async {
    final missing = ids.where((id) => !_equipCache.containsKey(id)).toSet();
    if (missing.isEmpty) return;
    final idsCsv = _inCsv(missing);
    try {
      final list = List<Map<String, dynamic>>.from(
        await _sb.from('equipements').select('id, numero_serie, modele, marque, type, salle_id').filter('id','in', idsCsv) as List
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
      final sallesCsv = _inCsv(missing);
      final salles = List<Map<String, dynamic>>.from(
        await _sb.from('salles').select('id, nom, batiment_id').filter('id','in', sallesCsv) as List
      );
      for (final s in salles) {
        _salleName[s['id'] as String] = (s['nom'] as String?) ?? '—';
      }

      final batIds = salles.map((s) => s['batiment_id'] as String?).whereType<String>().toSet();
      if (batIds.isEmpty) return;

      final batsCsv = _inCsv(batIds);
      final bats = List<Map<String, dynamic>>.from(
        await _sb.from('batiments').select('id, nom, site_id').filter('id','in', batsCsv) as List
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

  // ==================== Helpers UI / formats ====================

  static Widget _kv(String k, dynamic v) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      SizedBox(width: 150, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
      Expanded(child: Text(v?.toString() ?? '—')),
    ]),
  );

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

  static String _inCsv(Iterable<String> ids) =>
      '(${ids.map((e) => '"$e"').join(',')})';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: TabBar(tabs: [Tab(text: 'Liste'), Tab(text: 'Historique')]),
          ),
          Expanded(
            child: TabBarView(children: [
              _buildListTab(),
              _buildHistoryTab(),
            ]),
          ),
        ],
      ),
    );
  }
}*/
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/supabase_client.dart';

class MaintenancePage extends StatefulWidget {
  const MaintenancePage({super.key});
  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> {
  final _sb = SB.client;

  // ------- rôle / droits -------
  String? _role;
  bool _loadingRole = true;
  bool get _canWrite => _role == 'technicien' || _role == 'super-admin';

  // ------- référentiels -------
  String? _etatMaintenanceId; // id de l'état "en maintenance"
  final Map<String, String> _etatNames = {}; // id -> nom

  // Emplacements: caches "Site / Bâtiment / Salle"
  final Map<String, String> _salleName = {}; // salleId -> 'Salle'
  final Map<String, String> _sallePath = {}; // salleId -> 'Site / Bâtiment / Salle'

  // ------- filtres / recherches -------
  final _histSearchCtrl = TextEditingController();

  // Interventions: cache des équipements (pour afficher série, modèle, marque)
  final Map<String, Map<String, dynamic>> _equipCache = {};

  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadEtatMaintenanceId();
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

  /// Sélectionne plusieurs lignes avec col = id pour chacun des ids (fallback sans `in`).
  Future<List<Map<String, dynamic>>> _selectManyByIds(
    String table,
    String col,
    Iterable<String> ids, {
    String cols = '*',
  }) async {
    final out = <Map<String, dynamic>>[];
    for (final id in ids.where((e) => e.trim().isNotEmpty)) {
      try {
        final res = await SB.client.from(table).select(cols).eq(col, id);
        out.addAll(List<Map<String, dynamic>>.from(res as List));
      } catch (_) {}
    }
    return out;
  }

  Future<void> _loadEtatMaintenanceId() async {
    try {
      final r = await _sb
          .from('etats')
          .select('id, nom')
          .ilike('nom', 'en maintenance')
          .maybeSingle();
      if (r != null) {
        setState(() {
          _etatMaintenanceId = r['id'] as String?;
          if (r['id'] != null && r['nom'] != null) {
            _etatNames[r['id'] as String] = (r['nom'] as String);
          }
        });
      }
    } catch (_) {}
  }

  // ==================== Onglet LISTE ====================

  Widget _buildListTab() {
    if (_etatMaintenanceId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            "Le statut « en maintenance » n’a pas été trouvé.\n"
            "Créez-le dans la table 'statuts' pour afficher la liste des équipements en maintenance.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ),
      );
    }

    final stream = _sb
        .from('equipements')
        .stream(primaryKey: ['id'])
        .eq('etat_id', _etatMaintenanceId as Object)
        .order('updated_at', ascending: false);

    return Column(
      children: [
        if (_loadingRole)
          const LinearProgressIndicator(minHeight: 2)
        else if (!_canWrite)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            color: Colors.amber.withOpacity(0.15),
            child: const Text(
              "Lecture seule (visiteur)"
            ),
          ),

        // Barre d'actions
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: !_canWrite ? null : () async {
                  final equip = await _pickEquipForIntervention(context);
                  if (equip != null) _openNewInterventionDialogForEquip(equip);
                },
                icon: const Icon(Icons.add),
                label: const Text('Nouvelle intervention'),
              ),
            ],
          ),
        ),

        // Tableau des équipements en maintenance
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: stream,
            builder: (_, snap) {
              if (snap.hasError) return Center(child: Text('Erreur: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final rows = snap.data!;
              if (rows.isEmpty) return const Center(child: Text('Aucun équipement en maintenance.'));

              // Prépare les chemins d’emplacement
              _ensureSallePaths(rows.map((e) => e['salle_id'] as String?).whereType<String>().toSet());

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))],
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text(' ')), // info
                      DataColumn(label: Text('N° série')),
                      DataColumn(label: Text('Modèle')),
                      DataColumn(label: Text('Marque')),
                      DataColumn(label: Text('Emplacement')),
                      DataColumn(label: Text('Attribué à')),
                      DataColumn(label: Text('Dernière modif')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: rows.map((e) {
                      final sallePath = (e['salle_id'] != null)
                          ? (_sallePath[e['salle_id']] ?? _salleName[e['salle_id']] ?? '—')
                          : '—';
                      return DataRow(cells: [
                        DataCell(IconButton(
                          icon: const Icon(Icons.info_outline),
                          tooltip: 'Détails',
                          onPressed: () => _showEquipDetails(e),
                        )),
                        DataCell(Text(e['numero_serie'] ?? '—')),
                        DataCell(Text(e['modele'] ?? '—')),
                        DataCell(Text(e['marque'] ?? '—')),
                        DataCell(Text(sallePath)),
                        DataCell(Text(e['attribue_a'] ?? '—')),
                        DataCell(Text(_fmtTs(e['updated_at']))),
                        DataCell(
                          Wrap(
                            spacing: 6,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.add_task_outlined),
                                tooltip: 'Ajouter une intervention',
                                onPressed: !_canWrite ? null : () => _openNewInterventionDialogForEquip(e),
                              ),
                              IconButton(
                                icon: const Icon(Icons.history),
                                tooltip: 'Interventions de cet équipement',
                                onPressed: () => _openInterventionsSheetForEquip(e),
                              ),
                            ],
                          ),
                        ),
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

  // ==================== Onglet HISTORIQUE (global) ====================

  Widget _buildHistoryTab() {
    final stream = _sb
        .from('interventions')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    return Column(
      children: [
        // barre de recherche
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _histSearchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Rechercher ',
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
                    ? "Historique indisponible. Vérifie la table 'public.interventions' et ses policies, puis NOTIFY pgrst, 'reload schema';"
                    : msg;
                return Center(child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text('Erreur: $friendly'),
                ));
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());

              final rows = snap.data!;
              if (rows.isEmpty) return const Center(child: Text('Aucune intervention.'));

              // précharge les équipements référencés
              _ensureEquipCache(rows.map((r) => r['equipement_id'] as String?).whereType<String>().toSet());

              // filtre intelligent côté client
              final q = _histSearchCtrl.text.trim();
              final filtered = rows.where((r) => _histRowMatches(r, q)).toList();

              if (filtered.isEmpty) return const Center(child: Text('Aucun résultat.'));

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0,3))],
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text(' ')), // info
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Équipement')),
                      DataColumn(label: Text('Statut')),
                      DataColumn(label: Text('Pièces rempla.')),
                      DataColumn(label: Text('Technicien')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: filtered.map((r) {
                      final e = _equipCache[r['equipement_id']];
                      final equipLabel = (e == null)
                          ? '—'
                          : '${e['numero_serie'] ?? ''} • ${e['hostname'] ?? ''} • ${e['marque'] ?? ''}'.trim();
                      return DataRow(cells: [
                        DataCell(IconButton(
                          icon: const Icon(Icons.info_outline),
                          tooltip: 'Détails intervention',
                          onPressed: () => _showInterventionDetails(r),
                        )),
                        DataCell(Text(_fmtTs(r['date_creation']))),
                        DataCell(Text(equipLabel.isEmpty ? '—' : equipLabel)),
                        DataCell(Text(r['statut'] ?? '—')),
                        DataCell(Text((r['nbre_piece_remplacee'] ?? 0).toString())),
                        DataCell(Text(r['created_by_email'] ?? '—')),
                        DataCell(
                          IconButton(
                            icon: const Icon(Icons.edit),
                            tooltip: _canWrite ? 'Modifier' : 'Lecture seule',
                            onPressed: !_canWrite ? null : () => _editInterventionDialog(r),
                          ),
                        ),
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

  // ==================== Actions UI ====================

  void _showEquipDetails(Map<String, dynamic> e) {
    final sallePath = (e['salle_id'] != null)
        ? (_sallePath[e['salle_id']] ?? _salleName[e['salle_id']] ?? '—')
        : '—';
    showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: const Text('Détails équipement'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _kv('N° série', e['numero_serie']),
            _kv('Modèle', e['modele']),
            _kv('Marque', e['marque']),
            _kv('Type', e['type']),
            _kv('Emplacement', sallePath),
            _kv('Attribué à', e['attribue_a']),
            _kv('Date achat', _fmtDateOnly(e['date_achat'])),
            _kv('Date assignation', _fmtDateOnly(e['date_assignation'])),
            const Divider(),
            _kv('Dernière modif', _fmtTs(e['updated_at'])),
          ]),
        ),
        actions: [TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Fermer'))],
      );
    });
  }

  void _showInterventionDetails(Map<String, dynamic> r) {
    final e = _equipCache[r['equipement_id']];
    final equipLabel = (e == null)
        ? '—'
        : '${e['numero_serie'] ?? ''} • ${e['modele'] ?? ''} • ${e['marque'] ?? ''}'.trim();
    showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: const Text('Détails intervention'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _kv('Équipement', equipLabel),
            _kv('Date création', _fmtTs(r['date_creation'])),
            _kv('Statut', r['statut']),
            _kv('Pièces remplacées', r['nbre_piece_remplacee']),
            _kv('Technicien', r['created_by_email']),
            _kv('Date fin', _fmtTs(r['date_fin'])),
            const SizedBox(height: 8),
            Text(r['description'] ?? '—'),
          ]),
        ),
        actions: [TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Fermer'))],
      );
    });
  }

  // ==================== Interventions (ajout / listing / édition) ====================

  // Choisir rapidement un équipement (pour le bouton de la barre)
  Future<Map<String, dynamic>?> _pickEquipForIntervention(BuildContext ctx) async {
    final res = await _sb
        .from('equipements')
        .select('id, numero_serie, modele, marque, host_name, etat_id')
        .order('updated_at', ascending: false);
    final list = List<Map<String, dynamic>>.from(res as List);

    // Par défaut on filtre ceux "en maintenance"
    final maintOnly = list.where((e) => e['etat_id'] == _etatMaintenanceId).toList();

    return showDialog<Map<String, dynamic>>(
      context: ctx,
      builder: (_) {
        String q = '';
        List<Map<String, dynamic>> filtered = maintOnly;
        void doFilter(String s) {
          q = s.trim().toLowerCase();
          filtered = maintOnly.where((e) {
            final t = [
              e['numero_serie'], e['modele'], e['marque'], e['host_name']
            ].whereType<String>().map((s) => s.toLowerCase());
            return t.any((x) => x.contains(q));
          }).toList();
          (ctx as Element).markNeedsBuild();
        }

        return AlertDialog(
          title: const Text('Choisir un équipement'),
          content: SizedBox(
            width: 520, height: 420,
            child: Column(children: [
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Rechercher',
                ),
                onChanged: doFilter,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = filtered[i];
                    return ListTile(
                      leading: const Icon(Icons.memory),
                      title: Text('${e['numero_serie'] ?? '—'} • ${e['modele'] ?? '—'}'),
                      subtitle: Text('${e['marque'] ?? '—'}  ${e['host_name'] ?? ''}'),
                      onTap: () => Navigator.pop(ctx, e),
                    );
                  },
                ),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler'))],
        );
      },
    );
  }

  // 1) Nouvelle intervention pour un équipement donné
  Future<void> _openNewInterventionDialogForEquip(Map<String, dynamic> equip) async {
    final formKey  = GlobalKey<FormState>();
    final descCtrl = TextEditingController();
    final piecesCtrl = TextEditingController(text: '0');
    String statut = 'en cours';
    DateTime? dateFin;

    final email = _sb.auth.currentUser?.email ?? '';
    final intervenant = email.split('@').first; // pour affichage

    await showDialog(
      context: context,
      builder: (ctx) {
        Future<void> pickFin() async {
          final now = DateTime.now();
          final p = await showDatePicker(
            context: ctx,
            firstDate: DateTime(now.year - 1),
            lastDate:  DateTime(now.year + 1),
            initialDate: dateFin ?? now,
          );
          if (p != null && mounted) setState(() => dateFin = p);
        }

        return AlertDialog(
          title: const Text('Nouvelle intervention'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Équipement : ${equip['numero_serie'] ?? '—'} • ${equip['host_name'] ?? '—'} • ${equip['marque'] ?? '—'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text('Intervenant : $intervenant', style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: statut,
                    decoration: const InputDecoration(labelText: 'Statut', border: OutlineInputBorder()),
                    items: const ['en cours','terminée','en attente pièces','annulée']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (v) => statut = v ?? 'en cours',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: piecesCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de pièces remplacées',
                      prefixIcon: Icon(Icons.swap_horiz),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || int.tryParse(v) == null) ? 'Entier requis' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description ',
                      prefixIcon: Icon(Icons.description),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: pickFin,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Date fin ',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.event),
                      ),
                      child: Text(dateFin == null ? '—' : _fmtDateOnly(dateFin!.toIso8601String())),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              child: const Text('Enregistrer'),
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final payload = {
                  'equipement_id': equip['id'],
                  'statut': statut,
                  'nbre_piece_remplacee': int.parse(piecesCtrl.text.trim()),
                  'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                  'date_fin': dateFin?.toIso8601String(),
                  // created_by / created_by_email / utilisateur_id via triggers
                };
                try {
                  await _sb.from('interventions').insert(payload);
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Intervention ajoutée')),
                    );
                  }
                } on PostgrestException catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.message), backgroundColor: Colors.red),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  // 2) Feuille/listing des interventions d’un équipement (avec édition)
  void _openInterventionsSheetForEquip(Map<String, dynamic> equip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        final stream = _sb
            .from('interventions')
            .stream(primaryKey: ['id'])
            .eq('equipement_id', equip['id'])
            .order('created_at', ascending: false);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.handyman, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          /* */
                          'Interventions • ${equip['numero_serie'] ?? '—'} • ${equip['host_name'] ?? '—'} • ${equip['marque'] ?? '—'}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Nouvelle intervention',
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: !_canWrite ? null : () => _openNewInterventionDialogForEquip(equip),
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: stream,
                      builder: (_, snap) {
                        if (snap.hasError) {
                          return Center(child: Text('Erreur: ${snap.error}'));
                        }
                        if (!snap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final rows = snap.data!;
                        if (rows.isEmpty) {
                          return const Center(child: Text('Aucune intervention pour cet équipement.'));
                        }
                        return ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final r = rows[i];
                            return ListTile(
                              leading: const Icon(Icons.build),
                              title: Text('${r['statut'] ?? '—'} • ${_fmtTs(r['date_creation'])}'),
                              subtitle: Text(
                                'Pièces: ${r['nbre_piece_remplacee'] ?? 0}  •  ${r['description'] ?? '—'}\n'
                                'par ${r['created_by_email'] ?? '—'}',
                              ),
                              isThreeLine: true,
                              trailing: IconButton(
                                tooltip: 'Modifier',
                                icon: const Icon(Icons.edit),
                                onPressed: !_canWrite ? null : () => _editInterventionDialog(r),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 3) Édition d’une intervention (dialog réutilisable)
  Future<void> _editInterventionDialog(Map<String, dynamic> r) async {
    final formKey = GlobalKey<FormState>();
    final descCtrl = TextEditingController(text: r['description'] ?? '');
    final piecesCtrl =
        TextEditingController(text: (r['nbre_piece_remplacee'] ?? 0).toString());
    String statut = (r['statut'] ?? 'en cours').toString();
    DateTime? dateFin = _parseTs(r['date_fin']);

    await showDialog(
      context: context,
      builder: (ctx) {
        Future<void> pickFin() async {
          final now = DateTime.now();
          final p = await showDatePicker(
            context: ctx,
            firstDate: DateTime(now.year - 1),
            lastDate:  DateTime(now.year + 1),
            initialDate: dateFin ?? now,
          );
          if (p != null && mounted) setState(() => dateFin = p);
        }

        return AlertDialog(
          title: const Text('Modifier l’intervention'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  value: statut,
                  decoration: const InputDecoration(labelText: 'Statut', border: OutlineInputBorder()),
                  items: const ['en cours','terminée','en attente pièces','annulée']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => statut = v ?? statut,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: piecesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de pièces remplacées',
                    prefixIcon: Icon(Icons.swap_horiz),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || int.tryParse(v) == null) ? 'Entier requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    prefixIcon: Icon(Icons.description),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: pickFin,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date fin ',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.event),
                    ),
                    child: Text(dateFin == null ? '—' : _fmtDateOnly(dateFin!.toIso8601String())),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              child: const Text('Enregistrer'),
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final payload = {
                  'statut': statut,
                  'nbre_piece_remplacee': int.parse(piecesCtrl.text.trim()),
                  'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                  'date_fin': dateFin?.toIso8601String(),
                };
                try {
                  await _sb.from('interventions').update(payload).eq('id', r['id']);
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Intervention modifiée')),
                    );
                  }
                } on PostgrestException catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.message), backgroundColor: Colors.red),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  // ==================== Helpers métiers ====================

  bool _histRowMatches(Map<String, dynamic> r, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;

    // date
    final qDate = _tryParseUserDate(q);
    if (qDate != null) {
      if (_sameDay(_parseTs(r['date_creation']), qDate) ||
          _sameDay(_parseTs(r['date_fin']), qDate) ||
          _sameDay(_parseTs(r['created_at']), qDate)) {
        return true;
      }
    }

    // textes intervention
    final strings = <String>[
      r['description']?.toString() ?? '',
      r['statut']?.toString() ?? '',
      r['created_by_email']?.toString() ?? '',
      r['updated_by_email']?.toString() ?? '',
    ].map((s) => s.toLowerCase()).toList();

    // infos équipement liées
    final e = _equipCache[r['equipement_id']];
    if (e != null) {
      strings.addAll([
        e['numero_serie']?.toString() ?? '',
        e['modele']?.toString() ?? '',
        e['marque']?.toString() ?? '',
        e['type']?.toString() ?? '',
      ].map((s) => s.toLowerCase()));
      strings.add(_sallePath[e['salle_id']]?.toLowerCase() ?? _salleName[e['salle_id']]?.toLowerCase() ?? '');
    }

    return strings.any((s) => s.contains(q));
  }

  Future<void> _ensureEquipCache(Set<String> ids) async {
    final missing = ids.where((id) => !_equipCache.containsKey(id)).toSet();
    if (missing.isEmpty) return;
    final idsCsv = _inCsv(missing);
    try {
      final list = List<Map<String, dynamic>>.from(
        await _sb.from('equipements').select('id, numero_serie, host_name, marque, type, salle_id').filter('id','in', idsCsv) as List
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
      final sallesCsv = _inCsv(missing);
      final salles = List<Map<String, dynamic>>.from(
        await _sb.from('salles').select('id, nom, batiment_id').filter('id','in', sallesCsv) as List
      );
      for (final s in salles) {
        _salleName[s['id'] as String] = (s['nom'] as String?) ?? '—';
      }

      final batIds = salles.map((s) => s['batiment_id'] as String?).whereType<String>().toSet();
      if (batIds.isEmpty) return;

      final batsCsv = _inCsv(batIds);
      final bats = List<Map<String, dynamic>>.from(
        await _sb.from('batiments').select('id, nom, site_id').filter('id','in', batsCsv) as List
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

  // ==================== Helpers UI / formats ====================

  static Widget _kv(String k, dynamic v) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      SizedBox(width: 150, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
      Expanded(child: Text(v?.toString() ?? '—')),
    ]),
  );

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

  static String _inCsv(Iterable<String> ids) =>
      '(${ids.map((e) => '"$e"').join(',')})';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: TabBar(tabs: [Tab(text: 'Liste'), Tab(text: 'Historique')]),
          ),
          Expanded(
            child: TabBarView(children: [
              _buildListTab(),
              _buildHistoryTab(),
            ]),
          ),
        ],
      ),
    );
  }
}
*/
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/supabase_client.dart';
import 'package:gepi/pages/pdf_exporter.dart'; // <= export PDF

class MaintenancePage extends StatefulWidget {
  const MaintenancePage({super.key});
  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> {
  final _sb = SB.client;

  // ------- rôle / droits -------
  String? _role;
  bool _loadingRole = true;
  bool get _canWrite => _role == 'technicien' || _role == 'super-admin';

  // ------- référentiels -------
  String? _etatMaintenanceId; // id de l'état "en maintenance"
  final Map<String, String> _etatNames = {}; // id -> nom

  // Emplacements: caches "Site / Bâtiment / Salle"
  final Map<String, String> _salleName = {}; // salleId -> 'Salle'
  final Map<String, String> _sallePath = {}; // salleId -> 'Site / Bâtiment / Salle'

  // ------- filtres / recherches -------
  final _histSearchCtrl = TextEditingController();

  // Interventions: cache des équipements (pour afficher série, modèle, marque)
  final Map<String, Map<String, dynamic>> _equipCache = {};

  // (optionnel) garder la dernière liste filtrée pour AppBar export
  List<Map<String, dynamic>> _lastMaintRows = const [];
  List<Map<String, dynamic>> _lastIntervRows = const [];

  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadEtatMaintenanceId();
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

  /// Sélectionne plusieurs lignes avec col = id pour chacun des ids (fallback sans `in`).
  Future<List<Map<String, dynamic>>> _selectManyByIds(
    String table,
    String col,
    Iterable<String> ids, {
    String cols = '*',
  }) async {
    final out = <Map<String, dynamic>>[];
    for (final id in ids.where((e) => e.trim().isNotEmpty)) {
      try {
        final res = await SB.client.from(table).select(cols).eq(col, id);
        out.addAll(List<Map<String, dynamic>>.from(res as List));
      } catch (_) {}
    }
    return out;
  }

  Future<void> _loadEtatMaintenanceId() async {
    try {
      final r = await _sb
          .from('etats')
          .select('id, nom')
          .ilike('nom', 'en maintenance')
          .maybeSingle();
      if (r != null) {
        setState(() {
          _etatMaintenanceId = r['id'] as String?;
          if (r['id'] != null && r['nom'] != null) {
            _etatNames[r['id'] as String] = (r['nom'] as String);
          }
        });
      }
    } catch (_) {}
  }

  // ==================== Export PDF ====================

  Future<void> _exportMaintenance(List<Map<String, dynamic>> rows) async {
    final headers = [
      'N° série','Modèle','Marque','Emplacement','Attribué à','Dernière modif'
    ];
    final data = rows.map((e) {
      final sallePath = (e['salle_id'] != null)
          ? (_sallePath[e['salle_id']] ?? _salleName[e['salle_id']] ?? '—')
          : '—';
      return [
        (e['numero_serie'] ?? '—').toString(),
        (e['modele'] ?? '—').toString(),
        (e['marque'] ?? '—').toString(),
        sallePath,
        (e['attribue_a'] ?? '—').toString(),
        _fmtTs(e['updated_at']),
      ];
    }).toList();

    await PdfExporter.exportDataTable(
      title: 'Équipements en maintenance',
      subtitle: 'Export du tableau (filtres appliqués)',
      headers: headers,
      rows: data,
      landscape: true,
    );
  }

  Future<void> _exportInterventions(List<Map<String, dynamic>> rows) async {
    final headers = [
      'Date','Équipement','Statut','Pièces rempla.','Technicien','Description'
    ];
    final data = rows.map((r) {
      final e = _equipCache[r['equipement_id']];
      final equipLabel = (e == null)
          ? '—'
          : '${e['numero_serie'] ?? ''} • ${e['host_name'] ?? ''} • ${e['marque'] ?? ''}'.trim();
      return [
        _fmtTs(r['date_creation'] ?? r['created_at']),
        equipLabel.isEmpty ? '—' : equipLabel,
        (r['statut'] ?? '—').toString(),
        (r['nbre_piece_remplacee'] ?? 0).toString(),
        (r['created_by_email'] ?? '—').toString(),
        (r['description'] ?? '—').toString(),
      ];
    }).toList();

    await PdfExporter.exportDataTable(
      title: 'Historique des interventions',
      subtitle: 'Export du tableau (filtres appliqués)',
      headers: headers,
      rows: data,
      landscape: true,
    );
  }

  // ==================== Onglet LISTE ====================

  Widget _buildListTab() {
    if (_etatMaintenanceId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            "Le statut « en maintenance » n’a pas été trouvé.\n"
            "Créez-le dans la table 'etats' pour afficher la liste des équipements en maintenance.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ),
      );
    }

    final stream = _sb
        .from('equipements')
        .stream(primaryKey: ['id'])
        .eq('etat_id', _etatMaintenanceId as Object)
        .order('updated_at', ascending: false);

    return Column(
      children: [
        if (_loadingRole)
          const LinearProgressIndicator(minHeight: 2)
        else if (!_canWrite)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            color: Colors.amber.withOpacity(0.15),
            child: const Text("Lecture seule (visiteur)"),
          ),

        // Barre d'actions
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: !_canWrite ? null : () async {
                  final equip = await _pickEquipForIntervention(context);
                  if (equip != null) _openNewInterventionDialogForEquip(equip);
                },
                icon: const Icon(Icons.add),
                label: const Text('Nouvelle intervention'),
              ),
            ],
          ),
        ),

        // Tableau des équipements en maintenance
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: stream,
            builder: (_, snap) {
              if (snap.hasError) return Center(child: Text('Erreur: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final rows = snap.data!;
              if (rows.isEmpty) return const Center(child: Text('Aucun équipement en maintenance.'));

              // Prépare les chemins d’emplacement
              _ensureSallePaths(rows.map((e) => e['salle_id'] as String?).whereType<String>().toSet());

              // compteur + export
              _lastMaintRows = rows;

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
                            onPressed: () => _exportMaintenance(rows),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))],
                      ),
                      // ======= défilement vertical + horizontal =======
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
                              DataColumn(label: Text('Emplacement')),
                              DataColumn(label: Text('Attribué à')),
                              DataColumn(label: Text('Dernière modif')),
                              DataColumn(label: Text('Actions')),
                            ],
                            rows: rows.map((e) {
                              final sallePath = (e['salle_id'] != null)
                                  ? (_sallePath[e['salle_id']] ?? _salleName[e['salle_id']] ?? '—')
                                  : '—';
                              return DataRow(cells: [
                                DataCell(IconButton(
                                  icon: const Icon(Icons.info_outline),
                                  tooltip: 'Détails',
                                  onPressed: () => _showEquipDetails(e),
                                )),
                                DataCell(Text(e['numero_serie'] ?? '—')),
                                DataCell(Text(e['modele'] ?? '—')),
                                DataCell(Text(e['marque'] ?? '—')),
                                DataCell(Text(sallePath)),
                                DataCell(Text(e['attribue_a'] ?? '—')),
                                DataCell(Text(_fmtTs(e['updated_at']))),
                                DataCell(
                                  Wrap(
                                    spacing: 6,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.add_task_outlined),
                                        tooltip: 'Ajouter une intervention',
                                        onPressed: !_canWrite ? null : () => _openNewInterventionDialogForEquip(e),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.history),
                                        tooltip: 'Interventions de cet équipement',
                                        onPressed: () => _openInterventionsSheetForEquip(e),
                                      ),
                                    ],
                                  ),
                                ),
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

  // ==================== Onglet HISTORIQUE (global) ====================

  Widget _buildHistoryTab() {
    final stream = _sb
        .from('interventions')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    return Column(
      children: [
        // barre de recherche
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _histSearchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Rechercher ',
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
                    ? "Historique indisponible. Vérifie la table 'public.interventions' et ses policies, puis NOTIFY pgrst, 'reload schema';"
                    : msg;
                return Center(child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text('Erreur: $friendly'),
                ));
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());

              final rows = snap.data!;
              if (rows.isEmpty) return const Center(child: Text('Aucune intervention.'));

              // précharge les équipements référencés
              _ensureEquipCache(rows.map((r) => r['equipement_id'] as String?).whereType<String>().toSet());

              // filtre intelligent côté client
              final q = _histSearchCtrl.text.trim();
              final filtered = rows.where((r) => _histRowMatches(r, q)).toList();

              if (filtered.isEmpty) return const Center(child: Text('Aucun résultat.'));

              _lastIntervRows = filtered;

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
                            onPressed: () => _exportInterventions(filtered),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0,3))],
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text(' ')), // info
                              DataColumn(label: Text('Date')),
                              DataColumn(label: Text('Équipement')),
                              DataColumn(label: Text('Statut')),
                              DataColumn(label: Text('Pièces rempla.')),
                              DataColumn(label: Text('Technicien')),
                              DataColumn(label: Text('Actions')),
                            ],
                            rows: filtered.map((r) {
                              final e = _equipCache[r['equipement_id']];
                              final equipLabel = (e == null)
                                  ? '—'
                                  : '${e['numero_serie'] ?? ''} • ${e['host_name'] ?? ''} • ${e['marque'] ?? ''}'.trim();
                              return DataRow(cells: [
                                DataCell(IconButton(
                                  icon: const Icon(Icons.info_outline),
                                  tooltip: 'Détails intervention',
                                  onPressed: () => _showInterventionDetails(r),
                                )),
                                DataCell(Text(_fmtTs(r['date_creation'] ?? r['created_at']))),
                                DataCell(Text(equipLabel.isEmpty ? '—' : equipLabel)),
                                DataCell(Text(r['statut'] ?? '—')),
                                DataCell(Text((r['nbre_piece_remplacee'] ?? 0).toString())),
                                DataCell(Text(r['created_by_email'] ?? '—')),
                                DataCell(
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    tooltip: _canWrite ? 'Modifier' : 'Lecture seule',
                                    onPressed: !_canWrite ? null : () => _editInterventionDialog(r),
                                  ),
                                ),
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

  // ==================== Actions UI ====================

  void _showEquipDetails(Map<String, dynamic> e) {
    final sallePath = (e['salle_id'] != null)
        ? (_sallePath[e['salle_id']] ?? _salleName[e['salle_id']] ?? '—')
        : '—';
    showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: const Text('Détails équipement'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _kv('N° série', e['numero_serie']),
            _kv('Modèle', e['modele']),
            _kv('Marque', e['marque']),
            _kv('Type', e['type']),
            _kv('Emplacement', sallePath),
            _kv('Attribué à', e['attribue_a']),
            _kv('Date achat', _fmtDateOnly(e['date_achat'])),
            _kv('Date assignation', _fmtDateOnly(e['date_assignation'])),
            const Divider(),
            _kv('Dernière modif', _fmtTs(e['updated_at'])),
          ]),
        ),
        actions: [TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Fermer'))],
      );
    });
  }

  void _showInterventionDetails(Map<String, dynamic> r) {
    final e = _equipCache[r['equipement_id']];
    final equipLabel = (e == null)
        ? '—'
        : '${e['numero_serie'] ?? ''} • ${e['modele'] ?? ''} • ${e['marque'] ?? ''}'.trim();
    showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: const Text('Détails intervention'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _kv('Équipement', equipLabel),
            _kv('Date création', _fmtTs(r['date_creation'] ?? r['created_at'])),
            _kv('Statut', r['statut']),
            _kv('Pièces remplacées', r['nbre_piece_remplacee']),
            _kv('Technicien', r['created_by_email']),
            _kv('Date fin', _fmtTs(r['date_fin'])),
            const SizedBox(height: 8),
            Text(r['description'] ?? '—'),
          ]),
        ),
        actions: [TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Fermer'))],
      );
    });
  }

  // ==================== Interventions (ajout / listing / édition) ====================

  // Choisir rapidement un équipement (pour le bouton de la barre)
  Future<Map<String, dynamic>?> _pickEquipForIntervention(BuildContext ctx) async {
    final res = await _sb
        .from('equipements')
        .select('id, numero_serie, modele, marque, host_name, etat_id')
        .order('updated_at', ascending: false);
    final list = List<Map<String, dynamic>>.from(res as List);

    final maintOnly = list.where((e) => e['etat_id'] == _etatMaintenanceId).toList();

    return showDialog<Map<String, dynamic>>(
      context: ctx,
      builder: (_) {
        String q = '';
        List<Map<String, dynamic>> filtered = maintOnly;
        void doFilter(String s) {
          q = s.trim().toLowerCase();
          filtered = maintOnly.where((e) {
            final t = [
              e['numero_serie'], e['modele'], e['marque'], e['host_name']
            ].whereType<String>().map((s) => s.toLowerCase());
            return t.any((x) => x.contains(q));
          }).toList();
          (ctx as Element).markNeedsBuild();
        }

        return AlertDialog(
          title: const Text('Choisir un équipement'),
          content: SizedBox(
            width: 520, height: 420,
            child: Column(children: [
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Rechercher',
                ),
                onChanged: doFilter,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = filtered[i];
                    return ListTile(
                      leading: const Icon(Icons.memory),
                      title: Text('${e['numero_serie'] ?? '—'} • ${e['modele'] ?? '—'}'),
                      subtitle: Text('${e['marque'] ?? '—'}  ${e['host_name'] ?? ''}'),
                      onTap: () => Navigator.pop(ctx, e),
                    );
                  },
                ),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler'))],
        );
      },
    );
  }

  // 1) Nouvelle intervention pour un équipement donné
  Future<void> _openNewInterventionDialogForEquip(Map<String, dynamic> equip) async {
    final formKey  = GlobalKey<FormState>();
    final descCtrl = TextEditingController();
    final piecesCtrl = TextEditingController(text: '0');
    String statut = 'en cours';
    DateTime? dateFin;

    final email = _sb.auth.currentUser?.email ?? '';
    final intervenant = email.split('@').first;

    await showDialog(
      context: context,
      builder: (ctx) {
        Future<void> pickFin() async {
          final now = DateTime.now();
          final p = await showDatePicker(
            context: ctx,
            firstDate: DateTime(now.year - 1),
            lastDate:  DateTime(now.year + 1),
            initialDate: dateFin ?? now,
          );
          if (p != null && mounted) setState(() => dateFin = p);
        }

        return AlertDialog(
          title: const Text('Nouvelle intervention'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Équipement : ${equip['numero_serie'] ?? '—'} • ${equip['host_name'] ?? '—'} • ${equip['marque'] ?? '—'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text('Intervenant : $intervenant', style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: statut,
                    decoration: const InputDecoration(labelText: 'Statut', border: OutlineInputBorder()),
                    items: const ['en cours','terminée','en attente pièces','annulée']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (v) => statut = v ?? 'en cours',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: piecesCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de pièces remplacées',
                      prefixIcon: Icon(Icons.swap_horiz),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || int.tryParse(v) == null) ? 'Entier requis' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description ',
                      prefixIcon: Icon(Icons.description),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: pickFin,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Date fin ',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.event),
                      ),
                      child: Text(dateFin == null ? '—' : _fmtDateOnly(dateFin!.toIso8601String())),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              child: const Text('Enregistrer'),
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final payload = {
                  'equipement_id': equip['id'],
                  'statut': statut,
                  'nbre_piece_remplacee': int.parse(piecesCtrl.text.trim()),
                  'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                  'date_fin': dateFin?.toIso8601String(),
                };
                try {
                  await _sb.from('interventions').insert(payload);
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Intervention ajoutée')),
                    );
                  }
                } on PostgrestException catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.message), backgroundColor: Colors.red),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  // 2) Feuille/listing des interventions d’un équipement (avec édition)
  void _openInterventionsSheetForEquip(Map<String, dynamic> equip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        final stream = _sb
            .from('interventions')
            .stream(primaryKey: ['id'])
            .eq('equipement_id', equip['id'])
            .order('created_at', ascending: false);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.handyman, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Interventions • ${equip['numero_serie'] ?? '—'} • ${equip['host_name'] ?? '—'} • ${equip['marque'] ?? '—'}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Nouvelle intervention',
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: !_canWrite ? null : () => _openNewInterventionDialogForEquip(equip),
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: stream,
                      builder: (_, snap) {
                        if (snap.hasError) {
                          return Center(child: Text('Erreur: ${snap.error}'));
                        }
                        if (!snap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final rows = snap.data!;
                        if (rows.isEmpty) {
                          return const Center(child: Text('Aucune intervention pour cet équipement.'));
                        }
                        return ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final r = rows[i];
                            return ListTile(
                              leading: const Icon(Icons.build),
                              title: Text('${r['statut'] ?? '—'} • ${_fmtTs(r['date_creation'] ?? r['created_at'])}'),
                              subtitle: Text(
                                'Pièces: ${r['nbre_piece_remplacee'] ?? 0}  •  ${r['description'] ?? '—'}\n'
                                'par ${r['created_by_email'] ?? '—'}',
                              ),
                              isThreeLine: true,
                              trailing: IconButton(
                                tooltip: 'Modifier',
                                icon: const Icon(Icons.edit),
                                onPressed: !_canWrite ? null : () => _editInterventionDialog(r),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 3) Édition d’une intervention (dialog réutilisable)
  Future<void> _editInterventionDialog(Map<String, dynamic> r) async {
    final formKey = GlobalKey<FormState>();
    final descCtrl = TextEditingController(text: r['description'] ?? '');
    final piecesCtrl =
        TextEditingController(text: (r['nbre_piece_remplacee'] ?? 0).toString());
    String statut = (r['statut'] ?? 'en cours').toString();
    DateTime? dateFin = _parseTs(r['date_fin']);

    await showDialog(
      context: context,
      builder: (ctx) {
        Future<void> pickFin() async {
          final now = DateTime.now();
          final p = await showDatePicker(
            context: ctx,
            firstDate: DateTime(now.year - 1),
            lastDate:  DateTime(now.year + 1),
            initialDate: dateFin ?? now,
          );
          if (p != null && mounted) setState(() => dateFin = p);
        }

        return AlertDialog(
          title: const Text('Modifier l’intervention'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  value: statut,
                  decoration: const InputDecoration(labelText: 'Statut', border: OutlineInputBorder()),
                  items: const ['en cours','terminée','en attente pièces','annulée']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => statut = v ?? statut,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: piecesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de pièces remplacées',
                    prefixIcon: Icon(Icons.swap_horiz),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || int.tryParse(v) == null) ? 'Entier requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    prefixIcon: Icon(Icons.description),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: pickFin,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date fin ',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.event),
                    ),
                    child: Text(dateFin == null ? '—' : _fmtDateOnly(dateFin!.toIso8601String())),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              child: const Text('Enregistrer'),
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final payload = {
                  'statut': statut,
                  'nbre_piece_remplacee': int.parse(piecesCtrl.text.trim()),
                  'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                  'date_fin': dateFin?.toIso8601String(),
                };
                try {
                  await _sb.from('interventions').update(payload).eq('id', r['id']);
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Intervention modifiée')),
                    );
                  }
                } on PostgrestException catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.message), backgroundColor: Colors.red),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  // ==================== Helpers métiers ====================

  bool _histRowMatches(Map<String, dynamic> r, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;

    // date
    final qDate = _tryParseUserDate(q);
    if (qDate != null) {
      if (_sameDay(_parseTs(r['date_creation'] ?? r['created_at']), qDate) ||
          _sameDay(_parseTs(r['date_fin']), qDate) ||
          _sameDay(_parseTs(r['created_at']), qDate)) {
        return true;
      }
    }

    // textes intervention
    final strings = <String>[
      r['description']?.toString() ?? '',
      r['statut']?.toString() ?? '',
      r['created_by_email']?.toString() ?? '',
      r['updated_by_email']?.toString() ?? '',
    ].map((s) => s.toLowerCase()).toList();

    // infos équipement liées
    final e = _equipCache[r['equipement_id']];
    if (e != null) {
      strings.addAll([
        e['numero_serie']?.toString() ?? '',
        e['modele']?.toString() ?? '',
        e['marque']?.toString() ?? '',
        e['type']?.toString() ?? '',
      ].map((s) => s.toLowerCase()));
      strings.add(_sallePath[e['salle_id']]?.toLowerCase() ?? _salleName[e['salle_id']]?.toLowerCase() ?? '');
    }

    return strings.any((s) => s.contains(q));
  }

  Future<void> _ensureEquipCache(Set<String> ids) async {
    final missing = ids.where((id) => !_equipCache.containsKey(id)).toSet();
    if (missing.isEmpty) return;
    final idsCsv = _inCsv(missing);
    try {
      final list = List<Map<String, dynamic>>.from(
        await _sb.from('equipements').select('id, numero_serie, host_name, marque, type, salle_id').filter('id','in', idsCsv) as List
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
      final sallesCsv = _inCsv(missing);
      final salles = List<Map<String, dynamic>>.from(
        await _sb.from('salles').select('id, nom, batiment_id').filter('id','in', sallesCsv) as List
      );
      for (final s in salles) {
        _salleName[s['id'] as String] = (s['nom'] as String?) ?? '—';
      }

      final batIds = salles.map((s) => s['batiment_id'] as String?).whereType<String>().toSet();
      if (batIds.isEmpty) return;

      final batsCsv = _inCsv(batIds);
      final bats = List<Map<String, dynamic>>.from(
        await _sb.from('batiments').select('id, nom, site_id').filter('id','in', batsCsv) as List
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

  // ==================== Helpers UI / formats ====================

  static Widget _kv(String k, dynamic v) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      SizedBox(width: 150, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
      Expanded(child: Text(v?.toString() ?? '—')),
    ]),
  );

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

  static String _inCsv(Iterable<String> ids) =>
      '(${ids.map((e) => '"$e"').join(',')})';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: TabBar(tabs: [Tab(text: 'Liste'), Tab(text: 'Historique')]),
          ),
          Expanded(
            child: TabBarView(children: [
              _buildListTab(),
              _buildHistoryTab(),
            ]),
          ),
        ],
      ),
    );
  }
}
