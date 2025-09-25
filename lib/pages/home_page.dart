import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gepi/pages/gestion_acces_page.dart';
import 'package:gepi/pages/pdf_exporter.dart';
import 'package:intl/intl.dart';
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
import 'package:gepi/pages/pdf_exporter.dart';
import 'package:gepi/pages/gepi_repository.dart';
import 'package:provider/provider.dart';


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
    // ex. avec Provider



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
  // Dans ton widget (State), ajoute un flag si tu veux désactiver le bouton pendant l’export
bool _exportingAll = false;

Future<void> _onDownloadAllPressed(BuildContext context) async {
  if (_exportingAll) return;
  setState(() => _exportingAll = true);

  // Petit modal de progression pour éviter l’impression de “freeze”
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => WillPopScope(
      onWillPop: () async => false,
      child: const Dialog(
        insetPadding: EdgeInsets.all(24),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text('Préparation du PDF…'),
            ],
          ),
        ),
      ),
    ),
  );

  try {
    // 1) Charger les données en parallèle (remplace par tes vraies sources)
    final repo = context.read<GepiRepository>();
    final results = await Future.wait([
      
      repo.fetchEquipements(),
      repo.fetchMaintenance(),
      repo.fetchHse(),
      repo.fetchFournisseurs(),
      repo.fetchEmplacements(),
      repo.fetchStatuts(),
      repo.fetchInterventions(),
      repo.fetchUsersOrProfiles(),
    ]).timeout(const Duration(seconds: 60)); // anti-blocage réseau

    final equipementsItems    = results[0] as List<Map<String, dynamic>>;
    final maintenanceItems    = results[1] as List<Map<String, dynamic>>;
    final hseItems            = results[2] as List<Map<String, dynamic>>;
    final fournisseursItems   = results[3] as List<Map<String, dynamic>>;
    final emplacementsItems   = results[4] as List<Map<String, dynamic>>;
    final statutsItems        = results[5] as List<Map<String, dynamic>>;
    final interventionsItems  = results[6] as List<Map<String, dynamic>>;
    final profilsItems        = results[7] as List<Map<String, dynamic>>;

    // 2) Construire les sections
    final sections = [
      buildEquipementsSection(items: equipementsItems,   subtitle: 'Tous'),
      buildMaintenanceSection(items: maintenanceItems,   subtitle: 'Tous'),
      buildHseSection(items: hseItems,                   subtitle: 'Tous'),
      buildFournisseursSection(items: fournisseursItems, subtitle: 'Tous'),
      buildEmplacementsSection(items: emplacementsItems, subtitle: 'Tous'),
      buildStatutsSection(items: statutsItems,           subtitle: 'Tous'),
      buildInterventionsSection(items: interventionsItems, subtitle: 'Tous'),
      buildProfilsSection(items: profilsItems,           subtitle: 'Tous'),
    ];

    // 3) Fermer le modal AVANT d’ouvrir la boîte de dialogue navigateur
    if (context.mounted) Navigator.of(context).pop();

    // 4) Lancer l’export (layoutPdf sur Web pour éviter le blocage)
    await PdfExporter.exportAllPages(
      globalTitle: 'Rapport GEPI - Export global',
      sections: sections,
      preferPrintDialogOnWeb: true,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export terminé.')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context).pop(); // fermer le modal si ouvert
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export échoué : $e')),
      );
    }
  } finally {
    if (mounted) setState(() => _exportingAll = false);
  }
}
//stop
  // Utils de mise en forme (tu peux les mettre près de PdfExporter)
String _fmtDate(dynamic d) {
  if (d == null) return '';
  // Support DateTime, String (ISO) ou int (epoch)
  if (d is DateTime) return DateFormat('yyyy-MM-dd').format(d);
  if (d is int) return DateFormat('yyyy-MM-dd')
      .format(DateTime.fromMillisecondsSinceEpoch(d));
  // string
  return d.toString().split('T').first;
}
String _s(dynamic v) => v == null ? '' : v.toString();

/// =============== ÉQUIPEMENTS (déjà vu en exemple, je le laisse au complet)
PdfSectionData buildEquipementsSection({
  required List<Map<String, dynamic>> items,
  String? subtitle,
}) {
  final headers = [
    'État','N° série','Modèle','Marque','Host name','Type','Statut',
    'Emplacement','Date achat','Attribué à','Dernière modif',
  ];

  final rows = items.map((e) => [
    _s(e['etat']),
    _s(e['numero_serie'] ?? e['num_serie'] ?? e['serial']),
    _s(e['modele'] ?? e['model']),
    _s(e['marque'] ?? e['brand']),
    _s(e['hostname'] ?? e['host_name']),
    _s(e['type']),
    _s(e['statut']),
    _s(e['emplacement'] ?? e['location']),
    _fmtDate(e['date_achat'] ?? e['purchase_date']),
    _s(e['attribue_a'] ?? e['assigned_to']),
    _fmtDate(e['updated_at']),
  ]).toList();

  return PdfSectionData(
    title: 'Équipements',
    headers: headers,
    rows: rows,
    subtitle: subtitle,
    landscape: true,
  );
}

/// =============== MAINTENANCE
PdfSectionData buildMaintenanceSection({
  required List<Map<String, dynamic>> items,
  String? subtitle,
}) {
  final headers = [
    'Réf', 'Équipement', 'Type', 'Priorité', 'Statut',
    'Ouverture', 'Échéance', 'Technicien', 'Coût',
  ];
  final rows = items.map((m) => [
    _s(m['ref'] ?? m['code'] ?? m['id']),
    _s(m['equipement'] ?? m['asset'] ?? m['asset_name']),
    _s(m['type'] ?? m['maintenance_type']),
    _s(m['priorite'] ?? m['priority']),
    _s(m['statut'] ?? m['status']),
    _fmtDate(m['date_ouverture'] ?? m['opened_at'] ?? m['created_at']),
    _fmtDate(m['echeance'] ?? m['due_date']),
    _s(m['technicien'] ?? m['assigne_a'] ?? m['assignee']),
    _s(m['cout'] ?? m['cost']),
  ]).toList();

  return PdfSectionData(
    title: 'Maintenance',
    headers: headers,
    rows: rows,
    subtitle: subtitle,
    landscape: false,
  );
}

/// =============== HSE (Hygiène, Sécurité, Environnement)
PdfSectionData buildHseSection({
  required List<Map<String, dynamic>> items,
  String? subtitle,
}) {
  final headers = [
    'N°', 'Type', 'Gravité', 'Statut', 'Site/Zone',
    'Déclaré le', 'Clôturé le', 'Responsable',
  ];
  final rows = items.map((h) => [
    _s(h['numero'] ?? h['id']),
    _s(h['type']),
    _s(h['gravite'] ?? h['severity']),
    _s(h['statut'] ?? h['status']),
    _s(h['zone'] ?? h['site'] ?? h['emplacement']),
    _fmtDate(h['date_declaration'] ?? h['declared_at'] ?? h['created_at']),
    _fmtDate(h['date_cloture'] ?? h['closed_at']),
    _s(h['responsable'] ?? h['assignee']),
  ]).toList();

  return PdfSectionData(
    title: 'HSE',
    headers: headers,
    rows: rows,
    subtitle: subtitle,
  );
}

/// =============== FOURNISSEURS
PdfSectionData buildFournisseursSection({
  required List<Map<String, dynamic>> items,
  String? subtitle,
}) {
  final headers = [
    'Nom', 'Catégorie', 'Contact', 'Email', 'Téléphone', 'Adresse', 'Pays',
    'Dernière commande',
  ];
  final rows = items.map((f) => [
    _s(f['nom'] ?? f['name']),
    _s(f['categorie'] ?? f['category']),
    _s(f['contact'] ?? f['contact_name']),
    _s(f['email']),
    _s(f['telephone'] ?? f['phone']),
    _s(f['adresse'] ?? f['address']),
    _s(f['pays'] ?? f['country']),
    _fmtDate(f['last_order_at'] ?? f['derniere_commande']),
  ]).toList();

  return PdfSectionData(
    title: 'Fournisseurs',
    headers: headers,
    rows: rows,
    subtitle: subtitle,
  );
}

/// =============== EMPLACEMENTS
PdfSectionData buildEmplacementsSection({
  required List<Map<String, dynamic>> items,
  String? subtitle,
}) {
  final headers = [
    'Code', 'Nom', 'Site', 'Bâtiment', 'Étage', 'Salle', 'Capacité', 'Responsable',
  ];
  final rows = items.map((l) => [
    _s(l['code']),
    _s(l['nom'] ?? l['name']),
    _s(l['site']),
    _s(l['batiment'] ?? l['building']),
    _s(l['etage'] ?? l['floor']),
    _s(l['salle'] ?? l['room']),
    _s(l['capacite'] ?? l['capacity']),
    _s(l['responsable'] ?? l['manager']),
  ]).toList();

  return PdfSectionData(
    title: 'Emplacements',
    headers: headers,
    rows: rows,
    subtitle: subtitle,
  );
}

/// =============== STATUTS (catalogue des statuts d’équipements/interventions)
PdfSectionData buildStatutsSection({
  required List<Map<String, dynamic>> items,
  String? subtitle,
}) {
  final headers = ['Code', 'Libellé', 'Description', 'Actif', 'Dernière modif'];
  final rows = items.map((s) => [
    _s(s['code']),
    _s(s['libelle'] ?? s['label'] ?? s['name']),
    _s(s['description'] ?? s['desc']),
    _s((s['actif'] ?? s['active']) == true ? 'Oui' : 'Non'),
    _fmtDate(s['updated_at']),
  ]).toList();

  return PdfSectionData(
    title: 'Statuts',
    headers: headers,
    rows: rows,
    subtitle: subtitle,
  );
}

/// =============== INTERVENTIONS (tickets / ordres de travail)
PdfSectionData buildInterventionsSection({
  required List<Map<String, dynamic>> items,
  String? subtitle,
}) {
  final headers = [
    'N°', 'Équipement', 'Type', 'Priorité', 'Statut',
    'Ouverture', 'Début', 'Fin', 'Durée (h)', 'Technicien',
  ];
  final rows = items.map((t) {
    final start = t['date_debut'] ?? t['start_at'];
    final end   = t['date_fin'] ?? t['end_at'];
    double? hours;
    try {
      if (start != null && end != null) {
        final s = start is DateTime ? start : DateTime.parse(start.toString());
        final e = end   is DateTime ? end   : DateTime.parse(end.toString());
        hours = e.difference(s).inMinutes / 60.0;
      }
    } catch (_) {}
    return [
      _s(t['numero'] ?? t['id']),
      _s(t['equipement'] ?? t['asset']),
      _s(t['type']),
      _s(t['priorite'] ?? t['priority']),
      _s(t['statut'] ?? t['status']),
      _fmtDate(t['created_at'] ?? t['ouverture']),
      _fmtDate(start),
      _fmtDate(end),
      hours == null ? '' : hours.toStringAsFixed(2),
      _s(t['technicien'] ?? t['assignee']),
    ];
  }).toList();

  return PdfSectionData(
    title: 'Interventions',
    headers: headers,
    rows: rows,
    subtitle: subtitle,
    landscape: true,
  );
}

/// =============== GESTION DES PROFILS / UTILISATEURS
PdfSectionData buildProfilsSection({
  required List<Map<String, dynamic>> items,
  String? subtitle,
}) {
  final headers = [
    'Nom', 'Email', 'Rôle', 'Actif', 'Dernière connexion', 'Créé le',
  ];
  final rows = items.map((u) => [
    _s(u['nom'] ?? u['name']),
    _s(u['email']),
    _s(u['role']),
    _s((u['actif'] ?? u['active'] ?? u['is_active']) == true ? 'Oui' : 'Non'),
    _fmtDate(u['last_sign_in_at'] ?? u['derniere_connexion']),
    _fmtDate(u['created_at']),
  ]).toList();

  return PdfSectionData(
    title: 'Gestion des profils',
    headers: headers,
    rows: rows,
    subtitle: subtitle,
  );
}

  /*Future<PdfSectionData> _buildEquipementsSection() async {
  // Récupère tes données (depuis Supabase ou provider)
  // final items = await repo.fetchEquipements(...);

  final headers = [
    'État', 'N° série', 'Modèle', 'Marque', 'Host name', 'Type', 'Statut',
    'Emplacement', 'Date achat', 'Attribué à', 'Dernière modif',
  ];

  final rows = <List<String>>[
    // items.map((e) => [
    //   e.etat, e.numeroSerie, e.modele, e.marque, e.host, e.type, e.statut,
    //   e.emplacement, fmt(e.dateAchat), e.attribueA, fmt(e.updatedAt),
    // ]).toList();
  ];

  return PdfSectionData(
    title: 'Équipements',
    subtitle: 'Tous', // ou ton filtre actif
    headers: headers,
    rows: rows,
    landscape: true,  // utile pour les tableaux larges
  );
}*/


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
    {"title": "Lecteur code barre", "icon": Icons.qr_code_scanner},
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
  Future<void> _openProfileDialog() async {
  final user = _sb.auth.currentUser;
  if (user == null) return;

  final formKey = GlobalKey<FormState>();
  final emailCtrl = TextEditingController(text: user.email ?? '');
  final pwdCtrl   = TextEditingController();
  final pwd2Ctrl  = TextEditingController();

  String? infoMsg; // pour petits tips (ex: confirmation email)

  await showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setS) {
        return AlertDialog(
          title: const Text('Mon profil'),
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
                      labelText: 'Nouveau mot de passe (optionnel)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: pwd2Ctrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirmer le mot de passe',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (v) {
                      if (pwdCtrl.text.trim().isEmpty) return null; // pas de changement
                      if (v != pwdCtrl.text) return 'Les mots de passe ne correspondent pas';
                      if (pwdCtrl.text.length < 6) return '6 caractères minimum';
                      return null;
                    },
                  ),
                  if (infoMsg != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.info_outline, size: 18, color: Colors.blueGrey),
                        const SizedBox(width: 8),
                        Expanded(child: Text(infoMsg!, style: TextStyle(color: Colors.blueGrey.shade700))),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
            ElevatedButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;

                final newEmail = emailCtrl.text.trim();
                final changePwd = pwdCtrl.text.trim().isNotEmpty;

                try {
                  // on peut tout envoyer en une seule fois
                  final attrs = UserAttributes(
                    email: (newEmail != user.email) ? newEmail : null,
                    password: changePwd ? pwdCtrl.text : null,
                  );

                  if (attrs.email == null && attrs.password == null) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Aucune modification.')),
                      );
                    }
                    return;
                  }

                  final res = await _sb.auth.updateUser(attrs);

                  // Si email changé, Supabase peut envoyer un lien de confirmation
                  if (attrs.email != null) {
                    setS(() => infoMsg =
                      "Un email de confirmation a pu vous être envoyé. "
                      "Vous devrez peut-être vous reconnecter après validation.");
                  }

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Profil mis à jour.')),
                    );
                  }

                  // Si l’email a changé, on met à jour l’affichage de l’en-tête
                  if (mounted) {
                    setState(() => _userEmail = res.user?.email ?? newEmail);
                  }

                  if (!mounted) return;
                  Navigator.pop(ctx);
                } on AuthException catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.message), backgroundColor: Colors.red),
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
              child: const Text('Enregistrer'),
            ),
          ],
        );
      });
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
                      /*IconButton(
                        icon: Icon(Icons.download, color: Colors.blue.shade700),
                        tooltip: 'Exporter (bientôt)',
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Fonction export à venir.'),
                            ),
                          );
                        },
                      ),*/
                      ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Télécharger toutes les pages à implémenter'),
                            ),
                          );
                        },
  //onPressed: _exportingAll ? null : () => _onDownloadAllPressed(context),
  icon: const Icon(Icons.download),
  label: const Text('Télécharger tout'),
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.blue.shade700,
  ),
),

                      /*IconButton(
  tooltip: 'Télécharger toutes les pages',
  onPressed: () async {
  final repo = context.read<GepiRepository>();
    // 1) Récupère / dispose des données de CHAQUE page
final equipementsItems    = await repo.fetchEquipements();     // List<Map<String,dynamic>>
final maintenanceItems    = await repo.fetchMaintenance();
final hseItems            = await repo.fetchHse();
final fournisseursItems   = await repo.fetchFournisseurs();
final emplacementsItems   = await repo.fetchEmplacements();
final statutsItems        = await repo.fetchStatuts();
final interventionsItems  = await repo.fetchInterventions();
final profilsItems        = await repo.fetchUsersOrProfiles();

// 2) Construit les sections PDF (appel correct des builders)
final equipements   = buildEquipementsSection(items: equipementsItems, subtitle: 'Tous');
final maintenance   = buildMaintenanceSection(items: maintenanceItems, subtitle: 'Tous');
final hse           = buildHseSection(items: hseItems, subtitle: 'Tous');
final fournisseurs  = buildFournisseursSection(items: fournisseursItems, subtitle: 'Tous');
final emplacements  = buildEmplacementsSection(items: emplacementsItems, subtitle: 'Tous');
final statuts       = buildStatutsSection(items: statutsItems, subtitle: 'Tous');
final interventions = buildInterventionsSection(items: interventionsItems, subtitle: 'Tous');
final profils       = buildProfilsSection(items: profilsItems, subtitle: 'Tous');

// 3) Export global
await PdfExporter.exportAllPages(
  globalTitle: 'Rapport GEPI',
  sections: [
    equipements,
    maintenance,
    hse,
    fournisseurs,
    emplacements,
    statuts,
    interventions,
    profils,
  ],
);

    // ... ajoute les autres sections si besoin
    

    // 2) Appel unique qui assemble tout dans un seul PDF
    await PdfExporter.exportAllPages(
      globalTitle: 'Rapport GEPI - Export global',
      sections: [
        equipements,
        maintenance,
        hse,
        fournisseurs,
        emplacements,
        statuts,
        interventions,
        profils,
      ],
    );
  },
  icon: const Icon(Icons.download, color: Colors.blue),
),*/

                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.notifications),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Fonction notifications à venir.'),
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
                        /*onSelected: (value) async {
                          switch (value) {
                            case 'profile':
                              // TODO: ouvre ta page "Gestion des profils" ou un dialog
                              _onSelectPage('Gestion des profils');
                              break;
                            case 'logout':
                              await _logoutAndGoHome();
                              break;
                          }
                        },*/
                        onSelected: (value) async {
  switch (value) {
    case 'profile':
      await _openProfileDialog(); // ← au lieu d’ouvrir “Gestion des profils”
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
      case 'Lecteur code barre':
        return _buildPlaceholder(_selectedPage);
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


