import 'package:flutter/material.dart';
import 'package:gepi/pages/home_page.dart';
import 'package:gepi/pages/page_login.dart';
import 'package:gepi/services/supabase/auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/supabase_client.dart';

class RedirectionPage extends StatefulWidget {
  const RedirectionPage({super.key});

  @override
  State<RedirectionPage> createState() => _RedirectionPageState();
}

class _RedirectionPageState extends State<RedirectionPage> {
  final _auth = Auth();
  final _sb = SB.client;

  Future<String> _getEffectiveRole(User user) async {
    // 1) rôle des metadata de la session (immédiat)
    final metaRole = user.userMetadata?['role'] as String?;
    String role = metaRole ?? 'visiteur';

    // 2) essaie de lire la BD avec quelques retries courts
    final delaysMs = [0, 300, 800, 1500];
    for (final d in delaysMs) {
      if (d > 0) await Future.delayed(Duration(milliseconds: d));
      try {
        final res = await _sb
            .from('users')
            .select('role')
            .eq('id', user.id)
            .maybeSingle();
        final dbRole = res?['role'] as String?;
        if (dbRole != null && dbRole.isNotEmpty) {
          role = dbRole;
          break;
        }
      } catch (_) {
        // ignore et on retente
      }
    }
    return role;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _auth.authStateChanges,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final session = Supabase.instance.client.auth.currentSession;
        final user = session?.user;

        if (user != null) {
          return FutureBuilder<String>(
            future: _getEffectiveRole(user),
            builder: (context, roleSnap) {
              if (!roleSnap.hasData) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              return MyHomePage(
                title: "Accueil",
                userRole: roleSnap.data!,
              );
            },
          );
        } else {
          return const LoginPage(title: "Connexion");
        }
      },
    );
  }
}
