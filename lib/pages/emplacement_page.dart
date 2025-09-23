import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/supabase_client.dart';

class EmplacementPage extends StatefulWidget {
  const EmplacementPage({super.key});

  @override
  State<EmplacementPage> createState() => _EmplacementPageState();
}

class _EmplacementPageState extends State<EmplacementPage> {
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
      // 1) rôle de la session (metadata) immédiat
      String? role = user?.userMetadata?['role'] as String?;
      // 2) confirme depuis la BD avec quelques tentatives
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
          } catch (_) {/* ignore et retente */}
        }
      }
      setState(() => _role = role ?? 'visiteur');
    } finally {
      if (mounted) setState(() => _loadingRole = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sitesStream = _sb
        .from('sites')
        .stream(primaryKey: ['id'])
        .order('created_at');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bandeau d’info droits
        if (_loadingRole)
          const LinearProgressIndicator(minHeight: 2)
        else if (!_canWrite)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            color: Colors.amber.withOpacity(0.15),
            child: const Text(
              "Vous êtes en lecture seule (rôle: visiteur).",
              style: TextStyle(color: Colors.black87),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: _buildAddButtons(),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: sitesStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Erreur: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final sites = snapshot.data!;
              if (sites.isEmpty) {
                return const Center(child: Text("Aucun site trouvé."));
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: sites.length,
                itemBuilder: (context, index) {
                  final site = sites[index];
                  return _buildSiteCard(site);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAddButtons() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ElevatedButton.icon(
          onPressed: _canWrite ? () => _showAddDialog('site') : null,
          icon: const Icon(Icons.add_location),
          label: const Text('Ajouter un Site'),
        ),
        ElevatedButton.icon(
          onPressed: _canWrite ? () => _showAddDialog('batiment') : null,
          icon: const Icon(Icons.apartment),
          label: const Text('Ajouter un Bâtiment'),
        ),
        ElevatedButton.icon(
          onPressed: _canWrite ? () => _showAddDialog('salle') : null,
          icon: const Icon(Icons.meeting_room),
          label: const Text('Ajouter une Salle'),
        ),
      ],
    );
  }

  Widget _buildSiteCard(Map<String, dynamic> site) {
    final siteId = site['id'] as String;
    final batimentsStream = _sb
        .from('batiments')
        .stream(primaryKey: ['id'])
        .eq('site_id', siteId)
        .order('created_at');

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        title: Text(site['nom'] ?? 'Nom inconnu',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(site['adresse'] ?? 'Adresse inconnue'),
        leading: const Icon(Icons.location_city, color: Colors.blue),
        children: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: batimentsStream,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Erreur: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                );
              }
              final batiments = snap.data!;
              if (batiments.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("Aucun bâtiment dans ce site."),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: batiments.length,
                itemBuilder: (context, index) {
                  final bat = batiments[index];
                  return _buildBatimentCard(siteId, bat);
                },
              );
            },
          )
        ],
      ),
    );
  }

  Widget _buildBatimentCard(String siteId, Map<String, dynamic> batiment) {
    final batimentId = batiment['id'] as String;
    final sallesStream = _sb
        .from('salles')
        .stream(primaryKey: ['id'])
        .eq('batiment_id', batimentId)
        .order('created_at');

    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ExpansionTile(
        title: Text(batiment['nom'] ?? 'Nom inconnu',
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(batiment['adresse'] ?? 'Adresse inconnue'),
        leading: const Icon(Icons.apartment, color: Colors.green),
        children: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: sallesStream,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Erreur: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                );
              }
              final salles = snap.data!;
              if (salles.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("Aucune salle dans ce bâtiment."),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: salles.length,
                itemBuilder: (context, index) {
                  final salle = salles[index];
                  return _buildSalleItem(salle);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSalleItem(Map<String, dynamic> salle) {
    return Padding(
      padding: const EdgeInsets.only(left: 64.0),
      child: ListTile(
        title: Text(salle['nom'] ?? 'Nom inconnu'),
        subtitle: Text(salle['adresse'] ?? 'Adresse inconnue'),
        leading: const Icon(Icons.meeting_room, color: Colors.orange),
      ),
    );
  }

  void _showAddDialog(String type) {
    final nomController = TextEditingController();
    final adresseController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        String? selectedSiteId;
        String? selectedBatimentId;

        final sitesFuture = _sb.from('sites').select('id, nom').order('nom');

        Future<List<Map<String, dynamic>>> batimentsFuture(String siteId) async {
          final res = await _sb
              .from('batiments')
              .select('id, nom')
              .eq('site_id', siteId)
              .order('nom');
          return List<Map<String, dynamic>>.from(res as List);
        }

        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: Text('Ajouter un $type'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nomController,
                    decoration: const InputDecoration(labelText: 'Nom *'),
                  ),
                  TextField(
                    controller: adresseController,
                    decoration: const InputDecoration(labelText: 'Adresse'),
                  ),
                  if (type == 'batiment' || type == 'salle')
                    FutureBuilder<List<dynamic>>(
                      future: sitesFuture,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snap.hasError) {
                          return Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text('Erreur chargement sites: ${snap.error}'),
                          );
                        }
                        final sites = List<Map<String, dynamic>>.from(snap.data ?? []);
                        return DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Site Parent *'),
                          value: selectedSiteId,
                          items: sites
                              .map((s) => DropdownMenuItem<String>(
                                    value: s['id'] as String,
                                    child: Text(s['nom'] ?? 'Sans nom'),
                                  ))
                              .toList(),
                          onChanged: (v) async {
                            setState(() {
                              selectedSiteId = v;
                              selectedBatimentId = null;
                            });
                          },
                        );
                      },
                    ),
                  if (type == 'salle' && selectedSiteId != null)
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: batimentsFuture(selectedSiteId!),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snap.hasError) {
                          return Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text('Erreur chargement bâtiments: ${snap.error}'),
                          );
                        }
                        final bats = snap.data ?? <Map<String, dynamic>>[];
                        return DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Bâtiment Parent *'),
                          value: selectedBatimentId,
                          items: bats
                              .map((b) => DropdownMenuItem<String>(
                                    value: b['id'] as String,
                                    child: Text(b['nom'] ?? 'Sans nom'),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => selectedBatimentId = v),
                        );
                      },
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: !_canWrite
                    ? null
                    : () async {
                        String? error;
                        if (nomController.text.isEmpty) {
                          error = 'Le nom est requis';
                        } else if ((type == 'batiment' || type == 'salle') &&
                            selectedSiteId == null) {
                          error = 'Veuillez sélectionner un site parent';
                        } else if (type == 'salle' && selectedBatimentId == null) {
                          error = 'Veuillez sélectionner un bâtiment parent';
                        }

                        if (error != null) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(error)));
                          }
                          return;
                        }

                        try {
                          final uid = _sb.auth.currentUser?.id;

                          if (type == 'site') {
                            await _sb.from('sites').insert({
                              'nom': nomController.text,
                              'adresse': adresseController.text,
                              if (uid != null) 'created_by': uid,
                            });
                          } else if (type == 'batiment') {
                            await _sb.from('batiments').insert({
                              'site_id': selectedSiteId,
                              'nom': nomController.text,
                              'adresse': adresseController.text,
                              if (uid != null) 'created_by': uid,
                            });
                          } else if (type == 'salle') {
                            await _sb.from('salles').insert({
                              'batiment_id': selectedBatimentId,
                              'nom': nomController.text,
                              'adresse': adresseController.text,
                              if (uid != null) 'created_by': uid,
                            });
                          }

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$type ajouté avec succès')),
                            );
                            Navigator.of(context).pop();
                          }
                        } on PostgrestException catch (e) {
                          // Erreurs BD/RLS explicites
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Erreur: ${e.message}')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Erreur: $e')),
                            );
                          }
                        }
                      },
                child: const Text('Ajouter'),
              ),
            ],
          );
        });
      },
    );
  }
}

/*import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/supabase_client.dart';

class EmplacementPage extends StatefulWidget {
  const EmplacementPage({super.key});

  @override
  State<EmplacementPage> createState() => _EmplacementPageState();
}

class _EmplacementPageState extends State<EmplacementPage> {
  final _sb = SB.client;

  @override
  Widget build(BuildContext context) {
    final sitesStream = _sb
        .from('sites')
        .stream(primaryKey: ['id'])
        .order('created_at');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: _buildAddButtons(),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: sitesStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Erreur: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final sites = snapshot.data!;
              if (sites.isEmpty) {
                return const Center(child: Text("Aucun site trouvé."));
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: sites.length,
                itemBuilder: (context, index) {
                  final site = sites[index];
                  return _buildSiteCard(site);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAddButtons() {
    return Row(
      children: [
        ElevatedButton.icon(
          onPressed: () => _showAddDialog('site'),
          icon: const Icon(Icons.add_location),
          label: const Text('Ajouter un Site'),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed: () => _showAddDialog('batiment'),
          icon: const Icon(Icons.apartment),
          label: const Text('Ajouter un Bâtiment'),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed: () => _showAddDialog('salle'),
          icon: const Icon(Icons.meeting_room),
          label: const Text('Ajouter une Salle'),
        ),
      ],
    );
  }

  Widget _buildSiteCard(Map<String, dynamic> site) {
    final siteId = site['id'] as String;
    final batimentsStream = _sb
        .from('batiments')
        .stream(primaryKey: ['id'])
        .eq('site_id', siteId)
        .order('created_at');

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        title: Text(site['nom'] ?? 'Nom inconnu',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(site['adresse'] ?? 'Adresse inconnue'),
        leading: const Icon(Icons.location_city, color: Colors.blue),
        children: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: batimentsStream,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Erreur: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final batiments = snap.data!;
              if (batiments.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("Aucun bâtiment dans ce site."),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: batiments.length,
                itemBuilder: (context, index) {
                  final bat = batiments[index];
                  return _buildBatimentCard(siteId, bat);
                },
              );
            },
          )
        ],
      ),
    );
  }

  Widget _buildBatimentCard(String siteId, Map<String, dynamic> batiment) {
    final batimentId = batiment['id'] as String;
    final sallesStream = _sb
        .from('salles')
        .stream(primaryKey: ['id'])
        .eq('batiment_id', batimentId)
        .order('created_at');

    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ExpansionTile(
        title: Text(batiment['nom'] ?? 'Nom inconnu',
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(batiment['adresse'] ?? 'Adresse inconnue'),
        leading: const Icon(Icons.apartment, color: Colors.green),
        children: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: sallesStream,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Erreur: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final salles = snap.data!;
              if (salles.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("Aucune salle dans ce bâtiment."),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: salles.length,
                itemBuilder: (context, index) {
                  final salle = salles[index];
                  return _buildSalleItem(salle);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSalleItem(Map<String, dynamic> salle) {
    return Padding(
      padding: const EdgeInsets.only(left: 64.0),
      child: ListTile(
        title: Text(salle['nom'] ?? 'Nom inconnu'),
        subtitle: Text(salle['adresse'] ?? 'Adresse inconnue'),
        leading: const Icon(Icons.meeting_room, color: Colors.orange),
      ),
    );
  }

  void _showAddDialog(String type) {
    final nomController = TextEditingController();
    final adresseController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        String? selectedSiteId;
        String? selectedBatimentId;

        final sitesFuture =
            _sb.from('sites').select('id, nom').order('nom');

        Future<List<Map<String, dynamic>>> batimentsFuture(String siteId) =>
            _sb.from('batiments')
                .select('id, nom')
                .eq('site_id', siteId)
                .order('nom');

        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: Text('Ajouter un $type'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nomController,
                    decoration: const InputDecoration(labelText: 'Nom *'),
                  ),
                  TextField(
                    controller: adresseController,
                    decoration: const InputDecoration(labelText: 'Adresse'),
                  ),
                  if (type == 'batiment' || type == 'salle')
                    FutureBuilder<List<dynamic>>(
                      future: sitesFuture,
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(),
                          );
                        }
                        final sites = List<Map<String, dynamic>>.from(snap.data!);
                        return DropdownButtonFormField<String>(
                          decoration:
                              const InputDecoration(labelText: 'Site Parent *'),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Sélectionnez un site'),
                            ),
                            ...sites.map((s) => DropdownMenuItem<String>(
                                  value: s['id'] as String,
                                  child: Text(s['nom'] ?? 'Sans nom'),
                                ))
                          ],
                          onChanged: (v) async {
                            setState(() {
                              selectedSiteId = v;
                              selectedBatimentId = null;
                            });
                          },
                          value: selectedSiteId,
                        );
                      },
                    ),
                  if (type == 'salle' && selectedSiteId != null)
                    FutureBuilder<List<dynamic>>(
                      future: batimentsFuture(selectedSiteId!),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(),
                          );
                        }
                        final bats =
                            List<Map<String, dynamic>>.from(snap.data!);
                        return DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                              labelText: 'Bâtiment Parent *'),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Sélectionnez un bâtiment'),
                            ),
                            ...bats.map((b) => DropdownMenuItem<String>(
                                  value: b['id'] as String,
                                  child: Text(b['nom'] ?? 'Sans nom'),
                                ))
                          ],
                          onChanged: (v) {
                            setState(() {
                              selectedBatimentId = v;
                            });
                          },
                          value: selectedBatimentId,
                        );
                      },
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () async {
                  String? error;
                  if (nomController.text.isEmpty) {
                    error = 'Le nom est requis';
                  } else if ((type == 'batiment' || type == 'salle') &&
                      selectedSiteId == null) {
                    error = 'Veuillez sélectionner un site parent';
                  } else if (type == 'salle' && selectedBatimentId == null) {
                    error = 'Veuillez sélectionner un bâtiment parent';
                  }

                  if (error != null) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(error)));
                    return;
                  }

                  try {
                    if (type == 'site') {
                      await _sb.from('sites').insert({
                        'nom': nomController.text,
                        'adresse': adresseController.text,
                      });
                    } else if (type == 'batiment') {
                      await _sb.from('batiments').insert({
                        'site_id': selectedSiteId,
                        'nom': nomController.text,
                        'adresse': adresseController.text,
                      });
                    } else if (type == 'salle') {
                      await _sb.from('salles').insert({
                        'batiment_id': selectedBatimentId,
                        'nom': nomController.text,
                        'adresse': adresseController.text,
                      });
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$type ajouté avec succès')),
                      );
                      Navigator.of(context).pop();
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erreur: $e')),
                      );
                    }
                  }
                },
                child: const Text('Ajouter'),
              ),
            ],
          );
        });
      },
    );
  }
}
*/