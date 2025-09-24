import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/supabase_client.dart';
import 'package:gepi/pages/pdf_exporter.dart'; // <- export PDF

class InterventionsPage extends StatefulWidget {
  const InterventionsPage({super.key});
  @override
  State<InterventionsPage> createState() => _InterventionsPageState();
}

class _InterventionsPageState extends State<InterventionsPage>
    with SingleTickerProviderStateMixin {
  final _sb = SB.client;

  late final TabController _tab;

  String? _role;
  bool _loadingRole = true;
  bool get _canWrite => _role == 'technicien' || _role == 'super-admin';

  final _searchCtrl = TextEditingController();
  final _histSearchCtrl = TextEditingController();

  // caches
  final Map<String, Map<String, dynamic>> _equipCache = {}; // equip_id -> equip
  final Map<String, String> _etatNameById = {};
  final Map<String, String> _salleName = {};
  final Map<String, String> _sallePath = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadRole();
    _warmEtats();
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    _histSearchCtrl.dispose();
    super.dispose();
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

  Future<void> _warmEtats() async {
    try {
      final res = await _sb.from('etats').select('id, nom');
      for (final m in List<Map<String, dynamic>>.from(res as List)) {
        _etatNameById[m['id'] as String] = (m['nom'] as String?) ?? '—';
      }
    } catch (_) {}
  }

  // =================== EXPORTS PDF ===================

  Future<void> _exportListe(List<Map<String, dynamic>> rows) async {
    final headers = ['Date','Équipement','Statut','Pièces remplacées','Technicien'];
    final data = rows.map((r) {
      final e = _equipCache[r['equipement_id']];
      final equipLabel = (e == null)
          ? '—'
          : '${e['numero_serie'] ?? ''} • ${e['host_name'] ?? ''} • ${e['marque'] ?? ''}'.trim();
      return [
        _fmtTs(r['date_creation']),
        equipLabel.isEmpty ? '—' : equipLabel,
        (r['statut'] ?? '—').toString(),
        (r['nbre_piece_remplacee'] ?? 0).toString(),
        (r['created_by_email'] ?? '—').toString(),
      ];
    }).toList();

    await PdfExporter.exportDataTable(
      title: 'Interventions',
      subtitle: 'Export du tableau — onglet Liste',
      headers: headers,
      rows: data,
      landscape: true,
    );
  }

  Future<void> _exportHistorique(List<Map<String, dynamic>> rows) async {
    final headers = ['Date','Action','Équipement','Champs modifiés','Technicien'];
    final data = rows.map((r) {
      final e = _equipCache[r['equipement_id']];
      final equipLabel = (e == null)
          ? '—'
          : '${e['numero_serie'] ?? ''} • ${e['host_name'] ?? ''} • ${e['marque'] ?? ''}'.trim();
      return [
        _fmtTs(r['created_at']),
        (r['action'] ?? '—').toString(),
        equipLabel.isEmpty ? '—' : equipLabel,
        _changedFieldsLabel(r['old_data'], r['new_data']),
        (r['changed_by_email'] ?? '—').toString(),
      ];
    }).toList();

    await PdfExporter.exportDataTable(
      title: 'Historique des interventions',
      subtitle: 'Export du tableau — onglet Historique',
      headers: headers,
      rows: data,
      landscape: true,
    );
  }

  // ============== LISTE ==============

  Widget _buildListe() {
    final stream = _sb
        .from('interventions')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    return Column(
      children: [
        if (_loadingRole) const LinearProgressIndicator(minHeight: 2),
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
                    hintText: 'Rechercher',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () { _searchCtrl.clear(); setState(() {}); },
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              ElevatedButton.icon(
                onPressed: !_canWrite ? null : () async {
                  final equip = await _pickEquipForIntervention(context);
                  if (equip != null) _showAddDialog(equip);
                },
                icon: const Icon(Icons.add),
                label: const Text('Nouvelle intervention'),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: stream,
            builder: (_, snap) {
              if (snap.hasError) return Center(child: Text('Erreur: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());

              final all = snap.data!;
              _ensureEquipCache(all.map((r) => r['equipement_id'] as String?).whereType<String>().toSet());

              final q = _searchCtrl.text.trim();
              final rows = all.where((r) => _rowMatches(r, q)).toList();
              if (rows.isEmpty) return const Center(child: Text('Aucune intervention.'));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left:16,right:16,bottom:6),
                    child: Row(
                      children: [
                        Chip(label: Text('${rows.length} résultat${rows.length>1?'s':''}')),
                        const Spacer(),
                        Tooltip(
                          message: 'Télécharger en PDF',
                          child: IconButton(
                            icon: const Icon(Icons.download),
                            onPressed: () => _exportListe(rows),
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
                              DataColumn(label: Text(' ')),
                              DataColumn(label: Text('Date')),
                              DataColumn(label: Text('Équipement')),
                              DataColumn(label: Text('Statut')),
                              DataColumn(label: Text('Pièces remplacées')),
                              DataColumn(label: Text('Technicien')),
                              DataColumn(label: Text('Actions')),
                            ],
                            rows: rows.map((r) {
                              final e = _equipCache[r['equipement_id']];
                              final equipLabel = (e == null)
                                  ? '—'
                                  : '${e['numero_serie'] ?? ''} • ${e['host_name'] ?? ''} • ${e['marque'] ?? ''}'.trim();
                              return DataRow(cells: [
                                DataCell(IconButton(
                                  icon: const Icon(Icons.info_outline),
                                  onPressed: () => _showIntervDetails(r, e),
                                )),
                                DataCell(Text(_fmtTs(r['date_creation']))),
                                DataCell(Text(equipLabel.isEmpty ? '—' : equipLabel)),
                                DataCell(Text((r['statut'] ?? '—').toString())),
                                DataCell(Text((r['nbre_piece_remplacee'] ?? 0).toString())),
                                DataCell(Text(r['created_by_email'] ?? '—')),
                                DataCell(Row(children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    tooltip: _canWrite ? 'Modifier' : 'Lecture seule',
                                    onPressed: !_canWrite ? null : () => _showEditDialog(r, e),
                                  ),
                                ])),
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

  // choix d’un équipement rapide
  Future<Map<String, dynamic>?> _pickEquipForIntervention(BuildContext ctx) async {
    final res = await _sb
        .from('equipements')
        .select('id, numero_serie, modele, marque, host_name, etat_id')
        .order('updated_at', ascending: false);

    final list = List<Map<String, dynamic>>.from(res as List);

    return showDialog<Map<String, dynamic>>(
      context: ctx,
      builder: (_) {
        String q = '';
        List<Map<String, dynamic>> filtered = list;
        void doFilter(String s) {
          q = s.trim().toLowerCase();
          filtered = list.where((e) {
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
                      title: Text('${e['numero_serie'] ?? '—'} • ${e['host_name'] ?? '—'}'),
                      subtitle: Text('${e['marque'] ?? '—'}  ${e['modele'] ?? ''}'),
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

  // ajout
  Future<void> _showAddDialog(Map<String, dynamic> equip) async {
    final formKey = GlobalKey<FormState>();
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
            context: ctx, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 1), initialDate: dateFin ?? now,
          );
          if (p != null) setState(() => dateFin = p);
        }

        return AlertDialog(
          title: const Text('Nouvelle intervention'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Équipement : ${equip['numero_serie'] ?? '—'} • ${equip['host_name'] ?? '—'} • ${equip['marque'] ?? '—'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Intervenant (déduit) : $intervenant', style: const TextStyle(color: Colors.black54)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Statut', border: OutlineInputBorder()),
                  value: statut,
                  items: const ['en cours', 'terminée', 'en attente pièces', 'annulée']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => statut = v ?? 'en cours',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: piecesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de pièces remplacées',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.swap_horiz),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) => (v == null || int.tryParse(v) == null) ? 'Entier requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Description ',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: pickFin,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date fin (optionnel)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.event)),
                    child: Text(dateFin == null ? '—' : _fmtDateOnly(dateFin!.toIso8601String())),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: !_canWrite ? null : () async {
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
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Intervention ajoutée')));
                  }
                } on PostgrestException catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
  }

  // édition
  Future<void> _showEditDialog(Map<String, dynamic> r, Map<String, dynamic>? e) async {
    final formKey = GlobalKey<FormState>();
    final descCtrl = TextEditingController(text: r['description'] ?? '');
    final piecesCtrl = TextEditingController(text: (r['nbre_piece_remplacee'] ?? 0).toString());
    String statut = (r['statut'] ?? 'en cours').toString();
    DateTime? dateFin = _parseTs(r['date_fin']);
    await showDialog(
      context: context,
      builder: (ctx) {
        Future<void> pickFin() async {
          final now = DateTime.now();
          final p = await showDatePicker(
            context: ctx, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 1),
            initialDate: dateFin ?? now,
          );
          if (p != null) setState(() => dateFin = p);
        }

        return AlertDialog(
          title: const Text('Modifier l’intervention'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    e == null ? 'Équipement: —'
                      : 'Équipement : ${e['numero_serie'] ?? '—'} • ${e['host_name'] ?? '—'} • ${e['marque'] ?? '—'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Statut', border: OutlineInputBorder()),
                  value: statut,
                  items: const ['en cours', 'terminée', 'en attente pièces', 'annulée']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => statut = v ?? statut,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: piecesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de pièces remplacées',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.swap_horiz),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) => (v == null || int.tryParse(v) == null) ? 'Entier requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: pickFin,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date fin ', border: OutlineInputBorder(), prefixIcon: Icon(Icons.event)),
                    child: Text(dateFin == null ? '—' : _fmtDateOnly(dateFin!.toIso8601String())),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: !_canWrite ? null : () async {
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
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Intervention modifiée')));
                  }
                } on PostgrestException catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
  }

  // détails intervention
  void _showIntervDetails(Map<String, dynamic> r, Map<String, dynamic>? e) {
    showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: const Text('Détails intervention'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _kv('Date', _fmtTs(r['date_creation'])),
            _kv('Statut', r['statut']),
            _kv('Pièces remplacées', r['nbre_piece_remplacee']),
            _kv('Description', r['description']),
            const Divider(),
            _kv('Créée par', r['created_by_email']),
            _kv('Modifiée par', r['updated_by_email']),
            if (e != null) ...[
              const Divider(),
              _kv('Équipement', '${e['numero_serie'] ?? '—'} • ${e['modele'] ?? '—'} • ${e['marque'] ?? '—'}'),
            ],
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
      );
    });
  }

  // ============== HISTORIQUE ==============

  Widget _buildHistorique() {
    final stream = _sb
        .from('interventions_hist')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _histSearchCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Rechercher',
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
            stream: stream,
            builder: (_, snap) {
              if (snap.hasError) {
                final msg = snap.error.toString();
                final friendly = msg.contains('PGRST205')
                    ? "Historique indisponible. "
                    : msg;
                return Center(child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text('Erreur: $friendly'),
                ));
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());

              final all = snap.data!;
              _ensureEquipCache(all.map((r) => r['equipement_id'] as String?).whereType<String>().toSet());

              final q = _histSearchCtrl.text.trim();
              final rows = all.where((r) => _histRowMatches(r, q)).toList();
              if (rows.isEmpty) return const Center(child: Text('Aucun événement.'));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left:16,right:16,bottom:6),
                    child: Row(
                      children: [
                        Chip(label: Text('${rows.length} événement${rows.length>1?'s':''}')),
                        const Spacer(),
                        Tooltip(
                          message: 'Télécharger en PDF',
                          child: IconButton(
                            icon: const Icon(Icons.download),
                            onPressed: () => _exportHistorique(rows),
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
                              DataColumn(label: Text('Date')),
                              DataColumn(label: Text('Action')),
                              DataColumn(label: Text('Équipement')),
                              DataColumn(label: Text('Champs modifiés')),
                              DataColumn(label: Text('Technicien')),
                            ],
                            rows: rows.map((r) {
                              final e = _equipCache[r['equipement_id']];
                              final equipLabel = (e == null)
                                  ? '—'
                                  : '${e['numero_serie'] ?? ''} • ${e['host_name'] ?? ''} • ${e['marque'] ?? ''}'.trim();
                              final changed = _changedFieldsLabel(r['old_data'], r['new_data']);
                              return DataRow(cells: [
                                DataCell(Text(_fmtTs(r['created_at']))),
                                DataCell(Text((r['action'] ?? '—').toString())),
                                DataCell(Text(equipLabel.isEmpty ? '—' : equipLabel)),
                                DataCell(Text(changed.isEmpty ? '—' : changed)),
                                DataCell(Text(r['changed_by_email'] ?? '—')),
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

  // ============== helpers data ==============

  bool _rowMatches(Map<String, dynamic> r, String q) {
    if (q.trim().isEmpty) return true;
    final e = _equipCache[r['equipement_id']];
    final low = q.toLowerCase();

    final dt = _tryParseUserDate(low);
    if (dt != null) {
      bool sameDay(DateTime? d) => d != null && d.year == dt.year && d.month == dt.month && d.day == dt.day;
      if (sameDay(_parseTs(r['date_creation'])) || sameDay(_parseTs(r['updated_at'])) || sameDay(_parseTs(r['created_at']))) {
        return true;
      }
    }

    final fields = <String>[
      r['statut']?.toString() ?? '',
      r['description']?.toString() ?? '',
      r['created_by_email']?.toString() ?? '',
      r['updated_by_email']?.toString() ?? '',
      if (e != null) ...[
        e['host_name']?.toString() ?? '',
        e['numero_serie']?.toString() ?? '',
        e['modele']?.toString() ?? '',
        e['marque']?.toString() ?? '',
      ]
    ].map((s) => s.toLowerCase());

    return fields.any((s) => s.contains(low));
  }

  bool _histRowMatches(Map<String, dynamic> r, String q) {
    if (q.trim().isEmpty) return true;
    final e = _equipCache[r['equipement_id']];
    final low = q.toLowerCase();

    final dt = _tryParseUserDate(low);
    if (dt != null) {
      final d = _parseTs(r['created_at']);
      if (d != null && d.year == dt.year && d.month == dt.month && d.day == dt.day) return true;
    }

    final changed = _changedFieldsLabel(r['old_data'], r['new_data']);

    final fields = <String>[
      (r['action'] ?? '').toString(),
      (r['changed_by_email'] ?? '').toString(),
      changed,
      if (e != null) ...[
        (e['host_name'] ?? '').toString(),
        (e['numero_serie'] ?? '').toString(),
        (e['modele'] ?? '').toString(),
        (e['marque'] ?? '').toString(),
      ]
    ].map((s) => s.toLowerCase());

    return fields.any((s) => s.contains(low));
  }

  String _changedFieldsLabel(dynamic oldJ, dynamic newJ) {
    try {
      final oldMap = (oldJ == null) ? <String, dynamic>{} : Map<String, dynamic>.from(oldJ);
      final newMap = (newJ == null) ? <String, dynamic>{} : Map<String, dynamic>.from(newJ);
      final keys = <String>{...oldMap.keys, ...newMap.keys};
      final changed = <String>[];
      for (final k in keys) {
        final ov = oldMap[k]?.toString();
        final nv = newMap[k]?.toString();
        if (ov != nv) changed.add(k);
      }
      changed.removeWhere((k) => {
        'id','created_at','updated_at','created_by','created_by_email','updated_by','updated_by_email'
      }.contains(k));
      return changed.join(', ');
    } catch (_) {
      return '';
    }
  }

  Future<void> _ensureEquipCache(Set<String> ids) async {
    final missing = ids.where((id) => !_equipCache.containsKey(id)).toSet();
    if (missing.isEmpty) return;
    try {
      final list = List<Map<String, dynamic>>.from(
        await _sb.from('equipements')
            .select('id, host_name, numero_serie, modele, marque, etat_id, salle_id')
            .filter('id','in', _inCsv(missing)) as List
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

  // ============== helpers UI ==============

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
      s = '${m.group(3)}-${m.group(2)!.padLeft(2,'0')}-${m.group(1)!.padLeft(2,'0')}';
    }
    try {
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
        return DateTime.parse('$s 00:00:00');
      }
    } catch (_) {}
    return null;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TabBar(
            controller: _tab,
            tabs: const [Tab(text: 'Liste'), Tab(text: 'Historique')],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _buildListe(),
              _buildHistorique(),
            ],
          ),
        ),
      ],
    );
  }
}

/*import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/supabase_client.dart';

class InterventionsPage extends StatefulWidget {
  const InterventionsPage({super.key});
  @override
  State<InterventionsPage> createState() => _InterventionsPageState();
}

class _InterventionsPageState extends State<InterventionsPage>
    with SingleTickerProviderStateMixin {
  final _sb = SB.client;

  late final TabController _tab;

  String? _role;
  bool _loadingRole = true;
  bool get _canWrite => _role == 'technicien' || _role == 'super-admin';

  final _searchCtrl = TextEditingController();
  final _histSearchCtrl = TextEditingController();

  // caches
  final Map<String, Map<String, dynamic>> _equipCache = {}; // equip_id -> equip
  final Map<String, String> _etatNameById = {};
  final Map<String, String> _salleName = {};
  final Map<String, String> _sallePath = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadRole();
    _warmEtats();
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    _histSearchCtrl.dispose();
    super.dispose();
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

  Future<void> _warmEtats() async {
    try {
      final res = await _sb.from('etats').select('id, nom');
      for (final m in List<Map<String, dynamic>>.from(res as List)) {
        _etatNameById[m['id'] as String] = (m['nom'] as String?) ?? '—';
      }
    } catch (_) {}
  }

  // ============== LISTE ==============

  Widget _buildListe() {
    final stream = _sb
        .from('interventions')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    return Column(
      children: [
        if (_loadingRole) const LinearProgressIndicator(minHeight: 2),
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
                    hintText: 'Rechercher',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () { _searchCtrl.clear(); setState(() {}); },
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              ElevatedButton.icon(
                onPressed: !_canWrite ? null : () async {
                  // choix d’un équipement (dialogue) avant de créer l’intervention
                  final equip = await _pickEquipForIntervention(context);
                  if (equip != null) _showAddDialog(equip);
                },
                icon: const Icon(Icons.add),
                label: const Text('Nouvelle intervention'),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: stream,
            builder: (_, snap) {
              if (snap.hasError) return Center(child: Text('Erreur: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());

              final all = snap.data!;
              // préchauffer le cache équipements
              _ensureEquipCache(all.map((r) => r['equipement_id'] as String?).whereType<String>().toSet());

              final q = _searchCtrl.text.trim();
              final rows = all.where((r) => _rowMatches(r, q)).toList();
              if (rows.isEmpty) return const Center(child: Text('Aucune intervention.'));

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(8),
                decoration: _tableBox(),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text(' ')),
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Équipement')),
                      DataColumn(label: Text('Statut')),
                      DataColumn(label: Text('Pièces remplacées')),
                      DataColumn(label: Text('Technicien')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: rows.map((r) {
                      final e = _equipCache[r['equipement_id']];
                      final equipLabel = (e == null)
                          ? '—'
                          : '${e['numero_serie'] ?? ''} • ${e['host_name'] ?? ''} • ${e['marque'] ?? ''}'.trim();
                      return DataRow(cells: [
                        DataCell(IconButton(
                          icon: const Icon(Icons.info_outline),
                          onPressed: () => _showIntervDetails(r, e),
                        )),
                        DataCell(Text(_fmtTs(r['date_creation']))),
                        DataCell(Text(equipLabel.isEmpty ? '—' : equipLabel)),
                        DataCell(Text((r['statut'] ?? '—').toString())),
                        DataCell(Text((r['nbre_piece_remplacee'] ?? 0).toString())),
                        DataCell(Text(r['created_by_email'] ?? '—')),
                        DataCell(Row(children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            tooltip: _canWrite ? 'Modifier' : 'Lecture seule',
                            onPressed: !_canWrite ? null : () => _showEditDialog(r, e),
                          ),
                        ])),
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

  // choix d’un équipement rapide
  Future<Map<String, dynamic>?> _pickEquipForIntervention(BuildContext ctx) async {
    final res = await _sb
        .from('equipements')
        .select('id, numero_serie, modele, marque, host_name, etat_id')
        .order('updated_at', ascending: false);

    final list = List<Map<String, dynamic>>.from(res as List);

    // seulement ceux "en maintenance" si tu veux filtrer ici : à toi d’ajuster
    return showDialog<Map<String, dynamic>>(
      context: ctx,
      builder: (_) {
        String q = '';
        List<Map<String, dynamic>> filtered = list;
        void doFilter(String s) {
          q = s.trim().toLowerCase();
          filtered = list.where((e) {
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
                      title: Text('${e['numero_serie'] ?? '—'} • ${e['host_name'] ?? '—'}'),
                      subtitle: Text('${e['marque'] ?? '—'}  ${e['modele'] ?? ''}'),
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

  // ajout
  Future<void> _showAddDialog(Map<String, dynamic> equip) async {
    final formKey = GlobalKey<FormState>();
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
            context: ctx, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 1), initialDate: dateFin ?? now,
          );
          if (p != null) setState(() => dateFin = p);
        }

        return AlertDialog(
          title: const Text('Nouvelle intervention'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Équipement : ${equip['numero_serie'] ?? '—'} • ${equip['host_name'] ?? '—'} • ${equip['marque'] ?? '—'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Intervenant (déduit) : $intervenant', style: const TextStyle(color: Colors.black54)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Statut', border: OutlineInputBorder()),
                  value: statut,
                  items: const ['en cours', 'terminée', 'en attente pièces', 'annulée']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => statut = v ?? 'en cours',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: piecesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de pièces remplacées',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.swap_horiz),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) => (v == null || int.tryParse(v) == null) ? 'Entier requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Description ',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: pickFin,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date fin (optionnel)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.event)),
                    child: Text(dateFin == null ? '—' : _fmtDateOnly(dateFin!.toIso8601String())),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: !_canWrite ? null : () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final payload = {
                  'equipement_id': equip['id'],
                  'statut': statut,
                  'nbre_piece_remplacee': int.parse(piecesCtrl.text.trim()),
                  'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                  'date_fin': dateFin?.toIso8601String(),
                  // created_by / created_by_email / utilisateur_id sont mis par trigger
                };
                try {
                  await _sb.from('interventions').insert(payload);
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Intervention ajoutée')));
                  }
                } on PostgrestException catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
  }

  // édition
  Future<void> _showEditDialog(Map<String, dynamic> r, Map<String, dynamic>? e) async {
    final formKey = GlobalKey<FormState>();
    final descCtrl = TextEditingController(text: r['description'] ?? '');
    final piecesCtrl = TextEditingController(text: (r['nbre_piece_remplacee'] ?? 0).toString());
    String statut = (r['statut'] ?? 'en cours').toString();
    DateTime? dateFin = _parseTs(r['date_fin']);
    await showDialog(
      context: context,
      builder: (ctx) {
        Future<void> pickFin() async {
          final now = DateTime.now();
          final p = await showDatePicker(
            context: ctx, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 1),
            initialDate: dateFin ?? now,
          );
          if (p != null) setState(() => dateFin = p);
        }

        return AlertDialog(
          title: const Text('Modifier l’intervention'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    e == null ? 'Équipement: —'
                      : 'Équipement : ${e['numero_serie'] ?? '—'} • ${e['host_name'] ?? '—'} • ${e['marque'] ?? '—'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Statut', border: OutlineInputBorder()),
                  value: statut,
                  items: const ['en cours', 'terminée', 'en attente pièces', 'annulée']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => statut = v ?? statut,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: piecesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de pièces remplacées',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.swap_horiz),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) => (v == null || int.tryParse(v) == null) ? 'Entier requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: pickFin,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date fin ', border: OutlineInputBorder(), prefixIcon: Icon(Icons.event)),
                    child: Text(dateFin == null ? '—' : _fmtDateOnly(dateFin!.toIso8601String())),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: !_canWrite ? null : () async {
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
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Intervention modifiée')));
                  }
                } on PostgrestException catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
  }

  // détails intervention
  void _showIntervDetails(Map<String, dynamic> r, Map<String, dynamic>? e) {
    showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: const Text('Détails intervention'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _kv('Date', _fmtTs(r['date_creation'])),
            _kv('Statut', r['statut']),
            _kv('Pièces remplacées', r['nbre_piece_remplacee']),
            _kv('Description', r['description']),
            const Divider(),
            _kv('Créée par', r['created_by_email']),
            _kv('Modifiée par', r['updated_by_email']),
            if (e != null) ...[
              const Divider(),
              _kv('Équipement', '${e['numero_serie'] ?? '—'} • ${e['modele'] ?? '—'} • ${e['marque'] ?? '—'}'),
            ],
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
      );
    });
  }

  // ============== HISTORIQUE ==============

  Widget _buildHistorique() {
    final stream = _sb
        .from('interventions_hist')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _histSearchCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Rechercher',
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
            stream: stream,
            builder: (_, snap) {
              if (snap.hasError) {
                final msg = snap.error.toString();
                final friendly = msg.contains('PGRST205')
                    ? "Historique indisponible. "
                    : msg;
                return Center(child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text('Erreur: $friendly'),
                ));
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());

              final all = snap.data!;
              // précharger équipements pour affichage
              _ensureEquipCache(all.map((r) => r['equipement_id'] as String?).whereType<String>().toSet());

              final q = _histSearchCtrl.text.trim();
              final rows = all.where((r) => _histRowMatches(r, q)).toList();
              if (rows.isEmpty) return const Center(child: Text('Aucun événement.'));

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(8),
                decoration: _tableBox(),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Action')),
                      DataColumn(label: Text('Équipement')),
                      DataColumn(label: Text('Champs modifiés')),
                      DataColumn(label: Text('Technicien')),
                    ],
                    rows: rows.map((r) {
                      final e = _equipCache[r['equipement_id']];
                      final equipLabel = (e == null)
                          ? '—'
                          : '${e['numero_serie'] ?? ''} • ${e['host_name'] ?? ''} • ${e['marque'] ?? ''}'.trim();
                      final changed = _changedFieldsLabel(r['old_data'], r['new_data']);
                      return DataRow(cells: [
                        DataCell(Text(_fmtTs(r['created_at']))),
                        DataCell(Text((r['action'] ?? '—').toString())),
                        DataCell(Text(equipLabel.isEmpty ? '—' : equipLabel)),
                        DataCell(Text(changed.isEmpty ? '—' : changed)),
                        DataCell(Text(r['changed_by_email'] ?? '—')),
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

  // ============== helpers data ==============

  bool _rowMatches(Map<String, dynamic> r, String q) {
    if (q.trim().isEmpty) return true;
    final e = _equipCache[r['equipement_id']];
    final low = q.toLowerCase();

    // date (yyyy-mm-dd ou dd/mm/yyyy)
    final dt = _tryParseUserDate(low);
    if (dt != null) {
      bool sameDay(DateTime? d) => d != null && d.year == dt.year && d.month == dt.month && d.day == dt.day;
      if (sameDay(_parseTs(r['date_creation'])) || sameDay(_parseTs(r['updated_at'])) || sameDay(_parseTs(r['created_at']))) {
        return true;
      }
    }

    final fields = <String>[
      r['statut']?.toString() ?? '',
      r['description']?.toString() ?? '',
      r['created_by_email']?.toString() ?? '',
      r['updated_by_email']?.toString() ?? '',
      if (e != null) ...[
        e['host_name']?.toString() ?? '',
        e['numero_serie']?.toString() ?? '',
        e['modele']?.toString() ?? '',
        e['marque']?.toString() ?? '',
      ]
    ].map((s) => s.toLowerCase());

    return fields.any((s) => s.contains(low));
  }

  bool _histRowMatches(Map<String, dynamic> r, String q) {
    if (q.trim().isEmpty) return true;
    final e = _equipCache[r['equipement_id']];
    final low = q.toLowerCase();

    final dt = _tryParseUserDate(low);
    if (dt != null) {
      final d = _parseTs(r['created_at']);
      if (d != null && d.year == dt.year && d.month == dt.month && d.day == dt.day) return true;
    }

    final changed = _changedFieldsLabel(r['old_data'], r['new_data']);

    final fields = <String>[
      (r['action'] ?? '').toString(),
      (r['changed_by_email'] ?? '').toString(),
      changed,
      if (e != null) ...[
        (e['host_name'] ?? '').toString(),
        (e['numero_serie'] ?? '').toString(),
        (e['modele'] ?? '').toString(),
        (e['marque'] ?? '').toString(),
      ]
    ].map((s) => s.toLowerCase());

    return fields.any((s) => s.contains(low));
  }

  String _changedFieldsLabel(dynamic oldJ, dynamic newJ) {
    try {
      final oldMap = (oldJ == null) ? <String, dynamic>{} : Map<String, dynamic>.from(oldJ);
      final newMap = (newJ == null) ? <String, dynamic>{} : Map<String, dynamic>.from(newJ);
      final keys = <String>{...oldMap.keys, ...newMap.keys};
      final changed = <String>[];
      for (final k in keys) {
        final ov = oldMap[k]?.toString();
        final nv = newMap[k]?.toString();
        if (ov != nv) changed.add(k);
      }
      // on masque les champs techniques
      changed.removeWhere((k) => {
        'id','created_at','updated_at','created_by','created_by_email','updated_by','updated_by_email'
      }.contains(k));
      return changed.join(', ');
    } catch (_) {
      return '';
    }
  }

  Future<void> _ensureEquipCache(Set<String> ids) async {
    final missing = ids.where((id) => !_equipCache.containsKey(id)).toSet();
    if (missing.isEmpty) return;
    try {
      final list = List<Map<String, dynamic>>.from(
        await _sb.from('equipements')
            .select('id, host_name, numero_serie, modele, marque, etat_id, salle_id')
            .filter('id','in', _inCsv(missing)) as List
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

  // ============== helpers UI ==============

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
      s = '${m.group(3)}-${m.group(2)!.padLeft(2,'0')}-${m.group(1)!.padLeft(2,'0')}';
    }
    try {
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
        return DateTime.parse('$s 00:00:00');
      }
    } catch (_) {}
    return null;
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

  /*@override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: TabBar(tabs: [Tab(text: 'Liste'), Tab(text: 'Historique')]),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _buildListe(),
              _buildHistorique(),
            ],
          ),
        ),
      ],
    );
  }*/
  @override
Widget build(BuildContext context) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TabBar(
          controller: _tab, 
          tabs: const [Tab(text: 'Liste'), Tab(text: 'Historique')],
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _tab,
          children: [
            _buildListe(),
            _buildHistorique(),
          ],
        ),
      ),
    ],
  );
}

  
}*/
