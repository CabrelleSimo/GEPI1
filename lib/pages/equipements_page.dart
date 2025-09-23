/*import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/supabase_client.dart';

class EquipementsPage extends StatefulWidget {
  const EquipementsPage({super.key});
  @override
  State<EquipementsPage> createState() => _EquipementsPageState();
}

class _EquipementsPageState extends State<EquipementsPage> {
  final _sb = SB.client;

  //  rôles / droits 
  String? _role;
  bool _loadingRole = true;
  bool get _canWrite => _role == 'technicien' || _role == 'super-admin';

  // ----- filtres liste -----
  final _searchCtrl = TextEditingController();
  String? _filterType;
  String? _filterEtatId; // filtre sur le "Statut" (DB)

  // ----- référentiels -----
  List<Map<String, dynamic>> _etats = [];
  Set<String> _knownBrands = {};
  final Map<String, String> _salleName = {}; // id -> 'Salle'
  final Map<String, String> _sallePath = {}; // id -> 'Site / Bâtiment / Salle'

  // types autorisés
  static const List<String> _types = [
    'Unité centrale','Laptop','Ecran','Imprimante','Vidéo projecteur','Clavier','Souris','Station','Scanner',
  ];

  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadEtats();
    _loadBrands();
  }

  Future<void> _loadRole() async {
    setState(() => _loadingRole = true);
    try {
      final user = _sb.auth.currentUser;
      String? role = user?.userMetadata?['role'] as String?;
      if (user != null) {
        final delays = [0, 300, 800, 1500];
        for (final d in delays) {
          if (d > 0) await Future.delayed(Duration(milliseconds: d));
          try {
            final r = await _sb.from('users').select('role').eq('id', user.id).maybeSingle();
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

  Future<void> _loadEtats() async {
    try {
      final res = await _sb.from('etats').select('id, nom').order('nom');
      setState(() => _etats = List<Map<String, dynamic>>.from(res as List));
    } catch (_) {}
  }

  Future<void> _loadBrands() async {
    try {
      final res = await _sb.from('equipements').select('marque').not('marque','is',null);
      final list = List<Map<String, dynamic>>.from(res as List);
      setState(() => _knownBrands = list.map((e)=> (e['marque']??'').toString().trim()).where((s)=>s.isNotEmpty).toSet());
    } catch (_) {}
  }

  // ================= Ajout / édition =================

  Future<void> _showAddDialog() async {
    final defaults = await _computeDefaults(); // inactif + base wouri/700/704 si dispo
    await _showEditDialog(null, defaults: defaults);
  }

  static String? _emptyToNull(String? s) {
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<Map<String,String?>> _computeDefaults() async {
    String? etatId, siteId, batId, salleId;
    try {
      final e = await _sb.from('etats').select('id').eq('nom','inactif').maybeSingle();
      etatId = e?['id'] as String?;
    } catch (_) {}
    try {
      final s = await _sb.from('sites').select('id').eq('nom','base wouri').maybeSingle();
      siteId = s?['id'] as String?;
      if (siteId != null) {
        final b = await _sb.from('batiments').select('id').eq('site_id', siteId).eq('nom','700').maybeSingle();
        batId = b?['id'] as String?;
        if (batId != null) {
          final sa = await _sb.from('salles').select('id, nom').eq('batiment_id', batId).eq('nom','704').maybeSingle();
          salleId = sa?['id'] as String?;
          if (sa != null && sa['id'] != null) _salleName[sa['id'] as String] = sa['nom'] as String? ?? '—';
        }
      }
    } catch (_) {}
    return {'etatId': etatId,'siteId': siteId,'batId': batId,'salleId': salleId};
  }

  Future<void> _showEditDialog(Map<String, dynamic>? record, {Map<String,String?>? defaults}) async {
    final isEdit = record != null;

    final serieCtrl    = TextEditingController(text: record?['numero_serie'] ?? '');
    final modeleCtrl   = TextEditingController(text: record?['modele'] ?? '');
    final marqueCtrl   = TextEditingController(text: record?['marque'] ?? '');
    final hostCtrl     = TextEditingController(text: record?['host_name'] ?? '');
    final seCtrl       = TextEditingController(text: record?['systeme_exploitation'] ?? '');
    final attribueCtrl = TextEditingController(text: record?['attribue_a'] ?? '');

    DateTime? dateAchat  = _parseTs(record?['date_achat']);
    DateTime? dateAssign = _parseTs(record?['date_assignation']);

    String? type   = record?['type'];
    String? etatId = record?['etat_id'] ?? defaults?['etatId'];
    String? siteId = defaults?['siteId'];
    String? batId  = defaults?['batId'];
    String? salleId= record?['salle_id'] ?? defaults?['salleId'];

    if (isEdit && salleId != null) {
      try {
        final s = await _sb.from('salles').select('id, nom, batiment_id').eq('id', salleId).maybeSingle();
        _salleName[salleId] = s?['nom'] as String? ?? '—';
        batId  = s?['batiment_id'] as String?;
        if (batId != null) {
          final b = await _sb.from('batiments').select('id, site_id').eq('id', batId).maybeSingle();
          siteId = b?['site_id'] as String?;
        }
      } catch (_) {}
    }

    Future<List<Map<String, dynamic>>> _sites() async =>
      List<Map<String, dynamic>>.from(await _sb.from('sites').select('id, nom').order('nom') as List);
    Future<List<Map<String, dynamic>>> _bats(String sId) async =>
      List<Map<String, dynamic>>.from(await _sb.from('batiments').select('id, nom').eq('site_id', sId).order('nom') as List);
    Future<List<Map<String, dynamic>>> _salles(String bId) async =>
      List<Map<String, dynamic>>.from(await _sb.from('salles').select('id, nom').eq('batiment_id', bId).order('nom') as List);

    await showDialog(
      context: context,
      builder: (ctx) {
        final formKey = GlobalKey<FormState>();

        return StatefulBuilder(builder: (context, setState) {
          Future<void> pickDateAchat() async {
            final now = DateTime.now();
            final p = await showDatePicker(
              context: context,
              firstDate: DateTime(now.year-15),
              lastDate: DateTime(now.year+1),
              initialDate: dateAchat ?? now,
            );
            if (p != null) setState(() => dateAchat = p);
          }
          Future<void> pickDateAssign() async {
            final now = DateTime.now();
            final p = await showDatePicker(
              context: context,
              firstDate: DateTime(now.year-15),
              lastDate: DateTime(now.year+1),
              initialDate: dateAssign ?? now,
            );
            if (p != null) setState(() => dateAssign = p);
          }

          return AlertDialog(
            title: Text(isEdit ? 'Modifier l’équipement' : 'Ajouter un équipement'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _buildText(serieCtrl,  'Numéro de série *', Icons.confirmation_number, required: true),
                  const SizedBox(height: 12),
                  _buildText(modeleCtrl, 'Modèle *', Icons.devices, required: true),
                  const SizedBox(height: 12),

                  // Marque obligatoire + suggestions
                  RawAutocomplete<String>(
                    textEditingController: marqueCtrl,
                    focusNode: FocusNode(),
                    optionsBuilder: (v) {
                      final q = v.text.trim().toLowerCase();
                      if (q.isEmpty) return const Iterable<String>.empty();
                      return _knownBrands.where((b)=> b.toLowerCase().contains(q)).take(8);
                    },
                    fieldViewBuilder: (_, controller, focus, __) => TextFormField(
                      controller: controller, focusNode: focus,
                      decoration: const InputDecoration(
                        labelText: 'Marque *',
                        prefixIcon: Icon(Icons.sell),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v==null||v.trim().isEmpty) ? 'Champ requis' : null,
                    ),
                    optionsViewBuilder: (_, onSelected, opts) => Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
                          child: ListView(
                            padding: EdgeInsets.zero,
                            children: opts.map((o)=> ListTile(
                              title: Text(o),
                              onTap: ()=> onSelected(o),
                            )).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _buildDateField(label: 'Date d’achat *', value: dateAchat, onTap: pickDateAchat),

                  const Divider(height: 24),

                  DropdownButtonFormField<String?>(
                    decoration: const InputDecoration(labelText: 'Type *', border: OutlineInputBorder()),
                    value: type!=null && _types.contains(type) ? type : null,
                    items: _types.map((t)=> DropdownMenuItem<String?>(value: t, child: Text(t))).toList(),
                    onChanged: (v)=> setState(()=> type = v),
                    validator: (v)=> (v==null||v.isEmpty) ? 'Champ requis' : null,
                  ),
                  const SizedBox(height: 12),

                  // "Statut" = valeur fine en base (table etats.nom)
                  DropdownButtonFormField<String?>(
                    decoration: const InputDecoration(labelText: 'Statut', border: OutlineInputBorder()),
                    value: etatId,
                    items: _etats.map((e)=> DropdownMenuItem<String?>(
                      value: e['id'] as String,
                      child: Text(e['nom'] ?? '—'),
                    )).toList(),
                    onChanged: (v)=> setState(()=> etatId = v),
                  ),
                  const SizedBox(height: 12),

                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _sites(),
                    builder: (_, snap) {
                      final sites = snap.data ?? [];
                      return DropdownButtonFormField<String?>(
                        decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
                        value: siteId,
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('—')),
                          ...sites.map((s)=> DropdownMenuItem<String?>(
                            value: s['id'] as String,
                            child: Text(s['nom'] ?? 'Sans nom'),
                          ))
                        ],
                        onChanged: (v){ setState((){ siteId = v; batId = null; salleId = null; }); },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  if (siteId != null)
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _bats(siteId!),
                      builder: (_, snap) {
                        final bats = snap.data ?? [];
                        return DropdownButtonFormField<String?>(
                          decoration: const InputDecoration(labelText: 'Bâtiment', border: OutlineInputBorder()),
                          value: batId,
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('—')),
                            ...bats.map((b)=> DropdownMenuItem<String?>(
                              value: b['id'] as String,
                              child: Text(b['nom'] ?? 'Sans nom'),
                            ))
                          ],
                          onChanged: (v){ setState((){ batId = v; salleId = null; }); },
                        );
                      },
                    ),
                  const SizedBox(height: 12),
                  if (batId != null)
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _salles(batId!),
                      builder: (_, snap) {
                        final salles = snap.data ?? [];
                        return DropdownButtonFormField<String?>(
                          decoration: const InputDecoration(labelText: 'Salle', border: OutlineInputBorder()),
                          value: salleId,
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('—')),
                            ...salles.map((s)=> DropdownMenuItem<String?>(
                              value: s['id'] as String,
                              child: Text(s['nom'] ?? 'Sans nom'),
                            ))
                          ],
                          onChanged: (v){
                            setState(()=> salleId = v);
                            if (v!=null) {
                              final m = salles.firstWhere((x)=> x['id']==v, orElse: ()=> {});
                              if (m.isNotEmpty) _salleName[v] = (m['nom'] as String?) ?? '—';
                            }
                          },
                        );
                      },
                    ),
                  const SizedBox(height: 12),

                  _buildText(hostCtrl, 'Host name (optionnel)', Icons.computer),
                  const SizedBox(height: 12),
                  _buildText(seCtrl, 'Système d’exploitation (optionnel)', Icons.memory),
                  const SizedBox(height: 12),
                  _buildText(attribueCtrl, 'Attribué à (optionnel)', Icons.person_outline),
                  const SizedBox(height: 12),

                  _buildDateField(label: 'Date d’assignation (optionnel)', value: dateAssign, onTap: pickDateAssign),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: ()=> Navigator.pop(ctx), child: const Text('Annuler')),
              ElevatedButton(
                onPressed: !_canWrite ? null : () async {
                  if (!(formKey.currentState?.validate() ?? false)) return;
                  if (marqueCtrl.text.trim().isEmpty || dateAchat==null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Remplis les champs requis'), backgroundColor: Colors.red),
                    );
                    return;
                  }
                  final payload = {
                    'numero_serie': serieCtrl.text.trim(),
                    'modele':       modeleCtrl.text.trim(),
                    'marque':       marqueCtrl.text.trim(),
                    'type':         type,
                    'date_achat':   dateAchat?.toIso8601String(),
                    'etat_id':      etatId,
                    'salle_id':     salleId,
                    'host_name':    _emptyToNull(hostCtrl.text),
                    'systeme_exploitation': _emptyToNull(seCtrl.text),
                    'attribue_a':   _emptyToNull(attribueCtrl.text),
                    'date_assignation': dateAssign?.toIso8601String(),
                  };
                  try {
                    if (isEdit) {
                      await _sb.from('equipements').update(payload).eq('id', record!['id']);
                    } else {
                      await _sb.from('equipements').insert(payload);
                    }
                    _knownBrands.add(marqueCtrl.text.trim());
                    if (!mounted) return;
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(isEdit ? 'Équipement modifié' : 'Équipement ajouté')),
                    );
                  } on PostgrestException catch (e) {
                    final msg = (e.code=='23505')
                        ? 'Numéro de série déjà utilisé.'
                        : (e.code=='42501' ? 'Accès refusé (vérifie tes droits).' : e.message);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(msg), backgroundColor: Colors.red),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                child: Text(isEdit ? 'Enregistrer' : 'Ajouter'),
              ),
            ],
          );
        });
      },
    );
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    final listStream = _sb.from('equipements').stream(primaryKey: ['id']).order('updated_at', ascending: false);
    final histStream = _sb.from('equipements_hist').stream(primaryKey: ['id']).order('created_at', ascending: false);

    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: TabBar(tabs: [Tab(text: 'Liste'), Tab(text: 'Historique')]),
          ),

          Expanded(
            child: TabBarView(children: [
              // ======= Onglet Liste (table) =======
              Column(
                children: [
                  // filtres
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Wrap(
                      spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 420,
                          child: TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search),
                              hintText: 'Rechercher ',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () { _searchCtrl.clear(); setState(() {}); },
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        DropdownButton<String?>(
                          value: _filterType, hint: const Text('Type'),
                          items: [null, ..._types].map((t)=> DropdownMenuItem<String?>(value: t, child: Text(t ?? 'Tous'))).toList(),
                          onChanged: (v)=> setState(()=> _filterType = v),
                        ),
                        DropdownButton<String?>(
                          value: _filterEtatId, hint: const Text('Statut'),
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('Tous')),
                            ..._etats.map((e)=> DropdownMenuItem<String?>(
                              value: e['id'] as String,
                              child: Text(e['nom'] ?? '—'),
                            ))
                          ],
                          onChanged: (v)=> setState(()=> _filterEtatId = v),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: _canWrite ? _showAddDialog : null,
                          icon: const Icon(Icons.add),
                          label: const Text('Ajouter un équipement'),
                        ),
                      ],
                    ),
                  ),

                  // tableau
                  Expanded(
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: listStream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) return Center(child: Text('Erreur: ${snapshot.error}'));
                        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                        final rows = snapshot.data!;
                        final q = _searchCtrl.text.trim();

                        // fetch des chemins d’emplacement pour les lignes affichées
                        _ensureSallePaths(rows.map((e)=> e['salle_id'] as String?).whereType<String>().toSet());

                        final filtered = rows.where((r) => _rowMatches(r, q)).where((r) {
                          final typeOk = _filterType == null || r['type'] == _filterType;
                          final etatOk = _filterEtatId == null || r['etat_id'] == _filterEtatId;
                          return typeOk && etatOk;
                        }).toList();

                        if (filtered.isEmpty) return const Center(child: Text('Aucun équipement.'));

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
                                DataColumn(label: Text('État')),            // dérivé
                                DataColumn(label: Text(' ')),               // icône info
                                DataColumn(label: Text('N° série')),
                                DataColumn(label: Text('Modèle')),
                                DataColumn(label: Text('Marque')),
                                DataColumn(label: Text('Type')),
                                DataColumn(label: Text('Statut')),          // valeur fine DB
                                DataColumn(label: Text('Emplacement')),
                                DataColumn(label: Text('Date achat')),
                                DataColumn(label: Text('Attribué à')),
                                DataColumn(label: Text('Dernière modif')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows: filtered.map((e) {
                                final etatId = e['etat_id'] as String?;
                                final etatName = _etatNameById(etatId) ?? '—';
                                final sallePath = (e['salle_id'] != null)
                                  ? (_sallePath[e['salle_id']] ?? _salleName[e['salle_id']] ?? '—')
                                  : '—';
                                return DataRow(cells: [
                                  // ---- État (dérivé) : icône + libellé
                                  DataCell(_etatCell(etatName)),

                                  // ---- Détails
                                  DataCell(IconButton(
                                    icon: const Icon(Icons.info_outline),
                                    tooltip: 'Détails',
                                    onPressed: ()=> _showDetails(e),
                                  )),

                                  DataCell(Text(e['numero_serie'] ?? '—')),
                                  DataCell(Text(e['modele'] ?? '—')),
                                  DataCell(Text(e['marque'] ?? '—')),
                                  DataCell(Text(e['type'] ?? '—')),

                                  // ---- Statut (valeur DB, éditable)
                                  DataCell(
                                    DropdownButtonHideUnderline(
                                      child: DropdownButton<String?>(
                                        value: etatId,
                                        items: _etats.map((x)=> DropdownMenuItem<String?>(
                                          value: x['id'] as String,
                                          child: Text(x['nom'] ?? '—'),
                                        )).toList(),
                                        onChanged: !_canWrite ? null : (v) async {
                                          if (v == null) return;
                                          try {
                                            await _sb.from('equipements').update({'etat_id': v}).eq('id', e['id']);
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Statut mis à jour')),
                                              );
                                            }
                                          } catch (err) {
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Erreur: $err'), backgroundColor: Colors.red),
                                              );
                                            }
                                          }
                                        },
                                      ),
                                    ),
                                  ),

                                  DataCell(Text(sallePath)),
                                  DataCell(Text(_fmtDateOnly(e['date_achat']))),
                                  DataCell(Text(e['attribue_a'] ?? '—')),
                                  DataCell(Text(_fmtTs(e['updated_at']))),
                                  DataCell(IconButton(
                                    icon: const Icon(Icons.edit),
                                    tooltip: _canWrite ? 'Modifier' : 'Lecture seule',
                                    onPressed: _canWrite ? ()=> _showEditDialog(e) : null,
                                  )),
                                ]);
                              }).toList(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),

              // ======= Onglet Historique =======
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: histStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    final msg = snapshot.error.toString();
                    final friendly = msg.contains('PGRST205')
                      ? "Historique indisponible. Crée/active la table public.equipements_hist puis exécute: NOTIFY pgrst, 'reload schema';"
                      : msg;
                    return Center(child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text('Erreur: $friendly'),
                    ));
                  }
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final rows = snapshot.data!;
                  if (rows.isEmpty) return const Center(child: Text('Aucun événement.'));
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      final snap = Map<String, dynamic>.from(r['snapshot']);
                      final titre = '${(snap['modele'] ?? '—')} • ${(snap['marque'] ?? '—')}';
                      final serie = (snap['numero_serie'] ?? '—').toString();
                      final action = r['action'] == 'insert' ? 'Ajout' : 'Modification';
                      final who = r['changed_by_email'] ?? '—';
                      final when = _fmtTs(r['created_at']);
                      return Card(
                        elevation: 2,
                        child: ListTile(
                          leading: Icon(
                            r['action']=='insert' ? Icons.add_circle_outline : Icons.edit_outlined,
                            color: r['action']=='insert' ? Colors.green : Colors.orange,
                          ),
                          title: Text('$action — $titre'),
                          subtitle: Text('N° série: $serie\nPar: $who • $when'),
                        ),
                      );
                    },
                  );
                },
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // ========= helpers =========

  // Recherche “intelligente” (texte + date + statut + chemin d’emplacement + ÉTAT dérivé)
  bool _rowMatches(Map<String, dynamic> r, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;

    final qDate = _tryParseUserDate(q);

    final statutFin = _etatNameById(r['etat_id'] as String?) ?? '';
    final strings = <String>[
      r['numero_serie']?.toString() ?? '',
      r['modele']?.toString() ?? '',
      r['marque']?.toString() ?? '',
      r['type']?.toString() ?? '',
      r['host_name']?.toString() ?? '',
      r['systeme_exploitation']?.toString() ?? '',
      r['attribue_a']?.toString() ?? '',
      statutFin,                 // "Statut" (DB)
      _deriveEtat(statutFin),    // "État" dérivé (OK / En panne / HS)
      _sallePath[r['salle_id']] ?? _salleName[r['salle_id']] ?? '',
    ].map((s) => s.toLowerCase()).toList();

    final textOk = strings.any((s) => s.contains(q));

    bool dateOk = false;
    if (qDate != null) {
      dateOk = _sameDay(_parseTs(r['date_achat']), qDate) ||
               _sameDay(_parseTs(r['created_at']), qDate) ||
               _sameDay(_parseTs(r['updated_at']), qDate);
    }

    return textOk || dateOk;
  }

  String? _etatNameById(String? id) {
    if (id == null) return null;
    final m = _etats.firstWhere((e)=> e['id']==id, orElse: ()=> const {'nom': null});
    return m['nom'] as String?;
  }

  // ----- ÉTAT dérivé (OK / En panne / HS) à partir du Statut (DB) -----

  String _fold(String? s) {
    if (s == null) return '';
    final lower = s.toLowerCase();
    return lower
      .replaceAll('é','e').replaceAll('è','e').replaceAll('ê','e').replaceAll('ë','e')
      .replaceAll('à','a').replaceAll('â','a')
      .replaceAll('î','i').replaceAll('ï','i')
      .replaceAll('ô','o').replaceAll('ö','o')
      .replaceAll('ù','u').replaceAll('û','u').replaceAll('ü','u')
      .replaceAll('ç','c');
  }

  /// Retourne 'OK', 'En panne' ou 'HS' selon la règle donnée
  String _deriveEtat(String? statutDbName) {
    final n = _fold(statutDbName).trim();

    // Groupes EXACTS connus
    const okExact = ['en utilisation','inactif','prete','pret'];
    const panneExact = ['en panne']; // au cas où la valeur existe telle quelle
    const hsExact = ['mis au rebut','donne','donnee','donne(e)','offert','offerte'];

    // 1) Égalités exactes (après normalisation)
    if (okExact.contains(n)) return 'OK';
    if (panneExact.contains(n)) return 'En panne';
    if (hsExact.contains(n)) return 'HS';

    // 2) Test par "contains" pour robustesse (fautes/synonymes)
    if (n.contains('utilisation') || n == 'inactif' || n.contains('pret')) return 'OK';
    if (n.contains('mainten')) return 'En panne';                 // "maintenance" ou "maintenace"
    if (n.contains('rebut') || n.contains('donne') || n.contains('offert')) return 'HS';

    // 3) Par défaut => OK (choix conservateur)
    return 'OK';
  }

  IconData _etatIcon(String label) {
    switch (label) {
      case 'OK': return Icons.check_circle;
      case 'En panne': return Icons.build_circle;
      case 'HS': return Icons.cancel;
      default: return Icons.help_outline;
    }
  }

  Color _etatColor(String label) {
    switch (label) {
      case 'OK': return Colors.green;
      case 'En panne': return Colors.orange;
      case 'HS': return Colors.red;
      default: return Colors.grey;
    }
  }

  /// Cellule “État” (dérivé) : icône + libellé
  Widget _etatCell(String? statutDbName) {
    final label = _deriveEtat(statutDbName);
    final color = _etatColor(label);
    return Row(
      children: [
        Icon(_etatIcon(label), color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Future<void> _ensureSallePaths(Set<String> ids) async {
    final missing = ids.where((id) => !_sallePath.containsKey(id)).toSet();
    if (missing.isEmpty) return;

    final idsCsv = _inCsv(missing);
    try {
      final salles = List<Map<String, dynamic>>.from(
        await _sb.from('salles').select('id, nom, batiment_id').filter('id','in', idsCsv) as List
      );
      for (final s in salles) {
        _salleName[s['id'] as String] = (s['nom'] as String?) ?? '—';
      }
      final batIds = salles.map((s)=> s['batiment_id'] as String?).whereType<String>().toSet();
      if (batIds.isEmpty) return;

      final batsCsv = _inCsv(batIds);
      final bats = List<Map<String, dynamic>>.from(
        await _sb.from('batiments').select('id, nom, site_id').filter('id','in', batsCsv) as List
      );
      final siteIds = bats.map((b)=> b['site_id'] as String?).whereType<String>().toSet();
      final sitesCsv = siteIds.isEmpty ? null : _inCsv(siteIds);
      final sites = siteIds.isEmpty ? <Map<String,dynamic>>[] :
        List<Map<String, dynamic>>.from(
          await _sb.from('sites').select('id, nom').filter('id','in', sitesCsv!) as List
        );

      final batById  = { for (final b in bats)  b['id'] as String : b };
      final siteById = { for (final s in sites) s['id'] as String : s };

      for (final s in salles) {
        final b = batById[s['batiment_id']];
        final siteName = (b != null && siteById[b['site_id']] != null)
          ? (siteById[b['site_id']]?['nom'] as String? ?? '—') : '—';
        final batName  = b != null ? (b['nom'] as String? ?? '—') : '—';
        final salName  = (s['nom'] as String?) ?? '—';
        _sallePath[s['id'] as String] = '$siteName / $batName / $salName';
      }
      if (mounted) setState(() {});
    } catch (_) {/* silencieux */}
  }

  // Helpers UI
  static Widget _buildText(TextEditingController c, String label, IconData icon, {bool required = false}) {
    return TextFormField(
      controller: c,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), border: const OutlineInputBorder()),
      validator: (v) => (!required) ? null : (v==null || v.trim().isEmpty ? 'Champ requis' : null),
    );
  }

  static Widget _buildDateField({required String label, required DateTime? value, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.event), border: const OutlineInputBorder()),
        child: Text(value == null ? '—' : '${value.year}-${_2(value.month)}-${_2(value.day)}'),
      ),
    );
  }

  // Dialog détails
  void _showDetails(Map<String, dynamic> e) {
    final statutFin = _etatNameById(e['etat_id'] as String?) ?? '—';
    final sallePath = (e['salle_id'] != null) ? (_sallePath[e['salle_id']] ?? _salleName[e['salle_id']] ?? '—') : '—';
    showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: const Text('Détails équipement'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('N° série', e['numero_serie']),
              _kv('Modèle', e['modele']),
              _kv('Marque', e['marque']),
              _kv('Type', e['type']),
              _kv('État', _deriveEtat(statutFin)), // dérivé
              _kv('Statut', statutFin),            // valeur DB
              _kv('Emplacement', sallePath),
              _kv('Host name', e['host_name']),
              _kv('Système d’exploitation', e['systeme_exploitation']),
              _kv('Attribué à', e['attribue_a']),
              _kv('Date achat', _fmtDateOnly(e['date_achat'])),
              _kv('Date assignation', _fmtDateOnly(e['date_assignation'])),
              const Divider(),
              _kv('Créé le', _fmtTs(e['created_at'])),
              _kv('Dernière modif', _fmtTs(e['updated_at'])),
              _kv('Ajouté par', e['created_by_email']),
              _kv('Modifié par', e['updated_by_email']),
            ],
          ),
        ),
        actions: [TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Fermer'))],
      );
    });
  }

  static Widget _kv(String k, dynamic v) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      SizedBox(width: 150, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
      Expanded(child: Text(v?.toString() ?? '—')),
    ]),
  );

  // Parse date utilisateur (YYYY-MM-DD ou DD/MM/YYYY)
  static DateTime? _tryParseUserDate(String q) {
    String s = q.trim();
    final re = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$');
    final m = re.firstMatch(s);
    if (m != null) {
      s = '${m.group(3)}-${m.group(2)!.padLeft(2,'0')}-${m.group(1)!.padLeft(2,'0')}';
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
    return a.year==b.year && a.month==b.month && a.day==b.day;
  }

  static String _fmtDateOnly(dynamic ts) {
    final d = _parseTs(ts); if (d==null) return '—';
    return '${d.year}-${_2(d.month)}-${_2(d.day)}';
  }

  static String _fmtTs(dynamic ts) {
    final d = _parseTs(ts); if (d==null) return '—';
    return '${d.year}-${_2(d.month)}-${_2(d.day)} ${_2(d.hour)}:${_2(d.minute)}';
  }

  static DateTime? _parseTs(dynamic ts) {
    if (ts==null) return null;
    try { return DateTime.parse(ts.toString()).toLocal(); } catch(_) { return null; }
  }
  static String _2(int x) => x.toString().padLeft(2, '0');

  // util pour PostgREST in()
  static String _inCsv(Iterable<String> ids) => '(${ids.map((e)=> '"$e"').join(',')})';
}
*/
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/supabase_client.dart';

class EquipementsPage extends StatefulWidget {
  const EquipementsPage({super.key});
  @override
  State<EquipementsPage> createState() => _EquipementsPageState();
}

class _EquipementsPageState extends State<EquipementsPage> {
  final _sb = SB.client;

  // ----- rôles / droits -----
  String? _role;
  bool _loadingRole = true;
  bool get _canWrite => _role == 'technicien' || _role == 'super-admin';

  // ----- filtres liste -----
  final _searchCtrl = TextEditingController();
  String? _filterType;
  String? _filterEtatId; // filtre sur le "Statut" (DB)

  // ----- recherche historique -----
  final _histSearchCtrl = TextEditingController();

  // ----- référentiels -----
  List<Map<String, dynamic>> _etats = [];
  Set<String> _knownBrands = {};
  final Map<String, String> _salleName = {}; // id -> 'Salle'
  final Map<String, String> _sallePath = {}; // id -> 'Site / Bâtiment / Salle'

  // ----- cache utilisateurs (pour "Attribué à") -----
  List<Map<String, dynamic>> _users = [];  // [{id,email}]
  List<String> _userEmails = [];           // auto-complétion

  // types autorisés
  static const List<String> _types = [
    'Unité centrale','Laptop','Ecran','Imprimante','Vidéo projecteur','Clavier','Souris','Station','Scanner',
  ];

  // OS autorisés
  static const List<String> _oses = ['Windows 11', 'Windows 10', 'Windows 7'];

  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadEtats();
    _loadBrands();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _histSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRole() async {
    setState(() => _loadingRole = true);
    try {
      final user = _sb.auth.currentUser;
      String? role = user?.userMetadata?['role'] as String?;
      if (user != null) {
        final delays = [0, 300, 800, 1500];
        for (final d in delays) {
          if (d > 0) await Future.delayed(Duration(milliseconds: d));
          try {
            final r = await _sb.from('users').select('role').eq('id', user.id).maybeSingle();
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

  Future<void> _loadEtats() async {
    try {
      final res = await _sb.from('etats').select('id, nom').order('nom');
      setState(() => _etats = List<Map<String, dynamic>>.from(res as List));
    } catch (_) {}
  }

  Future<void> _loadBrands() async {
    try {
      final res = await _sb.from('equipements').select('marque').not('marque','is',null);
      final list = List<Map<String, dynamic>>.from(res as List);
      setState(() => _knownBrands = list.map((e)=> (e['marque']??'').toString().trim()).where((s)=>s.isNotEmpty).toSet());
    } catch (_) {}
  }

  Future<void> _loadUsers() async {
    try {
      final res = await _sb.from('users').select('id,email').order('email');
      final list = List<Map<String, dynamic>>.from(res as List);
      setState(() {
        _users = list;
        _userEmails = list.map((e) => (e['email'] ?? '').toString()).where((s) => s.isNotEmpty).toList();
      });
    } catch (_) {}
  }

  // ================= Ajout / édition =================

  Future<void> _showAddDialog() async {
    final defaults = await _computeDefaults(); // inactif + base wouri/700/magasin si dispo
    await _showEditDialog(null, defaults: defaults);
  }

  static String? _emptyToNull(String? s) {
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<Map<String,String?>> _computeDefaults() async {
    // par défaut : statut "inactif" + Base Wouri / 700 / Magasin si existants
    String? etatId, siteId, batId, salleId;
    try {
      final e = await _sb.from('etats').select('id').ilike('nom','inactif').maybeSingle();
      etatId = e?['id'] as String?;
    } catch (_) {}
    try {
      final loc = await _locIds(site: 'base wouri', bat: '700', salle: 'magasin');
      siteId  = loc['siteId'];
      batId   = loc['batId'];
      salleId = loc['salleId'];
    } catch (_) {}
    return {'etatId': etatId,'siteId': siteId,'batId': batId,'salleId': salleId};
  }

  Future<Map<String,String?>> _locIds({required String site, required String bat, required String salle}) async {
    String? siteId, batId, salleId;
    try {
      final s = await _sb.from('sites').select('id').ilike('nom', site).maybeSingle();
      siteId = s?['id'] as String?;
      if (siteId != null) {
        final b = await _sb.from('batiments').select('id').eq('site_id', siteId).ilike('nom', bat).maybeSingle();
        batId = b?['id'] as String?;
        if (batId != null) {
          final sa = await _sb.from('salles').select('id, nom').eq('batiment_id', batId).ilike('nom', salle).maybeSingle();
          salleId = sa?['id'] as String?;
          if (sa != null && sa['id'] != null) _salleName[sa['id'] as String] = sa['nom'] as String? ?? '—';
        }
      }
    } catch (_) {}
    return {'siteId': siteId, 'batId': batId, 'salleId': salleId};
  }

  Future<void> _showEditDialog(Map<String, dynamic>? record, {Map<String,String?>? defaults}) async {
    final isEdit = record != null;

    final serieCtrl    = TextEditingController(text: record?['numero_serie'] ?? '');
    final modeleCtrl   = TextEditingController(text: record?['modele'] ?? '');
    final marqueCtrl   = TextEditingController(text: record?['marque'] ?? '');
    final hostCtrl     = TextEditingController(text: record?['host_name'] ?? '');
    final seCtrl       = TextEditingController(text: record?['systeme_exploitation'] ?? '');
    final attribueCtrl = TextEditingController(text: record?['attribue_a'] ?? '');

    DateTime? dateAchat  = _parseTs(record?['date_achat']);
    DateTime? dateAssign = _parseTs(record?['date_assignation']);

    String? type   = record?['type'];
    String? etatId = record?['etat_id'] ?? defaults?['etatId'];
    String? siteId = defaults?['siteId'];
    String? batId  = defaults?['batId'];
    String? salleId= record?['salle_id'] ?? defaults?['salleId'];

    if (isEdit && salleId != null) {
      try {
        final s = await _sb.from('salles').select('id, nom, batiment_id').eq('id', salleId).maybeSingle();
        _salleName[salleId] = s?['nom'] as String? ?? '—';
        batId  = s?['batiment_id'] as String?;
        if (batId != null) {
          final b = await _sb.from('batiments').select('id, site_id').eq('id', batId).maybeSingle();
          siteId = b?['site_id'] as String?;
        }
      } catch (_) {}
    }

    // helpers de listes
    Future<List<Map<String, dynamic>>> _sites() async =>
      List<Map<String, dynamic>>.from(await _sb.from('sites').select('id, nom').order('nom') as List);
    Future<List<Map<String, dynamic>>> _bats(String sId) async =>
      List<Map<String, dynamic>>.from(await _sb.from('batiments').select('id, nom').eq('site_id', sId).order('nom') as List);
    Future<List<Map<String, dynamic>>> _salles(String bId) async =>
      List<Map<String, dynamic>>.from(await _sb.from('salles').select('id, nom').eq('batiment_id', bId).order('nom') as List);

    await showDialog(
      context: context,
      builder: (ctx) {
        final formKey = GlobalKey<FormState>();

        return StatefulBuilder(builder: (context, setState) {
          Future<void> pickDateAchat() async {
            final now = DateTime.now();
            final p = await showDatePicker(
              context: context,
              firstDate: DateTime(now.year-15),
              lastDate: DateTime(now.year+1),
              initialDate: dateAchat ?? now,
            );
            if (p != null) setState(() => dateAchat = p);
          }
          Future<void> pickDateAssign() async {
            final now = DateTime.now();
            final p = await showDatePicker(
              context: context,
              firstDate: DateTime(now.year-15),
              lastDate: DateTime(now.year+1),
              initialDate: dateAssign ?? now,
            );
            if (p != null) setState(() => dateAssign = p);
          }

          return AlertDialog(
            title: Text(isEdit ? 'Modifier l’équipement' : 'Ajouter un équipement'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _buildText(serieCtrl,  'Numéro de série *', Icons.confirmation_number, required: true),
                  const SizedBox(height: 12),
                  _buildText(modeleCtrl, 'Modèle *', Icons.devices, required: true),
                  const SizedBox(height: 12),

                  // Marque obligatoire + suggestions
                  RawAutocomplete<String>(
                    textEditingController: marqueCtrl,
                    focusNode: FocusNode(),
                    optionsBuilder: (v) {
                      final q = v.text.trim().toLowerCase();
                      if (q.isEmpty) return const Iterable<String>.empty();
                      return _knownBrands.where((b)=> b.toLowerCase().contains(q)).take(8);
                    },
                    fieldViewBuilder: (_, controller, focus, __) => TextFormField(
                      controller: controller, focusNode: focus,
                      decoration: const InputDecoration(
                        labelText: 'Marque *',
                        prefixIcon: Icon(Icons.sell),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v==null||v.trim().isEmpty) ? 'Champ requis' : null,
                    ),
                    optionsViewBuilder: (_, onSelected, opts) => Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
                          child: ListView(
                            padding: EdgeInsets.zero,
                            children: opts.map((o)=> ListTile(
                              title: Text(o),
                              onTap: ()=> onSelected(o),
                            )).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _buildDateField(label: 'Date d’achat *', value: dateAchat, onTap: pickDateAchat),

                  const Divider(height: 24),

                  // Type
                  DropdownButtonFormField<String?>(
                    decoration: const InputDecoration(labelText: 'Type *', border: OutlineInputBorder()),
                    value: type!=null && _types.contains(type) ? type : null,
                    items: _types.map((t)=> DropdownMenuItem<String?>(value: t, child: Text(t))).toList(),
                    onChanged: (v)=> setState(()=> type = v),
                    validator: (v)=> (v==null||v.isEmpty) ? 'Champ requis' : null,
                  ),
                  const SizedBox(height: 12),

                  // "Statut" (valeur DB)
                  DropdownButtonFormField<String?>(
                    decoration: const InputDecoration(labelText: 'Statut', border: OutlineInputBorder()),
                    value: etatId,
                    items: _etats.map((e)=> DropdownMenuItem<String?>(
                      value: e['id'] as String,
                      child: Text(e['nom'] ?? '—'),
                    )).toList(),
                    onChanged: (v) async {
                      setState(()=> etatId = v);
                      // règles dynamiques d’emplacement + champs d’assignation
                      final nom = _fold(_etatName(etatId));
                      if (nom == 'inactif') {
                        final ids = await _locIds(site: 'base wouri', bat: '700', salle: 'magasin');
                        setState(() {
                          siteId = ids['siteId']; batId = ids['batId']; salleId = ids['salleId'];
                          attribueCtrl.clear(); dateAssign = null;
                        });
                      } else if (nom.contains('rebut') || nom.contains('donne')) {
                        final ids = await _locIds(site: 'base wouri', bat: '700', salle: 'hse');
                        setState(() {
                          siteId = ids['siteId']; batId = ids['batId']; salleId = ids['salleId'];
                          attribueCtrl.clear(); dateAssign = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),

                  // Site -> Bâtiment -> Salle
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _sites(),
                    builder: (_, snap) {
                      final sites = snap.data ?? [];
                      return DropdownButtonFormField<String?>(
                        decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
                        value: siteId,
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('—')),
                          ...sites.map((s)=> DropdownMenuItem<String?>(
                            value: s['id'] as String,
                            child: Text(s['nom'] ?? 'Sans nom'),
                          ))
                        ],
                        onChanged: (v){ setState((){ siteId = v; batId = null; salleId = null; }); },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  if (siteId != null)
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _bats(siteId!),
                      builder: (_, snap) {
                        final bats = snap.data ?? [];
                        return DropdownButtonFormField<String?>(
                          decoration: const InputDecoration(labelText: 'Bâtiment', border: OutlineInputBorder()),
                          value: batId,
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('—')),
                            ...bats.map((b)=> DropdownMenuItem<String?>(
                              value: b['id'] as String,
                              child: Text(b['nom'] ?? 'Sans nom'),
                            ))
                          ],
                          onChanged: (v){ setState((){ batId = v; salleId = null; }); },
                        );
                      },
                    ),
                  const SizedBox(height: 12),
                  if (batId != null)
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _salles(batId!),
                      builder: (_, snap) {
                        final salles = snap.data ?? [];
                        return DropdownButtonFormField<String?>(
                          decoration: const InputDecoration(labelText: 'Salle', border: OutlineInputBorder()),
                          value: salleId,
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('—')),
                            ...salles.map((s)=> DropdownMenuItem<String?>(
                              value: s['id'] as String,
                              child: Text(s['nom'] ?? 'Sans nom'),
                            ))
                          ],
                          onChanged: (v){
                            setState(()=> salleId = v);
                            if (v!=null) {
                              final m = salles.firstWhere((x)=> x['id']==v, orElse: ()=> {});
                              if (m.isNotEmpty) _salleName[v] = (m['nom'] as String?) ?? '—';
                            }
                          },
                        );
                      },
                    ),
                  const SizedBox(height: 12),

                  // Hostname
                  _buildText(hostCtrl, 'Host name (optionnel)', Icons.computer),
                  const SizedBox(height: 12),

                  // OS en enum
                  DropdownButtonFormField<String?>(
                    value: (seCtrl.text.isEmpty) ? null : seCtrl.text,
                    decoration: const InputDecoration(
                      labelText: 'Système d’exploitation',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('—')),
                      ..._oses.map((o) => DropdownMenuItem<String?>(value: o, child: Text(o))),
                    ],
                    onChanged: (v) => setState(() => seCtrl.text = v ?? ''),
                  ),
                  const SizedBox(height: 12),

                  // Attribué à (auto-complétion) – désactivé selon statut
                  Builder(builder: (_) {
                    final etatNom = _fold(_etatName(etatId));
                    final disabled = etatNom == 'inactif' || etatNom.contains('rebut') || etatNom.contains('donne');
                    return Opacity(
                      opacity: disabled ? 0.5 : 1,
                      child: IgnorePointer(
                        ignoring: disabled,
                        child: RawAutocomplete<String>(
                          textEditingController: attribueCtrl,
                          focusNode: FocusNode(),
                          optionsBuilder: (TextEditingValue tev) {
                            final q = tev.text.trim().toLowerCase();
                            if (q.isEmpty) return const Iterable<String>.empty();
                            return _userEmails.where((e) => e.toLowerCase().startsWith(q)).take(12);
                          },
                          fieldViewBuilder: (_, controller, focus, __) => TextFormField(
                            controller: controller,
                            focusNode: focus,
                            decoration: const InputDecoration(
                              labelText: 'Attribué à (email)',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              final needUser = etatNom.contains('utilisation') || etatNom.startsWith('prete') || etatNom.contains('pret');
                              if (!needUser) return null;
                              if (v==null || v.trim().isEmpty) return 'Requis pour ce statut';
                              return null;
                            },
                          ),
                          optionsViewBuilder: (_, onSelected, opts) => Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 220, maxWidth: 360),
                                child: ListView(
                                  padding: EdgeInsets.zero,
                                  children: opts.map((o) => ListTile(
                                    title: Text(o),
                                    onTap: () => onSelected(o),
                                  )).toList(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),

                  // Date d’assignation – désactivée selon statut
                  Builder(builder: (_) {
                    final etatNom = _fold(_etatName(etatId));
                    final disabled = etatNom == 'inactif' || etatNom.contains('rebut') || etatNom.contains('donne');
                    return Opacity(
                      opacity: disabled ? 0.5 : 1,
                      child: IgnorePointer(
                        ignoring: disabled,
                        child: _buildDateField(
                          label: 'Date d’assignation',
                          value: dateAssign,
                          onTap: pickDateAssign,
                        ),
                      ),
                    );
                  }),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: ()=> Navigator.pop(ctx), child: const Text('Annuler')),
              ElevatedButton(
                onPressed: !_canWrite ? null : () async {
                  if (!(formKey.currentState?.validate() ?? false)) return;
                  if (marqueCtrl.text.trim().isEmpty || dateAchat==null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Remplis les champs requis'), backgroundColor: Colors.red),
                    );
                    return;
                  }

                  final etatNom = _fold(_etatName(etatId));
                  final needUser = etatNom.contains('utilisation') || etatNom.startsWith('prete') || etatNom.contains('pret');
                  final forbidUser = etatNom == 'inactif' || etatNom.contains('rebut') || etatNom.contains('donne');

                  if (needUser) {
                    if (attribueCtrl.text.trim().isEmpty || dateAssign == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Renseigne "Attribué à" et la date d’assignation.'), backgroundColor: Colors.red),
                      );
                      return;
                    }
                  }

                  final payload = {
                    'numero_serie': serieCtrl.text.trim(),
                    'modele':       modeleCtrl.text.trim(),
                    'marque':       marqueCtrl.text.trim(),
                    'type':         type,
                    'date_achat':   dateAchat?.toIso8601String(),
                    'etat_id':      etatId,
                    'salle_id':     salleId,
                    'host_name':    _emptyToNull(hostCtrl.text),
                    'systeme_exploitation': _emptyToNull(seCtrl.text),
                    'attribue_a':   forbidUser ? null : _emptyToNull(attribueCtrl.text),
                    'date_assignation': forbidUser ? null : dateAssign?.toIso8601String(),
                  };

                  try {
                    if (isEdit) {
                      await _sb.from('equipements').update(payload).eq('id', record!['id']);
                    } else {
                      await _sb.from('equipements').insert(payload);
                    }
                    _knownBrands.add(marqueCtrl.text.trim());
                    if (!mounted) return;
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(isEdit ? 'Équipement modifié' : 'Équipement ajouté')),
                    );
                  } on PostgrestException catch (e) {
                    final msg = (e.code=='23505')
                        ? 'Numéro de série déjà utilisé.'
                        : (e.code=='42501' ? 'Accès refusé (vérifie tes droits).' : e.message);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(msg), backgroundColor: Colors.red),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                child: Text(isEdit ? 'Enregistrer' : 'Ajouter'),
              ),
            ],
          );
        });
      },
    );
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    final listStream = _sb.from('equipements').stream(primaryKey: ['id']).order('updated_at', ascending: false);
    final histStream = _sb.from('equipements_hist').stream(primaryKey: ['id']).order('created_at', ascending: false);

    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: TabBar(tabs: [Tab(text: 'Liste'), Tab(text: 'Historique')]),
          ),

          Expanded(
            child: TabBarView(children: [
              // ======= Onglet Liste (table) =======
              Column(
                children: [
                  // filtres
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Wrap(
                      spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 420,
                          child: TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search),
                              hintText: 'Rechercher ',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () { _searchCtrl.clear(); setState(() {}); },
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        DropdownButton<String?>(value: _filterType, hint: const Text('Type'),
                          items: [null, ..._types].map((t)=> DropdownMenuItem<String?>(value: t, child: Text(t ?? 'Tous'))).toList(),
                          onChanged: (v)=> setState(()=> _filterType = v),
                        ),
                        DropdownButton<String?>(value: _filterEtatId, hint: const Text('Statut'),
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('Tous')),
                            ..._etats.map((e)=> DropdownMenuItem<String?>(
                              value: e['id'] as String,
                              child: Text(e['nom'] ?? '—'),
                            ))
                          ],
                          onChanged: (v)=> setState(()=> _filterEtatId = v),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: _canWrite ? _showAddDialog : null,
                          icon: const Icon(Icons.add),
                          label: const Text('Ajouter un équipement'),
                        ),
                      ],
                    ),
                  ),

                  // tableau
                  Expanded(
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: listStream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) return Center(child: Text('Erreur: ${snapshot.error}'));
                        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                        final rows = snapshot.data!;
                        final q = _searchCtrl.text.trim();

                        // fetch des chemins d’emplacement
                        _ensureSallePaths(rows.map((e)=> e['salle_id'] as String?).whereType<String>().toSet());

                        final filtered = rows.where((r) => _rowMatches(r, q)).where((r) {
                          final typeOk = _filterType == null || r['type'] == _filterType;
                          final etatOk = _filterEtatId == null || r['etat_id'] == _filterEtatId;
                          return typeOk && etatOk;
                        }).toList();

                        if (filtered.isEmpty) return const Center(child: Text('Aucun équipement.'));

                        final count = filtered.length;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 24, right: 24, bottom: 6),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Chip(label: Text('$count résultat${count>1?'s':''}')),
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
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    columns: const [
                                      DataColumn(label: Text('État')),            // dérivé
                                      DataColumn(label: Text(' ')),               // icône info
                                      DataColumn(label: Text('N° série')),
                                      DataColumn(label: Text('Modèle')),
                                      DataColumn(label: Text('Marque')),
                                      DataColumn(label: Text('Host name')),       // dans les 7 premières
                                      DataColumn(label: Text('Type')),
                                      DataColumn(label: Text('Statut')),          // valeur DB
                                      DataColumn(label: Text('Emplacement')),
                                      DataColumn(label: Text('Date achat')),
                                      DataColumn(label: Text('Attribué à')),
                                      DataColumn(label: Text('Dernière modif')),
                                      DataColumn(label: Text('Actions')),
                                    ],
                                    rows: filtered.map((e) {
                                      final etatId = e['etat_id'] as String?;
                                      final etatName = _etatNameById(etatId) ?? '—';
                                      final sallePath = (e['salle_id'] != null)
                                        ? (_sallePath[e['salle_id']] ?? _salleName[e['salle_id']] ?? '—')
                                        : '—';
                                      return DataRow(cells: [
                                        // ---- État (dérivé) : icône + libellé
                                        DataCell(_etatCell(etatName)),

                                        // ---- Détails
                                        DataCell(IconButton(
                                          icon: const Icon(Icons.info_outline),
                                          tooltip: 'Détails',
                                          onPressed: ()=> _showDetails(e),
                                        )),

                                        DataCell(Text(e['numero_serie'] ?? '—')),
                                        DataCell(Text(e['modele'] ?? '—')),
                                        DataCell(Text(e['marque'] ?? '—')),
                                        DataCell(Text(e['host_name'] ?? '—')),    // host visible tôt
                                        DataCell(Text(e['type'] ?? '—')),

                                        // ---- Statut (valeur DB, éditable)
                                        DataCell(
                                          DropdownButtonHideUnderline(
                                            child: DropdownButton<String?>(
                                              value: etatId,
                                              items: _etats.map((x)=> DropdownMenuItem<String?>(
                                                value: x['id'] as String,
                                                child: Text(x['nom'] ?? '—'),
                                              )).toList(),
                                              onChanged: !_canWrite ? null : (v) async {
                                                if (v == null) return;
                                                try {
                                                  await _sb.from('equipements').update({'etat_id': v}).eq('id', e['id']);
                                                  if (mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(content: Text('Statut mis à jour')),
                                                    );
                                                  }
                                                } catch (err) {
                                                  if (mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(content: Text('Erreur: $err'), backgroundColor: Colors.red),
                                                    );
                                                  }
                                                }
                                              },
                                            ),
                                          ),
                                        ),

                                        DataCell(Text(sallePath)),
                                        DataCell(Text(_fmtDateOnly(e['date_achat']))),
                                        DataCell(Text(e['attribue_a'] ?? '—')),
                                        DataCell(Text(_fmtTs(e['updated_at']))),
                                        DataCell(IconButton(
                                          icon: const Icon(Icons.edit),
                                          tooltip: _canWrite ? 'Modifier' : 'Lecture seule',
                                          onPressed: _canWrite ? ()=> _showEditDialog(e) : null,
                                        )),
                                      ]);
                                    }).toList(),
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
              ),

              // ======= Onglet Historique =======
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      controller: _histSearchCtrl,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Rechercher (série, modèle, marque, email, utilisateur...)',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () { _histSearchCtrl.clear(); setState(() {}); },
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: histStream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          final msg = snapshot.error.toString();
                          final friendly = msg.contains('PGRST205')
                            ? "Historique indisponible. Crée/active la table public.equipements_hist puis exécute: NOTIFY pgrst, 'reload schema';"
                            : msg;
                          return Center(child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Text('Erreur: $friendly'),
                          ));
                        }
                        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                        final q = _histSearchCtrl.text.trim().toLowerCase();
                        final rows = snapshot.data!;

                        // Filtrage simple
                        List<Map<String, dynamic>> filtered = rows.where((r) {
                          final snap = Map<String, dynamic>.from(r['snapshot'] ?? {});
                          final texts = [
                            (snap['numero_serie'] ?? '').toString(),
                            (snap['modele'] ?? '').toString(),
                            (snap['marque'] ?? '').toString(),
                            (snap['attribue_a'] ?? '').toString(),
                            (r['changed_by_email'] ?? '').toString(),
                          ].map((s)=> s.toLowerCase());
                          return q.isEmpty || texts.any((s)=> s.contains(q));
                        }).toList();

                        // Résumé “utilisateurs & dates” si recherche active
                        Widget? resumeUsage;
                        if (q.isNotEmpty) {
                          final usage = <String, List<String>>{}; // email -> dates
                          for (final r in filtered) {
                            final snap = Map<String, dynamic>.from(r['snapshot'] ?? {});
                            final email = (snap['attribue_a'] ?? '').toString();
                            final date  = (snap['date_assignation'] ?? '').toString();
                            if (email.isNotEmpty && date.isNotEmpty) {
                              usage.putIfAbsent(email, ()=> []).add(_fmtDateOnly(date));
                            }
                          }
                          if (usage.isNotEmpty) {
                            resumeUsage = Card(
                              margin: const EdgeInsets.symmetric(horizontal:16),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Utilisateurs de cet équipement', style: TextStyle(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8, runSpacing: 8,
                                      children: usage.entries.map((e) =>
                                        Chip(label: Text('${e.key} • ${e.value.toSet().join(', ')}'))
                                      ).toList(),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                        }

                        final count = filtered.length;

                        return ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (resumeUsage != null) resumeUsage,
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Chip(label: Text('$count événement${count>1?'s':''}')),
                            ),
                            const SizedBox(height: 10),
                            ...filtered.map((r) {
                              final snap = Map<String, dynamic>.from(r['snapshot']);
                              final titre = '${(snap['modele'] ?? '—')} • ${(snap['marque'] ?? '—')}';
                              final serie = (snap['numero_serie'] ?? '—').toString();
                              final action = r['action'] == 'insert' ? 'Ajout' : 'Modification';
                              final who = r['changed_by_email'] ?? '—';
                              final when = _fmtTs(r['created_at']);
                              return Card(
                                elevation: 2,
                                child: ListTile(
                                  leading: Icon(
                                    r['action']=='insert' ? Icons.add_circle_outline : Icons.edit_outlined,
                                    color: r['action']=='insert' ? Colors.green : Colors.orange,
                                  ),
                                  title: Text('$action — $titre'),
                                  subtitle: Text('N° série: $serie\nPar: $who • $when'),
                                ),
                              );
                            }),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // ========= helpers =========

  // renvoie le libellé du statut depuis etat_id
  String _etatName(String? etatId) => _etatNameById(etatId) ?? '';

  // Recherche “intelligente”
  bool _rowMatches(Map<String, dynamic> r, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;

    final qDate = _tryParseUserDate(q);

    final statutFin = _etatNameById(r['etat_id'] as String?) ?? '';
    final strings = <String>[
      r['numero_serie']?.toString() ?? '',
      r['modele']?.toString() ?? '',
      r['marque']?.toString() ?? '',
      r['type']?.toString() ?? '',
      r['host_name']?.toString() ?? '',
      r['systeme_exploitation']?.toString() ?? '',
      r['attribue_a']?.toString() ?? '',
      statutFin,
      _deriveEtat(statutFin),
      _sallePath[r['salle_id']] ?? _salleName[r['salle_id']] ?? '',
    ].map((s) => s.toLowerCase()).toList();

    final textOk = strings.any((s) => s.contains(q));

    bool dateOk = false;
    if (qDate != null) {
      dateOk = _sameDay(_parseTs(r['date_achat']), qDate) ||
               _sameDay(_parseTs(r['created_at']), qDate) ||
               _sameDay(_parseTs(r['updated_at']), qDate);
    }

    return textOk || dateOk;
  }

  String? _etatNameById(String? id) {
    if (id == null) return null;
    final m = _etats.firstWhere((e)=> e['id']==id, orElse: ()=> const {'nom': null});
    return m['nom'] as String?;
  }

  // ----- ÉTAT dérivé (OK / En panne / HS) à partir du Statut (DB) -----

  String _fold(String? s) {
    if (s == null) return '';
    final lower = s.toLowerCase().trim();
    return lower
      .replaceAll('é','e').replaceAll('è','e').replaceAll('ê','e').replaceAll('ë','e')
      .replaceAll('à','a').replaceAll('â','a')
      .replaceAll('î','i').replaceAll('ï','i')
      .replaceAll('ô','o').replaceAll('ö','o')
      .replaceAll('ù','u').replaceAll('û','u').replaceAll('ü','u')
      .replaceAll('ç','c');
  }

  String _deriveEtat(String? statutDbName) {
    final n = _fold(statutDbName);
    const okExact = ['en utilisation','inactif','prete','pret'];
    const panneExact = ['en panne'];
    const hsExact = ['mis au rebut','donne','donnee','donne(e)','offert','offerte'];
    if (okExact.contains(n)) return 'OK';
    if (panneExact.contains(n)) return 'En panne';
    if (hsExact.contains(n)) return 'HS';
    if (n.contains('utilisation') || n == 'inactif' || n.contains('pret')) return 'OK';
    if (n.contains('mainten')) return 'En panne';
    if (n.contains('rebut') || n.contains('donne') || n.contains('offert')) return 'HS';
    return 'OK';
  }

  IconData _etatIcon(String label) {
    switch (label) {
      case 'OK': return Icons.check_circle;
      case 'En panne': return Icons.build_circle;
      case 'HS': return Icons.cancel;
      default: return Icons.help_outline;
    }
  }

  Color _etatColor(String label) {
    switch (label) {
      case 'OK': return Colors.green;
      case 'En panne': return Colors.orange;
      case 'HS': return Colors.red;
      default: return Colors.grey;
    }
  }

  Widget _etatCell(String? statutDbName) {
    final label = _deriveEtat(statutDbName);
    final color = _etatColor(label);
    return Row(
      children: [
        Icon(_etatIcon(label), color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Future<void> _ensureSallePaths(Set<String> ids) async {
    final missing = ids.where((id) => !_sallePath.containsKey(id)).toSet();
    if (missing.isEmpty) return;

    final idsCsv = _inCsv(missing);
    try {
      final salles = List<Map<String, dynamic>>.from(
        await _sb.from('salles').select('id, nom, batiment_id').filter('id','in', idsCsv) as List
      );
      for (final s in salles) {
        _salleName[s['id'] as String] = (s['nom'] as String?) ?? '—';
      }
      final batIds = salles.map((s)=> s['batiment_id'] as String?).whereType<String>().toSet();
      if (batIds.isEmpty) return;

      final batsCsv = _inCsv(batIds);
      final bats = List<Map<String, dynamic>>.from(
        await _sb.from('batiments').select('id, nom, site_id').filter('id','in', batsCsv) as List
      );
      final siteIds = bats.map((b)=> b['site_id'] as String?).whereType<String>().toSet();
      final sitesCsv = siteIds.isEmpty ? null : _inCsv(siteIds);
      final sites = siteIds.isEmpty ? <Map<String,dynamic>>[] :
        List<Map<String, dynamic>>.from(
          await _sb.from('sites').select('id, nom').filter('id','in', sitesCsv!) as List
        );

      final batById  = { for (final b in bats)  b['id'] as String : b };
      final siteById = { for (final s in sites) s['id'] as String : s };

      for (final s in salles) {
        final b = batById[s['batiment_id']];
        final siteName = (b != null && siteById[b['site_id']] != null)
          ? (siteById[b['site_id']]?['nom'] as String? ?? '—') : '—';
        final batName  = b != null ? (b['nom'] as String? ?? '—') : '—';
        final salName  = (s['nom'] as String?) ?? '—';
        _sallePath[s['id'] as String] = '$siteName / $batName / $salName';
      }
      if (mounted) setState(() {});
    } catch (_) {/* silencieux */}
  }

  static Widget _buildText(TextEditingController c, String label, IconData icon, {bool required = false}) {
    return TextFormField(
      controller: c,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), border: const OutlineInputBorder()),
      validator: (v) => (!required) ? null : (v==null || v.trim().isEmpty ? 'Champ requis' : null),
    );
  }

  static Widget _buildDateField({required String label, required DateTime? value, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.event), border: const OutlineInputBorder()),
        child: Text(value == null ? '—' : '${value.year}-${_2(value.month)}-${_2(value.day)}'),
      ),
    );
  }

  void _showDetails(Map<String, dynamic> e) {
    final statutFin = _etatNameById(e['etat_id'] as String?) ?? '—';
    final sallePath = (e['salle_id'] != null) ? (_sallePath[e['salle_id']] ?? _salleName[e['salle_id']] ?? '—') : '—';
    showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: const Text('Détails équipement'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('N° série', e['numero_serie']),
              _kv('Modèle', e['modele']),
              _kv('Marque', e['marque']),
              _kv('Type', e['type']),
              _kv('État', _deriveEtat(statutFin)),
              _kv('Statut', statutFin),
              _kv('Emplacement', sallePath),
              _kv('Host name', e['host_name']),
              _kv('Système d’exploitation', e['systeme_exploitation']),
              _kv('Attribué à', e['attribue_a']),
              _kv('Date achat', _fmtDateOnly(e['date_achat'])),
              _kv('Date assignation', _fmtDateOnly(e['date_assignation'])),
              const Divider(),
              _kv('Créé le', _fmtTs(e['created_at'])),
              _kv('Dernière modif', _fmtTs(e['updated_at'])),
              _kv('Ajouté par', e['created_by_email']),
              _kv('Modifié par', e['updated_by_email']),
            ],
          ),
        ),
        actions: [TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Fermer'))],
      );
    });
  }

  static Widget _kv(String k, dynamic v) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      SizedBox(width: 150, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
      Expanded(child: Text(v?.toString() ?? '—')),
    ]),
  );

  static DateTime? _tryParseUserDate(String q) {
    String s = q.trim();
    final re = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$');
    final m = re.firstMatch(s);
    if (m != null) {
      s = '${m.group(3)}-${m.group(2)!.padLeft(2,'0')}-${m.group(1)!.padLeft(2,'0')}';
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
    return a.year==b.year && a.month==b.month && a.day==b.day;
  }

  static String _fmtDateOnly(dynamic ts) {
    final d = _parseTs(ts); if (d==null) return '—';
    return '${d.year}-${_2(d.month)}-${_2(d.day)}';
  }

  static String _fmtTs(dynamic ts) {
    final d = _parseTs(ts); if (d==null) return '—';
    return '${d.year}-${_2(d.month)}-${_2(d.day)} ${_2(d.hour)}:${_2(d.minute)}';
  }

  static DateTime? _parseTs(dynamic ts) {
    if (ts==null) return null;
    try { return DateTime.parse(ts.toString()).toLocal(); } catch(_) { return null; }
  }
  static String _2(int x) => x.toString().padLeft(2, '0');

  static String _inCsv(Iterable<String> ids) => '(${ids.map((e)=> '"$e"').join(',')})';

  Future<List<Map<String, dynamic>>> _sites() async =>
    List<Map<String, dynamic>>.from(await _sb.from('sites').select('id, nom').order('nom') as List);
  Future<List<Map<String, dynamic>>> _bats(String sId) async =>
    List<Map<String, dynamic>>.from(await _sb.from('batiments').select('id, nom').eq('site_id', sId).order('nom') as List);
  Future<List<Map<String, dynamic>>> _salles(String bId) async =>
    List<Map<String, dynamic>>.from(await _sb.from('salles').select('id, nom').eq('batiment_id', bId).order('nom') as List);
}
