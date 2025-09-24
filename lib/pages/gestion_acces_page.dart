/*import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/supabase_client.dart';

class GestionAccesPage extends StatefulWidget {
  const GestionAccesPage({super.key});
  @override
  State<GestionAccesPage> createState() => _GestionAccesPageState();
}

class _GestionAccesPageState extends State<GestionAccesPage>
    with SingleTickerProviderStateMixin {
  final _sb = SB.client;

  // rôle courant
  String? _role;
  bool _loadingRole = true;
  bool get _isSuperAdmin => _role == 'super-admin';

  // recherche
  final _searchCtrl = TextEditingController();
  final _invSearchCtrl = TextEditingController();

  // rôles connus
  static const Set<String> _knownRoles = {
    'visiteur',
    'technicien',
    'super-admin',
  };

  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadRole();
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    _invSearchCtrl.dispose();
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
            final r = await _sb
                .from('users')
                .select('role')
                .eq('id', u.id)
                .maybeSingle();
            final dbRole = r?['role'] as String?;
            if (dbRole != null && dbRole.isNotEmpty) {
              role = dbRole;
              break;
            }
          } catch (_) {}
        }
      }
      setState(() => _role = role ?? 'visiteur');
    } finally {
      if (mounted) setState(() => _loadingRole = false);
    }
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TabBar(
            controller: _tab,
            tabs: const [
              Tab(text: 'Utilisateurs'),
              Tab(text: 'Invitations'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _buildUsersTab(),
              _buildInvitesTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== Onglet UTILISATEURS ====================

  Widget _buildUsersTab() {
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
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {});
                      },
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              // plus de “Créer utilisateur” ici — on passe par “Invitations”
            ],
          ),
        ),
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

              final all = snap.data!;
              final q = _searchCtrl.text.trim().toLowerCase();

              bool rowMatches(Map<String, dynamic> r) {
                if (q.isEmpty) return true;

                // date (yyyy-mm-dd)
                try {
                  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(q)) {
                    final d = DateTime.parse('$q 00:00:00');
                    bool sameDay(DateTime? x) =>
                        x != null &&
                        x.year == d.year &&
                        x.month == d.month &&
                        x.day == d.day;
                    if (sameDay(_parseTs(r['created_at'])) ||
                        sameDay(_parseTs(r['updated_at']))) {
                      return true;
                    }
                  }
                } catch (_) {}

                final texts = <String>[
                  r['email']?.toString() ?? '',
                  r['role']?.toString() ?? '',
                ].map((e) => e.toLowerCase());

                return texts.any((e) => e.contains(q));
              }

              final rows = all.where(rowMatches).toList();
              if (rows.isEmpty) {
                return const Center(child: Text('Aucun utilisateur.'));
              }

              return Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                            tooltip: 'Changer le rôle',
                            onPressed: () => _showRoleDialog(u),
                          ),
                          // Note: pas de suppression compte Auth ni reset mot de passe ici
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

  Future<void> _showRoleDialog(Map<String, dynamic> userRow) async {
    String role = (userRow['role'] as String?) ?? 'visiteur';
    final bool isSelf = _sb.auth.currentUser?.id == userRow['id'];

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Rôle • ${userRow['email'] ?? ''}'),
          content: DropdownButtonFormField<String>(
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
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                try {
                  // RLS: le super-admin est autorisé à update public.users
                  await _sb
                      .from('users')
                      .update({'role': role}).eq('id', userRow['id']);
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Rôle mis à jour.')),
                    );
                  }
                } on PostgrestException catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(e.message),
                          backgroundColor: Colors.red),
                    );
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

  // ==================== Onglet INVITATIONS ====================

  Widget _buildInvitesTab() {
    final stream = _sb
        .from('pending_invites')
        .stream(primaryKey: ['email'])
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
                  controller: _invSearchCtrl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Rechercher (email, rôle...)',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _invSearchCtrl.clear();
                        setState(() {});
                      },
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showInviteDialog,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Inviter un utilisateur'),
              ),
            ],
          ),
        ),
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

              final all = snap.data!;
              final q = _invSearchCtrl.text.trim().toLowerCase();

              bool rowMatches(Map<String, dynamic> r) {
                if (q.isEmpty) return true;
                final texts = <String>[
                  r['email']?.toString() ?? '',
                  r['role']?.toString() ?? '',
                ].map((e) => e.toLowerCase());
                return texts.any((e) => e.contains(q));
              }

              final rows = all.where(rowMatches).toList();
              if (rows.isEmpty) {
                return const Center(child: Text('Aucune invitation.'));
              }

              return Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(8),
                decoration: _tableBox(),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Email invité')),
                      DataColumn(label: Text('Rôle prévu')),
                      DataColumn(label: Text('Invité le')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: rows.map((r) {
                      return DataRow(cells: [
                        DataCell(Text(r['email'] ?? '—')),
                        DataCell(_roleChip(r['role'])),
                        DataCell(Text(_fmtTs(r['created_at']))),
                        DataCell(Row(children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            tooltip: 'Modifier rôle',
                            onPressed: () => _editInviteDialog(r),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Retirer l’invitation',
                            onPressed: () => _removeInvite(r['email'] as String),
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

  Future<void> _showInviteDialog() async {
    final formKey = GlobalKey<FormState>();
    final emailCtrl = TextEditingController();
    String role = 'visiteur';

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Inviter un utilisateur'),
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
                            ? 'Email valide requis'
                            : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: const InputDecoration(
                      labelText: 'Rôle attribué à l’inscription',
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
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            ElevatedButton(
              child: const Text('Enregistrer'),
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                try {
                  await _sb.from('pending_invites').upsert({
                    'email': emailCtrl.text.trim(),
                    'role': role,
                  });
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invitation enregistrée.')),
                    );
                  }
                } on PostgrestException catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(e.message),
                          backgroundColor: Colors.red),
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

  Future<void> _editInviteDialog(Map<String, dynamic> inviteRow) async {
    String role = (inviteRow['role'] as String?) ?? 'visiteur';

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Modifier invitation\n${inviteRow['email'] ?? ''}'),
          content: DropdownButtonFormField<String>(
            value: role,
            decoration: const InputDecoration(
              labelText: 'Rôle',
              border: OutlineInputBorder(),
            ),
            items: _knownRoles
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) => role = v ?? role,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                try {
                  await _sb
                      .from('pending_invites')
                      .update({'role': role}).eq('email', inviteRow['email']);
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invitation mise à jour.')),
                    );
                  }
                } on PostgrestException catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(e.message),
                          backgroundColor: Colors.red),
                    );
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

  Future<void> _removeInvite(String email) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Retirer cette invitation ?'),
        content: Text(email),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Retirer')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _sb.from('pending_invites').delete().eq('email', email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitation supprimée.')),
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ==================== Helpers ====================

  static Widget _roleChip(String? role) {
    final r = (role ?? '—').toLowerCase();
    Color c;
    switch (r) {
      case 'super-admin':
        c = Colors.red.shade400;
        break;
      case 'technicien':
        c = Colors.blue.shade400;
        break;
      default:
        c = Colors.grey.shade500;
        break;
    }
    return Chip(
      label: Text(r),
      backgroundColor: c.withOpacity(0.12),
      labelStyle:
          TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w600),
      side: BorderSide(color: c.withOpacity(0.4)),
      visualDensity: VisualDensity.compact,
    );
  }

  static BoxDecoration _tableBox() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      );

  static String _fmtTs(dynamic ts) {
    final d = _parseTs(ts);
    if (d == null) return '—';
    String _2(int x) => x.toString().padLeft(2, '0');
    return '${d.year}-${_2(d.month)}-${_2(d.day)} ${_2(d.hour)}:${_2(d.minute)}';
  }

  static DateTime? _parseTs(dynamic ts) {
    if (ts == null) return null;
    try {
      return DateTime.parse(ts.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }
}
*/
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/supabase_client.dart';

class GestionAccesPage extends StatefulWidget {
  const GestionAccesPage({super.key});
  @override
  State<GestionAccesPage> createState() => _GestionAccesPageState();
}

class _GestionAccesPageState extends State<GestionAccesPage>
    with SingleTickerProviderStateMixin {
  final _sb = SB.client;

  // --------- rôle courant ----------
  String? _role;
  bool _loadingRole = true;
  bool get _isSuperAdmin => _role == 'super-admin';

  // --------- recherches ----------
  final _searchCtrl = TextEditingController();      // utilisateurs
  final _invSearchCtrl = TextEditingController();   // invitations
  final _invHistSearchCtrl = TextEditingController(); // historique

  // --------- rôles connus ----------
  static const Set<String> _knownRoles = {
    'visiteur',
    'technicien',
    'super-admin',
  };

  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _loadRole();
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    _invSearchCtrl.dispose();
    _invHistSearchCtrl.dispose();
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
            final r = await _sb
                .from('users')
                .select('role')
                .eq('id', u.id)
                .maybeSingle();
            final dbRole = r?['role'] as String?;
            if (dbRole != null && dbRole.isNotEmpty) {
              role = dbRole;
              break;
            }
          } catch (_) {}
        }
      }
      setState(() => _role = role ?? 'visiteur');
    } finally {
      if (mounted) setState(() => _loadingRole = false);
    }
  }

  // ==================== UI ROOT ====================

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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TabBar(
            controller: _tab,
            tabs: const [
              Tab(text: 'Utilisateurs'),
              Tab(text: 'Invitations'),
              Tab(text: 'Historique'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _buildUsersTab(),
              _buildInvitesTab(),
              _buildInvitesHistoryTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== Onglet UTILISATEURS ====================

  Widget _buildUsersTab() {
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
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {});
                      },
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
              if (snap.hasError) return Center(child: Text('Erreur: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());

              final all = snap.data!;
              final q = _searchCtrl.text.trim().toLowerCase();

              bool rowMatches(Map<String, dynamic> r) {
                if (q.isEmpty) return true;

                // match date yyyy-mm-dd
                try {
                  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(q)) {
                    final d = DateTime.parse('$q 00:00:00');
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
                return texts.any((e) => e.contains(q));
              }

              final rows = all.where(rowMatches).toList();
              if (rows.isEmpty) {
                return const Center(child: Text('Aucun utilisateur.'));
              }

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(8),
                decoration: _tableBox(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_searchCtrl.text.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 8),
                        child: Chip(
                          avatar: const Icon(Icons.filter_alt, size: 16),
                          label: Text('${rows.length} résultat${rows.length > 1 ? 's' : ''}'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    SingleChildScrollView(
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
                                tooltip: 'Changer le rôle',
                                onPressed: () => _showRoleDialog(u),
                              ),
                            ])),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showRoleDialog(Map<String, dynamic> userRow) async {
    String role = (userRow['role'] as String?) ?? 'visiteur';
    final bool isSelf = _sb.auth.currentUser?.id == userRow['id'];

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Rôle • ${userRow['email'] ?? ''}'),
          content: DropdownButtonFormField<String>(
            value: role,
            decoration: const InputDecoration(
              labelText: 'Rôle',
              border: OutlineInputBorder(),
            ),
            items: _knownRoles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
            onChanged: (isSelf && role == 'super-admin') ? null : (v) => role = v ?? role,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                try {
                  await _sb.from('users').update({'role': role}).eq('id', userRow['id']);
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Rôle mis à jour.')));
                  }
                } on PostgrestException catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.message), backgroundColor: Colors.red),
                    );
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

  // ==================== Onglet INVITATIONS ====================

  Widget _buildInvitesTab() {
    final stream = _sb
        .from('pending_invites')
        .stream(primaryKey: ['email'])
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
                  controller: _invSearchCtrl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Rechercher (email, rôle...)',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _invSearchCtrl.clear();
                        setState(() {});
                      },
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showInviteDialog,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Inviter un utilisateur'),
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
              final q = _invSearchCtrl.text.trim().toLowerCase();

              bool rowMatches(Map<String, dynamic> r) {
                if (q.isEmpty) return true;
                final texts = <String>[
                  r['email']?.toString() ?? '',
                  r['role']?.toString() ?? '',
                ].map((e) => e.toLowerCase());
                return texts.any((e) => e.contains(q));
              }

              final rows = all.where(rowMatches).toList();
              if (rows.isEmpty) {
                return const Center(child: Text('Aucune invitation.'));
              }

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(8),
                decoration: _tableBox(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_invSearchCtrl.text.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 8),
                        child: Chip(
                          avatar: const Icon(Icons.filter_alt, size: 16),
                          label: Text('${rows.length} résultat${rows.length > 1 ? 's' : ''}'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Email invité')),
                          DataColumn(label: Text('Rôle prévu')),
                          DataColumn(label: Text('Invité le')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: rows.map((r) {
                          return DataRow(cells: [
                            DataCell(Text(r['email'] ?? '—')),
                            DataCell(_roleChip(r['role'])),
                            DataCell(Text(_fmtTs(r['created_at']))),
                            DataCell(Row(children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                tooltip: 'Modifier rôle',
                                onPressed: () => _editInviteDialog(r),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Retirer l’invitation',
                                onPressed: () => _removeInvite(r['email'] as String),
                              ),
                            ])),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showInviteDialog() async {
    final formKey = GlobalKey<FormState>();
    final emailCtrl = TextEditingController();
    String role = 'visiteur';

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Inviter un utilisateur'),
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
                            ? 'Email valide requis'
                            : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: const InputDecoration(
                      labelText: 'Rôle attribué à l’inscription',
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
              child: const Text('Enregistrer'),
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                try {
                  await _sb.from('pending_invites').upsert({
                    'email': emailCtrl.text.trim(),
                    'role': role,
                  });
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invitation enregistrée.')),
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

  Future<void> _editInviteDialog(Map<String, dynamic> inviteRow) async {
    String role = (inviteRow['role'] as String?) ?? 'visiteur';

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Modifier invitation\n${inviteRow['email'] ?? ''}'),
          content: DropdownButtonFormField<String>(
            value: role,
            decoration: const InputDecoration(
              labelText: 'Rôle',
              border: OutlineInputBorder(),
            ),
            items: _knownRoles
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) => role = v ?? role,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                try {
                  await _sb
                      .from('pending_invites')
                      .update({'role': role}).eq('email', inviteRow['email']);
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invitation mise à jour.')),
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
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _removeInvite(String email) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Retirer cette invitation ?'),
        content: Text(email),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Retirer')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _sb.from('pending_invites').delete().eq('email', email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitation supprimée.')),
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ==================== Onglet HISTORIQUE ====================
Widget _buildInvitesHistoryTab() {
  final invitesStream = _sb
      .from('invites_hist')
      .stream(primaryKey: ['id'])
      .order('changed_at', ascending: false);

  final rolesStream = _sb
      .from('users_roles_hist')
      .stream(primaryKey: ['id'])
      .order('changed_at', ascending: false);

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
                controller: _invHistSearchCtrl,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Rechercher (email, action, rôle, date...)',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _invHistSearchCtrl.clear();
                      setState(() {});
                    },
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      ),

      // on lit les 2 flux et on fusionne
      Expanded(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: invitesStream,
          builder: (_, snapInv) {
            if (snapInv.hasError) {
              return Center(child: Text('Erreur: ${snapInv.error}'));
            }
            if (!snapInv.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: rolesStream,
              builder: (_, snapRole) {
                if (snapRole.hasError) {
                  return Center(child: Text('Erreur: ${snapRole.error}'));
                }
                if (!snapRole.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                // 1) normalise les 2 listes dans un seul format
                List<_HistRow> items = [];

                // a) invites_hist
                for (final r in snapInv.data!) {
                  String roleFromJson(dynamic j) {
                    try {
                      final m = (j == null)
                          ? <String, dynamic>{}
                          : Map<String, dynamic>.from(j);
                      final v = m['role']?.toString();
                      return (v == null || v.isEmpty) ? '—' : v;
                    } catch (_) {
                      return '—';
                    }
                  }

                  items.add(_HistRow(
                    changedAt: _parseTs(r['changed_at']) ?? DateTime.now(),
                    email: (r['email'] ?? '—').toString(),
                    action: (r['action'] ?? '—').toString(),  // invited / updated / deleted / consumed
                    oldRole: roleFromJson(r['old_data']),
                    newRole: roleFromJson(r['new_data']),
                    by: (r['changed_by_email'] ?? '—').toString(),
                  ));
                }

                // b) users_roles_hist
                for (final r in snapRole.data!) {
                  items.add(_HistRow(
                    changedAt: _parseTs(r['changed_at']) ?? DateTime.now(),
                    email: (r['email'] ?? '—').toString(),
                    action: (r['action'] ?? 'role_changed').toString(), // user_created / role_changed
                    oldRole: (r['old_role'] ?? '—').toString(),
                    newRole: (r['new_role'] ?? '—').toString(),
                    by: (r['changed_by_email'] ?? '—').toString(),
                  ));
                }

                // 2) tri + filtre de recherche
                items.sort((a, b) => b.changedAt.compareTo(a.changedAt));

                final q = _invHistSearchCtrl.text.trim().toLowerCase();
                bool matches(_HistRow x) {
                  if (q.isEmpty) return true;

                  // match date yyyy-mm-dd
                  try {
                    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(q)) {
                      final d = DateTime.parse('$q 00:00:00');
                      final c = x.changedAt;
                      if (c.year == d.year && c.month == d.month && c.day == d.day) {
                        return true;
                      }
                    }
                  } catch (_) {}

                  return [
                    x.email.toLowerCase(),
                    x.action.toLowerCase(),
                    (x.oldRole ?? '').toLowerCase(),
                    (x.newRole ?? '').toLowerCase(),
                    x.by.toLowerCase(),
                  ].any((s) => s.contains(q));
                }

                final filtered = items.where(matches).toList();

                // 3) rendu
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: _tableBox(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (q.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 8),
                          child: Chip(
                            avatar: const Icon(Icons.filter_alt, size: 16),
                            label: Text(
                              '${filtered.length} résultat${filtered.length > 1 ? 's' : ''}',
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Date')),
                            DataColumn(label: Text('Email')),
                            DataColumn(label: Text('Action')),
                            DataColumn(label: Text('Rôle (avant → après)')),
                            DataColumn(label: Text('Par')),
                          ],
                          rows: filtered.map((x) {
                            return DataRow(cells: [
                              DataCell(Text(_fmtTs(x.changedAt.toIso8601String()))),
                              DataCell(Text(x.email)),
                              DataCell(Text(x.action)),
                              DataCell(Text('${x.oldRole ?? '—'} → ${x.newRole ?? '—'}')),
                              DataCell(Text(x.by)),
                            ]);
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    ],
  );
}
 /* Widget _buildInvitesHistoryTab() {
    final stream = _sb
        .from('invites_hist')
        .stream(primaryKey: ['id'])
        .order('changed_at', ascending: false);

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
                  controller: _invHistSearchCtrl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Rechercher',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _invHistSearchCtrl.clear();
                        setState(() {});
                      },
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
              if (snap.hasError) return Center(child: Text('Erreur: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());

              final all = snap.data!;
              final q = _invHistSearchCtrl.text.trim().toLowerCase();

              bool matches(Map<String, dynamic> r) {
                if (q.isEmpty) return true;
                final texts = <String>[
                  r['email']?.toString() ?? '',
                  r['action']?.toString() ?? '',
                  r['changed_by_email']?.toString() ?? '',
                ].map((e) => e.toLowerCase());
                return texts.any((e) => e.contains(q));
              }

              final rows = all.where(matches).toList();

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(8),
                decoration: _tableBox(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_invHistSearchCtrl.text.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 8),
                        child: Chip(
                          avatar: const Icon(Icons.filter_alt, size: 16),
                          label: Text('${rows.length} résultat${rows.length > 1 ? 's' : ''}'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Email')),
                          DataColumn(label: Text('Action')),
                          DataColumn(label: Text('Rôle (avant → après)')),
                          DataColumn(label: Text('Par')),
                        ],
                        rows: rows.map((r) {
                          String roleFromJson(dynamic j) {
                            try {
                              final m = (j == null)
                                  ? <String, dynamic>{}
                                  : Map<String, dynamic>.from(j);
                              final v = m['role']?.toString();
                              return (v == null || v.isEmpty) ? '—' : v;
                            } catch (_) {
                              return '—';
                            }
                          }

                          final oldRole = roleFromJson(r['old_data']);
                          final newRole = roleFromJson(r['new_data']);

                          return DataRow(cells: [
                            DataCell(Text(_fmtTs(r['changed_at']))),
                            DataCell(Text(r['email'] ?? '—')),
                            DataCell(Text(r['action'] ?? '—')),
                            DataCell(Text('$oldRole → $newRole')),
                            DataCell(Text(r['changed_by_email'] ?? '—')),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }*/

  // ==================== Helpers ====================

  static Widget _roleChip(String? role) {
    final r = (role ?? '—').toLowerCase();
    Color c;
    switch (r) {
      case 'super-admin':
        c = Colors.red.shade400;
        break;
      case 'technicien':
        c = Colors.blue.shade400;
        break;
      default:
        c = Colors.grey.shade500;
        break;
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
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: Offset(0, 3)),
        ],
      );

  static String _fmtTs(dynamic ts) {
    final d = _parseTs(ts);
    if (d == null) return '—';
    String _2(int x) => x.toString().padLeft(2, '0');
    return '${d.year}-${_2(d.month)}-${_2(d.day)} ${_2(d.hour)}:${_2(d.minute)}';
  }

  static DateTime? _parseTs(dynamic ts) {
    if (ts == null) return null;
    try {
      return DateTime.parse(ts.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }
}
class _HistRow {
  final DateTime changedAt;
  final String email;
  final String action; // invited / updated / deleted / consumed / user_created / role_changed
  final String? oldRole;
  final String? newRole;
  final String by;

  _HistRow({
    required this.changedAt,
    required this.email,
    required this.action,
    required this.oldRole,
    required this.newRole,
    required this.by,
  });
}