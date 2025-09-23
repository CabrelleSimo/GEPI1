import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/supabase_client.dart';

class GestionAccesPage extends StatefulWidget {
  const GestionAccesPage({super.key});
  @override
  State<GestionAccesPage> createState() => _GestionAccesPageState();
}

class _GestionAccesPageState extends State<GestionAccesPage> {
  final _sb = SB.client;

  // rôle courant
  String? _role;
  bool _loadingRole = true;
  bool get _isSuperAdmin => _role == 'super-admin';

  // recherche
  final _searchCtrl = TextEditingController();

  // rôles connus
  final Set<String> _knownRoles = {'visiteur', 'technicien', 'super-admin'};

  // nom de la fonction edge
  static const String _fnName = 'admin-create-user';

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
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

  // ==================== Appels Edge Function ====================

  /// Appelle l’Edge Function et renvoie le JSON (Map). Lève une Exception si erreur.
  Future<Map<String, dynamic>> _callAdminFn(Map<String, dynamic> payload) async {
    // Supabase Flutter ajoute automatiquement le header Authorization: Bearer <access_token>
    final resp = await _sb.functions.invoke(_fnName, body: payload);

    // resp.data peut être déjà un Map, ou une String JSON selon versions
    Map<String, dynamic> obj;
    if (resp.data == null) {
      obj = {};
    } else if (resp.data is Map) {
      obj = Map<String, dynamic>.from(resp.data as Map);
    } else if (resp.data is String) {
      obj = jsonDecode(resp.data as String) as Map<String, dynamic>;
    } else {
      obj = jsonDecode(jsonEncode(resp.data)) as Map<String, dynamic>;
    }

    // Certaines versions ne remontent pas resp.error; on vérifie champs connus
    final hasError = (obj['error'] != null) || (resp.status >= 400);
    if (hasError) {
      final msg = (obj['error']?.toString().isNotEmpty == true)
          ? obj['error'].toString()
          : 'Erreur ${resp.status}';
      throw Exception(msg);
    }
    return obj;
  }

  Future<void> _createUser(String email, String password, String role) async {
    await _callAdminFn({
      'action': 'create',
      'email': email,
      'password': password,
      'role': role,
    });
  }

  Future<void> _updateUser(String userId, {String? password, String? role}) async {
    final payload = <String, dynamic>{'action': 'update', 'userId': userId};
    if (password != null && password.trim().isNotEmpty) payload['password'] = password;
    if (role != null && role.trim().isNotEmpty) payload['role'] = role;
    await _callAdminFn(payload);
  }

  Future<void> _deleteUser(String userId) async {
    await _callAdminFn({'action': 'delete', 'userId': userId});
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    if (_loadingRole) return const Center(child: CircularProgressIndicator());
    if (!_isSuperAdmin) {
      return const Center(
        child: Text(
          "Accès réservé au Super-Admin",
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
        ),
      );
    }

    // Flux temps réel sur la table applicative "users"
    final stream = _sb
        .from('users')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 420,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Rechercher (email, rôle, date...)',
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
                onPressed: _showAddDialog,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Ajouter un utilisateur'),
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
              final q = _searchCtrl.text.trim();
              final rows = all.where((m) => _rowMatches(m, q)).toList();
              if (rows.isEmpty) return const Center(child: Text('Aucun utilisateur.'));

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(8),
                decoration: _tableBox(),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Email')),
                      DataColumn(label: Text('Rôle')),
                      DataColumn(label: Text('Créé le')),
                      DataColumn(label: Text('Modifié le')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: rows.map((u) {
                      return DataRow(cells: [
                        DataCell(Text(u['email'] ?? '—')),
                        DataCell(_roleChip(u['role'])),
                        DataCell(Text(_fmtTs(u['created_at']))),
                        DataCell(Text(_fmtTs(u['updated_at']))),
                        DataCell(Row(children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            tooltip: 'Modifier rôle / mot de passe',
                            onPressed: () => _showEditDialog(u),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Supprimer',
                            onPressed: () => _confirmDelete(u),
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

  // ==================== Dialogs ====================

  Future<void> _showAddDialog() async {
    final formKey = GlobalKey<FormState>();
    final emailCtrl = TextEditingController();
    final pwdCtrl   = TextEditingController();
    String role     = 'visiteur';

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Ajouter un utilisateur'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (v) =>
                      (v == null || v.trim().isEmpty || !v.contains('@'))
                        ? 'Email valide requis' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: pwdCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mot de passe',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.password_outlined),
                    ),
                    validator: (v) =>
                      (v == null || v.length < 6) ? '6 caractères minimum' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: const InputDecoration(
                      labelText: 'Rôle',
                      border: OutlineInputBorder(),
                    ),
                    items: _knownRoles
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (v) => role = v ?? 'visiteur',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              child: const Text('Créer'),
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                try {
                  await _createUser(emailCtrl.text.trim(), pwdCtrl.text, role);
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Utilisateur créé.')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
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

  Future<void> _showEditDialog(Map<String, dynamic> userRow) async {
    final formKey = GlobalKey<FormState>();
    final pwdCtrl  = TextEditingController();
    String role    = (userRow['role'] as String?) ?? 'visiteur';
    final bool isSelf = _sb.auth.currentUser?.id == userRow['id'];

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Modifier ${userRow['email'] ?? ''}'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: const InputDecoration(
                    labelText: 'Rôle',
                    border: OutlineInputBorder(),
                  ),
                  items: _knownRoles
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (isSelf && role == 'super-admin')
                      ? null // éviter de se destituer soi-même
                      : (v) => role = v ?? role,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: pwdCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Nouveau mot de passe (optionnel)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.password_outlined),
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
                try {
                  await _updateUser(
                    userRow['id'] as String,
                    password: pwdCtrl.text.trim().isEmpty ? null : pwdCtrl.text,
                    role: role,
                  );
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Modifications enregistrées.')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
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

  Future<void> _confirmDelete(Map<String, dynamic> userRow) async {
    final bool isSelf = _sb.auth.currentUser?.id == userRow['id'];
    if (isSelf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible de supprimer votre propre compte."), backgroundColor: Colors.red),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer l’utilisateur ?'),
        content: Text('Cette action supprimera aussi son compte Auth.\n\n${userRow['email'] ?? ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _deleteUser(userRow['id'] as String);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Utilisateur supprimé.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ==================== Helpers ====================

  bool _rowMatches(Map<String, dynamic> r, String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return true;

    // date (yyyy-mm-dd)
    try {
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
        final d = DateTime.parse('$s 00:00:00');
        bool sameDay(DateTime? x) =>
            x != null && x.year == d.year && x.month == d.month && x.day == d.day;
        if (sameDay(_parseTs(r['created_at'])) || sameDay(_parseTs(r['updated_at']))) {
          return true;
        }
      }
    } catch (_) {}

    final texts = <String>[
      r['email']?.toString() ?? '',
      r['role']?.toString() ?? '',
    ].map((e) => e.toLowerCase());

    return texts.any((e) => e.contains(s));
  }

  static Widget _roleChip(String? role) {
    final r = (role ?? '—').toLowerCase();
    Color c;
    switch (r) {
      case 'super-admin': c = Colors.red.shade400; break;
      case 'technicien':  c = Colors.blue.shade400; break;
      default:            c = Colors.grey.shade500; break;
    }
    return Chip(
      label: Text(r),
      backgroundColor: c.withOpacity(0.12),
      labelStyle: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w600),
      side: BorderSide(color: c.withOpacity(0.4)),
      visualDensity: VisualDensity.compact,
    );
  }

  static BoxDecoration _tableBox() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0,3))],
  );

  static String _fmtTs(dynamic ts) {
    final d = _parseTs(ts); if (d == null) return '—';
    String _2(int x) => x.toString().padLeft(2, '0');
    return '${d.year}-${_2(d.month)}-${_2(d.day)} ${_2(d.hour)}:${_2(d.minute)}';
  }

  static DateTime? _parseTs(dynamic ts) {
    if (ts == null) return null;
    try { return DateTime.parse(ts.toString()).toLocal(); } catch (_) { return null; }
  }
}
