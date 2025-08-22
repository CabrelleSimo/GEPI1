import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gepi/pages/emplacement_page.dart';
import 'package:gepi/services/firebase/auth.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title, this.userRole});

  final String title;
  final String? userRole;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final User? _user = Auth().currentUser;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _userRole;
  bool _loadingRole = true;
  String? _userEmail;

  String _selectedPage = 'Tableau de bord';

  // NOUVEAUTÉ : Ajout de couleurs spécifiques pour les icônes
  final List<Map<String, dynamic>> _stats = [
    {"title": "Actifs totaux", "value": "100", "icon": Icons.inventory_2, "color": Colors.blue},
    {"title": "En utilisation", "value": "58", "icon": Icons.check_circle, "color": Colors.green},
    {"title": "En maintenance", "value": "3", "icon": Icons.build_circle, "color": Colors.orange},
    {"title": "Prêtés", "value": "3", "icon": Icons.local_shipping, "color": Colors.purple},
    {"title": "Mis au rebut", "value": "3", "icon": Icons.delete, "color": Colors.red},
    // NOUVEAUTÉ : Changement de 'Offerts' à 'Donnés'
    {"title": "Donnés", "value": "3", "icon": Icons.volunteer_activism, "color": Colors.pink},
    {"title": "Inactifs", "value": "3", "icon": Icons.block, "color": Colors.grey},
  ];

  @override
  void initState() {
    super.initState();
    _userEmail = _user?.email;
    if (widget.userRole != null) {
      _userRole = widget.userRole;
      _loadingRole = false;
    } else {
      _fetchUserRole();
    }
  }

  Future<void> _fetchUserRole() async {
    setState(() {
      _loadingRole = true;
    });
    try {
      if (_user != null) {
        final doc = await _firestore.collection('users').doc(_user!.uid).get();
        if (doc.exists) {
          setState(() {
            _userRole = doc.data()?['role'] ?? 'visiteur';
          });
        } else {
          setState(() {
            _userRole = 'visiteur';
          });
        }
      } else {
        setState(() {
          _userRole = 'visiteur';
        });
      }
    } catch (e) {
      setState(() {
        _userRole = 'visiteur';
      });
    } finally {
      setState(() {
        _loadingRole = false;
      });
    }
  }

  final List<Map<String, dynamic>> _menuItems = [
    {"title": "Tableau de bord", "icon": Icons.dashboard},
    {"title": "Équipements", "icon": Icons.devices},
    {"title": "Maintenance", "icon": Icons.build},
    {"title": "HSE", "icon": Icons.shield_outlined},
    {"title": "Fournisseurs", "icon": Icons.store},
    {"title": "Emplacement", "icon": Icons.location_on},
    {"title": "État", "icon": Icons.info},
    {"title": "QR Code", "icon": Icons.qr_code},
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
    setState(() {
      _selectedPage = title;
    });
  }

  void _downloadPdf() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Téléchargement PDF... (fonctionnalité à implémenter)')),
    );
  }

  void _openNotifications() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notifications (placeholder)')),
    );
  }

  void _openProfileMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Mon profil'),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Déconnexion'),
                onTap: () {
                  Navigator.pop(context);
                  Auth().logout();
                },
              ),
            ],
          ),
        );
      },
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
                CircleAvatar(child: const Text('G'), backgroundColor: Colors.blue.shade300),
                const SizedBox(width: 12),
                const Text('GEPI', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                  leading: Icon(item['icon'], color: enabled ? (selected ? Colors.blue : Colors.black54) : Colors.grey),
                  title: Text(
                    item['title'],
                    style: TextStyle(
                      color: enabled ? (selected ? Colors.blue : Colors.black87) : Colors.grey,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  onTap: enabled ? () => _onSelectPage(item['title'] as String) : null,
                  tileColor: selected ? Colors.blue.withOpacity(0.05) : null,
                );
              },
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: _menuItems.length,
            ),
          ),
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
                      Text(
                        _selectedPage,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text('Accueil > $_selectedPage', style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                if (_loadingRole)
                  const SizedBox(width: 200, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                else
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.verified_user, size: 18, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Text('${_userRole ?? 'visiteur'} • ${_userEmail ?? ''}'),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _downloadPdf,
                        icon: const Icon(Icons.download),
                        label: const Text('Télécharger'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: _openNotifications,
                        icon: const Icon(Icons.notifications_none),
                        tooltip: 'Notifications',
                      ),
                      IconButton(
                        onPressed: _openProfileMenu,
                        icon: CircleAvatar(
                          radius: 16,
                          child: Text(
                            (_userEmail != null && _userEmail!.isNotEmpty) ? _userEmail![0].toUpperCase() : 'U',
                          ),
                        ),
                        tooltip: 'Profil',
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Expanded(
            //child: SingleChildScrollView(
              //padding: const EdgeInsets.all(24),
            child: _buildPageContent(),
            //),
          ),
        ],
      ),
    );
  }

  Widget _buildPageContent() {
    switch (_selectedPage) {
      case 'Tableau de bord':
        return _buildDashboard();
      case 'Équipements':
        return _buildPlaceholder(_selectedPage);
      case 'Maintenance':
        return _buildPlaceholder(_selectedPage);
      case 'HSE':
        return _buildPlaceholder(_selectedPage);
      case 'Fournisseurs':
        return _buildPlaceholder(_selectedPage);
      case 'Emplacement':
        return EmplacementPage();
      case 'État':
        return _buildPlaceholder(_selectedPage);
      case 'QR Code':
        return _buildPlaceholder(_selectedPage);
      case 'Gestion des profils':
        return _buildProfilesPage();
      default:
        return _buildPlaceholder(_selectedPage);
    }
  }

  Widget _buildPlaceholder(String title) {
    return SizedBox(
      height: 400,
      child: Center(
        child: Text('$title : page à implémenter', style: TextStyle(fontSize: 18, color: Colors.grey.shade700)),
      ),
    );
  }

  Widget _buildProfilesPage() {
    if (_userRole != 'super-admin') {
      return const SizedBox(
        height: 160,
        child: Center(child: Text("Accès réservé au Super-Admin", style: TextStyle(color: Colors.red))),
      );
    }
    return const SizedBox(
      height: 400,
      child: Center(child: Text("Gestion des profils (Super-Admin)", style: TextStyle(fontSize: 18))),
    );
  }

  Color _getIconColor(String title) {
    final stat = _stats.firstWhere((s) => s['title'] == title, orElse: () => {});
    return stat['color'] ?? Colors.blue;
  }

  Widget _buildDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        /*const Text('Bienvenue sur le tableau de bord', style: TextStyle(fontSize: 16, color: Colors.black54)),
        const SizedBox(height: 18),*/
        // NOUVEAUTÉ : Utilisation de GridView.builder pour une grille fixe
        LayoutBuilder(builder: (context, constraints) {
          int crossAxisCount = 3;
          //if (constraints.maxWidth < 1200) crossAxisCount = 2;
          //if (constraints.maxWidth < 800) crossAxisCount = 1;

          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _stats.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              // NOUVEAUTÉ : Ajustement du childAspectRatio pour un layout plus serré
              childAspectRatio: 2.8, // Augmentation du rapport d'aspect pour des cartes plus courtes
            ),
            itemBuilder: (context, index) {
              final s = _stats[index];
              final iconColor = _getIconColor(s['title']);
              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: iconColor.withOpacity(0.4), width: 1.5),
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
                          color: iconColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(s['icon'] as IconData, size: 26, color: iconColor),
                      ),
                      const SizedBox(width: 14),
                      // NOUVEAUTÉ : Nouvelle disposition du texte pour correspondre à l'image
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(s['value'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            Text(s['title'], style: TextStyle(color: Colors.grey.shade700)),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          );
        }),
      ],
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

