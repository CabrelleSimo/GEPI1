import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/pages/redirection_page.dart';
import 'package:gepi/supabase_client.dart';
//import 'package:supabase_flutter/supabase_flutter.dart';
//import 'package:gepi/pages/redirection_page.dart';

Future<void> logoutAndGoHome(BuildContext context) async {
  await Supabase.instance.client.auth.signOut();
  if (context.mounted) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RedirectionPage()),
      (route) => false,
    );
  }
}



Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Supabase.initialize(
    url: SB.url,
    anonKey: SB.anonKey,
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 10),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GEPI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const RedirectionPage(),
    );
  }
}


