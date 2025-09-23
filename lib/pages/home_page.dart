
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gepi/pages/gestion_acces_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gepi/pages/equipements_page.dart';
import 'package:gepi/pages/statut_page.dart';
import 'package:gepi/pages/hse_page.dart';
import 'package:gepi/pages/maintenance_page.dart';
import 'package:gepi/pages/interventions_page.dart';
import 'package:gepi/pages/emplacement_page.dart';
import 'package:gepi/pages/redirection_page.dart';
import 'package:gepi/services/supabase/auth.dart';
import 'package:gepi/supabase_client.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title, this.userRole});

  final String title;
  final String? userRole;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _sb = SB.client;
  final User? _user = Auth().currentUser;

  // ----------- Auth / rôle -----------
  String? _userRole;
  String? _userEmail;
  bool _loadingRole = true;
  StreamSubscription<AuthState>? _authSub;

  // ----------- Navigation -----------
  String _selectedPage = 'Tableau de bord';

  // ----------- KPI dashboard (dynamiques) -----------
  // mapping etat_id -> nom d’état
  Map<String, String> _etatNameById = {};
  // dernière vue "équipements" pour recalcul rapide quand les états changent
  List<Map<String, dynamic>> _lastEquipementsRows = [];

  // chiffres du dashboard
  int _countTotal = 0;
  int _countEnUtilisation = 0;
  int _countEnMaintenance = 0;
  int _countPretes = 0;
  int _countRebut = 0;
  int _countDonnes = 0;
  int _countInactifs = 0;

  // stream subs
  StreamSubscription<List<Map<String, dynamic>>>? _eqSub;
  StreamSubscription<List<Map<String, dynamic>>>? _etatsSub;

  @override
  void initState() {
    super.initState();

    _userEmail = _user?.email;

    // 1) rôle passé depuis la page précédente
    _userRole = widget.userRole;

    // 2) rôle depuis les metadata
    _userRole ??= SB.client.auth.currentUser?.userMetadata?['role'] as String?;

    // 3) confirme côté BD
    _fetchUserRole();

    // Écoute des changements d’auth
    _authSub = _sb.auth.onAuthStateChange.listen((_) async {
      if (!mounted) return;
      setState(() => _userEmail = _sb.auth.currentUser?.email);
      await _fetchUserRole();
    });

    // charge le référentiel des états + ouvre les streams
    _subscribeEtats();
    _subscribeEquipements();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _eqSub?.cancel();
    _etatsSub?.cancel();
    super.dispose();
  }

  // ======================== RÔLES ========================

  Future<void> _fetchUserRole() async {
    setState(() => _loadingRole = true);
    try {
      final user = _sb.auth.currentUser;
      if (user == null) return;

      final delaysMs = [0, 300, 800, 1500];
      String? roleFromDb;
      for (final d in delaysMs) {
        if (d > 0) await Future.delayed(Duration(milliseconds: d));
        final res = await _sb.from('users').select('role').eq('id', user.id).maybeSingle();
        roleFromDb = res?['role'] as String?;
        if (roleFromDb != null && roleFromDb.isNotEmpty) break;
      }

      if (!mounted) return;
      setState(() {
        if (roleFromDb != null && roleFromDb.isNotEmpty) _userRole = roleFromDb;
      });
    } catch (_) {
      // on n’écrase pas en cas d’erreur réseau
    } finally {
      if (mounted) setState(() => _loadingRole = false);
    }
  }

  // ======================== STREAMS (temps réel) ========================

  void _subscribeEtats() async {
    // stream des états -> maintient le mapping id -> nom
    final stream = _sb.from('etats').stream(primaryKey: ['id']);
    _etatsSub = stream.listen((rows) {
      _etatNameById = {
        for (final r in rows)
          (r['id']?.toString() ?? ''): (r['nom']?.toString() ?? '')
      };
      // recalcul des KPI avec la dernière vue équipements
      _recomputeKpis(_lastEquipementsRows);
    }, onError: (_) {});
  }

  void _subscribeEquipements() {
    // on récupère tout (comme dans EquipementsPage) pour rester cohérent
    final stream = _sb.from('equipements').stream(primaryKey: ['id']);
    _eqSub = stream.listen((rows) {
      _lastEquipementsRows = rows;
      _recomputeKpis(rows);
    }, onError: (_) {});
  }

  // ======================== CALCUL KPI ========================

  // normalise les libellés d’état (enlève accents/majuscules)
  String _norm(String s) {
    var x = s.toLowerCase().trim();
    x = x
        .replaceAll(RegExp(r'[àáâä]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[îïíì]'), 'i')
        .replaceAll(RegExp(r'[ôöóò]'), 'o')
        .replaceAll(RegExp(r'[ûüúù]'), 'u')
        .replaceAll('ç', 'c');
    return x;
  }

  // classe la valeur dans une “famille” de KPI
  String _bucketFromEtatName(String? name) {
    if (name == null) return '';
    final n = _norm(name);
    if (n.contains('utilisation')) return 'en_utilisation';
    if (n.contains('maintenance')) return 'en_maintenance';
    if (n.startsWith('prete') || n.startsWith('prêt')) return 'prete';
    if (n.contains('rebut')) return 'rebut';
    if (n.startsWith('donne') || n.startsWith('don')) return 'donne';
    if (n.startsWith('inact')) return 'inactif';
    return ''; // autre/HS/OK… non agrégé sur ce dashboard
  }

  void _recomputeKpis(List<Map<String, dynamic>> rows) {
    int total = rows.length;
    int util = 0, maint = 0, prete = 0, rebut = 0, donne = 0, inactif = 0;

    for (final r in rows) {
      final etatId = r['etat_id']?.toString();
      final etatName = (etatId != null) ? _etatNameById[etatId] : null;
      switch (_bucketFromEtatName(etatName)) {
        case 'en_utilisation':
          util++;
          break;
        case 'en_maintenance':
          maint++;
          break;
        case 'prete':
          prete++;
          break;
        case 'rebut':
          rebut++;
          break;
        case 'donne':
          donne++;
          break;
        case 'inactif':
          inactif++;
          break;
      }
    }

    if (!mounted) return;
    setState(() {
      _countTotal = total;
      _countEnUtilisation = util;
      _countEnMaintenance = maint;
      _countPretes = prete;
      _countRebut = rebut;
      _countDonnes = donne;
      _countInactifs = inactif;
    });
  }

  // ======================== UI ========================

  final List<Map<String, dynamic>> _menuItems = const [
    {"title": "Tableau de bord", "icon": Icons.dashboard},
    {"title": "Équipements", "icon": Icons.devices},
    {"title": "Maintenance", "icon": Icons.build},
    {"title": "HSE", "icon": Icons.shield_outlined},
    {"title": "Fournisseurs", "icon": Icons.store},
    {"title": "Emplacement", "icon": Icons.location_on},
    {"title": "Statut", "icon": Icons.info},
    {"title": "Interventions", "icon": Icons.handyman},
    {"title": "Gestion des profils", "icon": Icons.manage_accounts},
  ];

  bool _isMenuEnabled(String title) {
    if (title == "Gestion des profils") {
      return _userRole == 'super-admin';
    }
    return true;
  }

  void _onSelectPage(String title) {
    if (!_isMenuEnabled(title)) return;
    setState(() => _selectedPage = title);
  }

  Future<void> _logoutAndGoHome() async {
    await Auth().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RedirectionPage()),
      (route) => false,
    );
  }

  Widget _buildSideNav() {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.background,
        border: Border(right: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          DrawerHeader(
            child: Row(
              children: [
                CircleAvatar(
                  child: const Text('G'),
                  backgroundColor: Colors.blue.shade300,
                ),
                const SizedBox(width: 12),
                const Text('GEPI',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemBuilder: (context, index) {
                final item = _menuItems[index];
                final enabled = _isMenuEnabled(item['title'] as String);
                final selected = _selectedPage == item['title'];
                return ListTile(
                  leading: Icon(
                    item['icon'] as IconData,
                    color: enabled
                        ? (selected ? Colors.blue : Colors.black54)
                        : Colors.grey,
                  ),
                  title: Text(
                    item['title'] as String,
                    style: TextStyle(
                      color: enabled
                          ? (selected ? Colors.blue : Colors.black87)
                          : Colors.grey,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  onTap:
                      enabled ? () => _onSelectPage(item['title'] as String) : null,
                  tileColor: selected ? Colors.blue.withOpacity(0.05) : null,
                );
              },
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: _menuItems.length,
            ),
          ),
          // (Tu as demandé d’enlever “Se déconnecter” du menu latéral — on ne l’affiche plus ici)
        ],
      ),
    );
  }

  Widget _buildMainArea() {
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_selectedPage,
                          style: const TextStyle(
                              fontSize: 28, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text('Accueil > $_selectedPage',
                          style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                if (_loadingRole)
                  const SizedBox(
                      width: 200,
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2)))
                else
                  Row(
                    children: [
                      // Icône “télécharger” conservée (sans action pour l’instant)
                      IconButton(
                        icon: Icon(Icons.download, color: Colors.blue.shade700),
                        tooltip: 'Exporter (bientôt)',
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Fonction export à venir.'),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.verified_user,
                                size: 18, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Text('${_userRole ?? 'visiteur'} • ${_userEmail ?? ''}'),
                          ],
                        ),
                      ),
                      // Menu profil (gérer le profil / se déconnecter)
                      PopupMenuButton<String>(
                        tooltip: 'Profil',
                        offset: const Offset(0, 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onSelected: (value) async {
                          switch (value) {
                            case 'profile':
                              // TODO: ouvre ta page "Gestion des profils" ou un dialog
                              _onSelectPage('Gestion des profils');
                              break;
                            case 'logout':
                              await _logoutAndGoHome();
                              break;
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'profile',
                            child: ListTile(
                              leading: Icon(Icons.person_outline),
                              title: Text('Gérer le profil'),
                            ),
                          ),
                          PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'logout',
                            child: ListTile(
                              leading: Icon(Icons.logout),
                              title: Text('Se déconnecter'),
                            ),
                          ),
                        ],
                        child: CircleAvatar(
                          radius: 16,
                          child: Text(
                            (_userEmail != null && _userEmail!.isNotEmpty)
                                ? _userEmail![0].toUpperCase()
                                : 'U',
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Expanded(child: _buildPageContent()),
        ],
      ),
    );
  }

  Widget _buildPageContent() {
    switch (_selectedPage) {
      case 'Tableau de bord':
        return _buildDashboard();
      case 'Équipements':
        return const EquipementsPage();
      case 'Maintenance':
        return const MaintenancePage();
      case 'HSE':
        return const HsePage();
      case 'Fournisseurs':
        return _buildPlaceholder(_selectedPage);
      case 'Emplacement':
        return const EmplacementPage();
      case 'Statut':
        return const StatutPage();
      case 'Interventions':
        return const InterventionsPage();
      case 'Gestion des profils':
        return const GestionAccesPage();
      default:
        return _buildPlaceholder(_selectedPage);
    }
  }

  Widget _buildPlaceholder(String title) {
    return SizedBox(
      height: 400,
      child: Center(
        child: Text('$title : page à implémenter',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade700)),
      ),
    );
  }

  Widget _buildProfilesPage() {
    if (_userRole != 'super-admin') {
      return const SizedBox(
        height: 160,
        child: Center(
          child: Text("Accès réservé au Super-Admin",
              style: TextStyle(color: Colors.red)),
        ),
      );
    }
    return const SizedBox(
      height: 400,
      child: Center(
        child:
            Text("Gestion des profils (Super-Admin)", style: TextStyle(fontSize: 18)),
      ),
    );
  }

  Color _getIconColor(String title) {
    switch (title) {
      case 'Actifs totaux':
        return Colors.blue;
      case 'En utilisation':
        return Colors.green;
      case 'En maintenance':
        return Colors.orange;
      case 'Prêtés':
        return Colors.purple;
      case 'Mis au rebut':
        return Colors.red;
      case 'Donnés':
        return Colors.pink;
      case 'Inactifs':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  Widget _buildDashboard() {
    final cards = [
      {'title': 'Actifs totaux', 'value': _countTotal, 'icon': Icons.inventory_2},
      {'title': 'En utilisation', 'value': _countEnUtilisation, 'icon': Icons.check_circle},
      {'title': 'En maintenance', 'value': _countEnMaintenance, 'icon': Icons.build_circle},
      {'title': 'Prêtés', 'value': _countPretes, 'icon': Icons.local_shipping},
      {'title': 'Mis au rebut', 'value': _countRebut, 'icon': Icons.delete},
      {'title': 'Donnés', 'value': _countDonnes, 'icon': Icons.volunteer_activism},
      {'title': 'Inactifs', 'value': _countInactifs, 'icon': Icons.block},
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: cards.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 15,
          mainAxisSpacing: 15,
          childAspectRatio: 2.8,
        ),
        itemBuilder: (context, index) {
          final s = cards[index];
          final color = _getIconColor(s['title'] as String);
          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: color.withOpacity(0.4), width: 1.5),
            ),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(s['icon'] as IconData, size: 26, color: color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${s['value']}',
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        Text(s['title'] as String,
                            style: TextStyle(color: Colors.grey.shade700)),
                      ],
                    ),
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Row(
          children: [
            _buildSideNav(),
            _buildMainArea(),
          ],
        ),
      ),
    );
  }
}


