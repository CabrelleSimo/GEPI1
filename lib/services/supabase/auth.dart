import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/supabase_client.dart';

/// Service d'auth Supabase (remplace Firebase Auth)
class Auth {
  final _sb = SB.client;

  /// Utilisateur actuellement connecté
  User? get currentUser => _sb.auth.currentUser;

  /// Flux d'état d'auth (équivalent authStateChanges Firebase)
  Stream<AuthState> get authStateChanges => _sb.auth.onAuthStateChange;

  /// Connexion email / mot de passe
  /// Retourne { 'user': User, 'role': String }
  Future<Map<String, dynamic>> loginWithEmailAndPassword(
    String email,
    String password,
  ) async {
    final res = await _sb.auth.signInWithPassword(
      email: email,
      password: password,
    );

    final user = res.user;
    if (user == null) {
      throw AuthException('Échec de la connexion');
    }

    // Récupère le rôle depuis la table applicative public.users
    final row = await _sb
        .from('users')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();

    if (row == null || row['role'] == null) {
      // Si tu préfères un fallback: remplace par 'visiteur'
      // return {'user': user, 'role': 'visiteur'};
      throw AuthException(
        "Aucun rôle n'est défini pour cet utilisateur. "
        "Assure-toi que la ligne existe dans public.users (trigger) ou que tu as bien complété l'inscription.",
      );
    }

    return {
      'user': user,
      'role': row['role'],
    };
  }

  /// Déconnexion
  Future<void> logout() async {
    await _sb.auth.signOut();
  }

  /// Inscription avec rôle
  ///
  /// - Passe le rôle dans `data` (metadata) pour que le TRIGGER serveur puisse créer la ligne public.users.
  /// - Si une session est créée immédiatement (confirmation e-mail désactivée),
  ///   on s'assure que la ligne existe (INSERT si besoin).
  /// - Si confirmation e-mail activée: pas d'INSERT client (évite l'erreur RLS) ;
  ///   la ligne sera créée par le trigger après validation de l'e-mail.
  Future<void> createUserWithEmailAndPassword(
    String email,
    String password,
    String role,
  ) async {
    final res = await _sb.auth.signUp(
      email: email,
      password: password,
      data: {'role': role}, // <-- IMPORTANT: pour le trigger côté serveur
      // emailRedirectTo: 'myapp://callback', // optionnel si tu utilises deep link
    );

    // Si la confirmation e-mail est activée, il est normal que `session` soit null.
    // Dans ce cas: NE PAS tenter d'insérer dans public.users côté client (RLS bloquerait).
    final user = res.user;
    final session = res.session;

    if (user == null) {
      // Cas rare: signup a échoué sans lever d'exception explicite
      throw AuthException("Inscription échouée");
    }

    // Si on a une session immédiate (confirmation désactivée), on peut créer/compléter la ligne côté client.
    if (session != null) {
      await _ensureAppUserRow(user.id, email, role);
    }
    // Sinon, on ne fait rien ici : le TRIGGER `handle_new_user` s'en chargera
    // dès que Supabase créera l'entrée dans auth.users (après confirmation).
  }

  /// Crée la ligne dans `public.users` si elle n'existe pas (dev sans trigger / sans confirm email).
  Future<void> _ensureAppUserRow(String id, String email, String role) async {
    final existing =
        await _sb.from('users').select('id').eq('id', id).maybeSingle();
    if (existing != null) return;

    try {
      await _sb.from('users').insert({
        'id': id,
        'email': email,
        'role': role,
      });
    } catch (e) {
      // En cas de RLS (ex: policies restrictives), on ignore :
      // - soit tu relies le flow au trigger (recommandé),
      // - soit tu ajustes ta policy INSERT (to authenticated with check auth.uid() = id).
      // print('users insert blocked by RLS: $e');
    }
  }
}
