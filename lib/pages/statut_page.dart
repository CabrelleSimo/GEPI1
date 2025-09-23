import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/supabase_client.dart';

class StatutPage extends StatefulWidget {
  const StatutPage({super.key});

  @override
  State<StatutPage> createState() => _StatutPageState();
}

class _StatutPageState extends State<StatutPage> {
  final _sb = SB.client;

  String? _role;
  bool _loadingRole = true;
  bool get _canWrite => _role == 'technicien' || _role == 'super-admin';

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    setState(() => _loadingRole = true);
    try { 
      final user = _sb.auth.currentUser;
      // 1) rôle direct du JWT (metadata)
      String? role = user?.userMetadata?['role'] as String?;
      // 2) confirme depuis la BD avec quelques retries courts
      if (user != null) {
        final delaysMs = [0, 300, 800, 1500];
        for (final d in delaysMs) {
          if (d > 0) await Future.delayed(Duration(milliseconds: d));
          try {
            final row = await _sb
                .from('users')
                .select('role')
                .eq('id', user.id)
                .maybeSingle();
            final dbRole = row?['role'] as String?;
            if (dbRole != null && dbRole.isNotEmpty) {
              role = dbRole;
              break;
            }
          } catch (_) {/* retry */}
        }
      }
      setState(() => _role = role ?? 'visiteur');
    } finally {
      if (mounted) setState(() => _loadingRole = false);
    }
  }

  Future<void> _showAddDialog() async {
    final nomCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Ajouter un statut'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nomCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom *',
                    prefixIcon: Icon(Icons.info_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description (optionnel)',
                    prefixIcon: Icon(Icons.notes),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: !_canWrite
                  ? null
                  : () async {
                      final nom = nomCtrl.text.trim();
                      final description = descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim();

                      if (nom.isEmpty) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Le nom est requis'), backgroundColor: Colors.red),
                          );
                        }
                        return;
                      }

                      try {
                        final uid = _sb.auth.currentUser?.id;
                        await _sb.from('etats').insert({
                          'nom': nom,
                          'description': description,
                          if (uid != null) 'created_by': uid,
                        });
                        if (mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Statut ajouté')),
                          );
                        }
                      } on PostgrestException catch (e) {
                        final msg = e.code == '23505'
                            ? 'Un statut avec ce nom existe déjà.'
                            : (e.code == '42501'
                                ? "Accès refusé (vérifie les droits/RLS)."
                                : e.message);
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
              child: const Text('Ajouter'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEditDialog(Map<String, dynamic> etat) async {
    final nomCtrl = TextEditingController(text: etat['nom'] ?? '');
    final descCtrl = TextEditingController(text: etat['description'] ?? '');

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Modifier le statut'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nomCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom *',
                    prefixIcon: Icon(Icons.info_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description ',
                    prefixIcon: Icon(Icons.notes),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: !_canWrite
                  ? null
                  : () async {
                      final nom = nomCtrl.text.trim();
                      final description = descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim();

                      if (nom.isEmpty) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Le nom est requis'), backgroundColor: Colors.red),
                          );
                        }
                        return;
                      }

                      try {
                        await _sb
                            .from('etats')
                            .update({'nom': nom, 'description': description})
                            .eq('id', etat['id']);
                        if (mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Statut modifié')),
                          );
                        }
                      } on PostgrestException catch (e) {
                        final msg = e.code == '23505'
                            ? 'Un état avec ce nom existe déjà.'
                            : (e.code == '42501'
                                ? "Accès refusé (vérifie les droits/RLS)."
                                : e.message);
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
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final stream = _sb
        .from('etats')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loadingRole)
          const LinearProgressIndicator(minHeight: 2)
        else if (!_canWrite)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            color: Colors.amber.withOpacity(0.15),
            child: const Text(
              "Lecture seule (rôle: visiteur). L’ajout et la modification sont réservés aux techniciens et super-admins.",
            ),
          ),

        // barre d’actions
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: _canWrite ? _showAddDialog : null,
                icon: const Icon(Icons.add),
                label: const Text('Ajouter un statut'),
              ),
            ],
          ),
        ),

        // liste
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Erreur: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data!;
              if (rows.isEmpty) {
                return const Center(child: Text('Aucun statut. Ajoutez-en.'));
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final r = rows[i];
                  return Card(
                    elevation: 2,
                    child: ListTile(
                      leading: const Icon(Icons.info, color: Colors.blue),
                      title: Text(r['nom'] ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: (r['description'] == null || (r['description'] as String).isEmpty)
                          ? null
                          : Text(r['description']),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: _canWrite ? 'Modifier' : 'Lecture seule',
                        onPressed: _canWrite ? () => _showEditDialog(r) : null,
                      ),
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
}
