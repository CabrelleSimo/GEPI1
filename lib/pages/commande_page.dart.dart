/*import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/supabase_client.dart';

class CommandePage extends StatefulWidget {
  const CommandePage({super.key});
  @override
  State<CommandePage> createState() => _CommandePageState();
}
class CommandePageState extends State<CommandePage> {
  final _sb = SB.client;

  String? _role;
  List<Map<String, dynamic>> _data = [];
  bool _isLoading = true;
  String _searchText = '';
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchRoleAndData();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searchText = _searchCtrl.text;
        _isLoading = true;
      });
      _fetchData();
    });
  }

  Future<void> _fetchRoleAndData() async {
    final user = _sb.auth.currentUser;
    if (user != null) {
      final row = await _sb.from('users').select('role').eq('id', user.id).maybeSingle();
      setState(() {
        _role = row?['role'] as String?;
      });
      await _fetchData();
    }
  }

  Future<void> _fetchData() async {
    try {
      final query = _sb.from('commandes').select().order('date_commande', ascending: false);
      if (_searchText.isNotEmpty) {
        query.ilike('description', '%$_searchText%');
      }
      final results = await query.execute();
      if (results.error == null) {
        setState(() {
          _data = List<Map<String, dynamic>>.from(results.data as List);
          _isLoading = false;
        });
      } else {
        throw results.error!;
      }
    } catch (e) {
      setState(() {
        _data = [];
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur lors du chargement des données: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Commandes')),
      body: Column(
        children: [],))
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Rechercher',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchCtrl.clear();
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _data.isEmpty
                    ? const Center(child: Text('Aucune donnée trouvée'))
                    : ListView.builder(
                        itemCount: _data.length,
                        itemBuilder: (context, index) {
                          final item = _data[index];
                          return ListTile(
                            title: Text(item['description'] ?? 'Sans description'),
                            subtitle: Text('Date: ${item['date_commande'] ?? 'Inconnue'} - Montant: ${item['montant'] ?? 'N/A'}'),
                          );
                        },
                      ),
          ),
        ],
  ),
      floatingActionButton: _role == 'admin'
          ? FloatingActionButton(
              onPressed: () {
                _showAddCommandeDialog();
              },
              child: const Icon(Icons.add),
            )
          : null,
          );
  }
  
*/