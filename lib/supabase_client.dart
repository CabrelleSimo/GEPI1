import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SB {
  static SupabaseClient get client => Supabase.instance.client;
  static String get url => dotenv.env['SUPABASE_URL']!;
  static String get anonKey => dotenv.env['SUPABASE_ANON_KEY']!;
}
