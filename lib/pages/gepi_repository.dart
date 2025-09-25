// lib/data/gepi_repository.dart
import 'package:gepi/supabase_client.dart';

class GepiRepository {
  Future<List<Map<String, dynamic>>> _select(String table) async {
    final rows = await SB.client.from(table).select();
    return rows.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchEquipements()     => _select('equipements');
  Future<List<Map<String, dynamic>>> fetchMaintenance()     => _select('maintenance');
  Future<List<Map<String, dynamic>>> fetchHse()             => _select('hse');
  Future<List<Map<String, dynamic>>> fetchFournisseurs()    => _select('fournisseurs');
  Future<List<Map<String, dynamic>>> fetchEmplacements()    => _select('emplacements');
  Future<List<Map<String, dynamic>>> fetchStatuts()         => _select('statuts');
  Future<List<Map<String, dynamic>>> fetchInterventions()   => _select('interventions');
  Future<List<Map<String, dynamic>>> fetchUsersOrProfiles() => _select('users'); // ou 'profils'
}
