/*
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/services/supabase/auth.dart';
import 'package:gepi/pages/home_page.dart';
import 'package:gepi/supabase_client.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.title});
  final String title;

  @override
  State<LoginPage> createState() => LoginPageState();
}

class LoginPageState extends State<LoginPage> {
  final formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final passwordConfirmController = TextEditingController();

  bool isLoading = false;
  bool forLogin = true;
  bool obscureText = true;

  String? _selectedRole;
  final List<String> _roles = ['visiteur', 'technicien', 'super-admin'];

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    passwordConfirmController.dispose();
    super.dispose();
  }

  Future<void> _goHomeWithRole(String fallbackRole) async {
    final sb = SB.client;
    final user = sb.auth.currentUser;
    String role = fallbackRole;

    // 1) d’abord le rôle des metadata (immédiat, côté session)
    final metaRole = user!.userMetadata?['role'] as String?;
    if (metaRole != null && metaRole.isNotEmpty) {
      role = metaRole;
    }

    // 2) on tente de lire la BD (plus fiable) avec quelques retries courts
    if (user != null) {
      final delaysMs = [0, 300, 800, 1500]; // total ~2.6s max
      for (final d in delaysMs) {
        if (d > 0) await Future.delayed(Duration(milliseconds: d));
        try {
          final row = await sb
              .from('users')
              .select('role')
              .eq('id', user.id)
              .maybeSingle();
          final dbRole = row?['role'] as String?;
          if (dbRole != null && dbRole.isNotEmpty) {
            role = dbRole;
            break;
          }
        } catch (_) {
          // ignore et on retente
        }
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MyHomePage(title: "Page d'accueil", userRole: role),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(forLogin ? widget.title : "S'inscrire")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: formKey,
          child: Column(
            children: <Widget>[
              TextFormField(
                controller: emailController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.email),
                  labelText: "Email",
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Adresse e-mail requise' : null,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: passwordController,
                obscureText: obscureText,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock),
                  labelText: "Mot de passe",
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(obscureText ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => obscureText = !obscureText),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Mot de passe requis';
                  if (v.length < 6) return '6 caractères minimum';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              if (!forLogin) ...[
                TextFormField(
                  controller: passwordConfirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.lock),
                    labelText: "Confirmation du mot de passe",
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Confirmation requise';
                    if (v != passwordController.text) return 'Les mots de passe ne correspondent pas';
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Rôle',
                    border: OutlineInputBorder(),
                  ),
                  value: _selectedRole,
                  hint: const Text('Sélectionner un rôle'),
                  onChanged: (s) => setState(() => _selectedRole = s),
                  validator: (v) => (v == null) ? 'Le rôle est requis' : null,
                  items: _roles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                ),
              ],
              Container(
                margin: const EdgeInsets.only(top: 30, bottom: 20),
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          setState(() => isLoading = true);
                          if (!formKey.currentState!.validate()) {
                            setState(() => isLoading = false);
                            return;
                          }
                          try {
                            if (forLogin) {
                              // ====== Connexion ======
                              final userData = await Auth().loginWithEmailAndPassword(
                                emailController.text.trim(),
                                passwordController.text,
                              );
                              if (!mounted) return;
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => MyHomePage(
                                    title: "Page d'accueil",
                                    userRole: userData['role'] as String,
                                  ),
                                ),
                              );
                            } else {
                              // ====== Inscription (sans confirmation e-mail) ======
                              final role = _selectedRole!;
                              await Auth().createUserWithEmailAndPassword(
                                emailController.text.trim(),
                                passwordController.text,
                                role,
                              );

                              // On part tout de suite à l’accueil avec meta->role, puis BD dès prête.
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Compte créé et connecté."),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: Colors.green,
                                  showCloseIcon: true,
                                ),
                              );

                              await _goHomeWithRole(role);
                            }
                          } on AuthException catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(e.message),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: Colors.red,
                                  showCloseIcon: true,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("Une erreur s'est produite : $e"),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: Colors.red,
                                  showCloseIcon: true,
                                ),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => isLoading = false);
                          }
                        },
                  child: isLoading
                      ? const CircularProgressIndicator()
                      : Text(forLogin ? "Se connecter" : "S'inscrire"),
                ),
              ),
              TextButton(
                onPressed: () {
                  emailController.clear();
                  passwordController.clear();
                  passwordConfirmController.clear();
                  setState(() => forLogin = !forLogin);
                },
                child: Text(
                  forLogin ? "Je n'ai pas de compte — s'inscrire"
                           : "J'ai déjà un compte — se connecter",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
*/
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gepi/pages/home_page.dart';
import 'package:gepi/supabase_client.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.title});
  final String title;

  @override
  State<LoginPage> createState() => LoginPageState();
}

class LoginPageState extends State<LoginPage> {
  final formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final passwordConfirmController = TextEditingController();

  bool isLoading = false;
  bool forLogin = true;
  bool obscureText = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    passwordConfirmController.dispose();
    super.dispose();
  }

  Future<void> _goHomeWithRole(String fallbackRole) async {
    final sb = SB.client;
    final user = sb.auth.currentUser;
    String role = fallbackRole;

    // 1) rôle via metadata si déjà présent
    final metaRole = user?.userMetadata?['role'] as String?;
    if (metaRole != null && metaRole.isNotEmpty) {
      role = metaRole;
    }

    // 2) essaie d’aller lire la BD (plus fiable)
    if (user != null) {
      final delaysMs = [0, 300, 800, 1500];
      for (final d in delaysMs) {
        if (d > 0) await Future.delayed(Duration(milliseconds: d));
        try {
          final row =
              await sb.from('users').select('role').eq('id', user.id).maybeSingle();
          final dbRole = row?['role'] as String?;
          if (dbRole != null && dbRole.isNotEmpty) {
            role = dbRole;
            break;
          }
        } catch (_) {}
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MyHomePage(title: "Page d'accueil", userRole: role),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(forLogin ? widget.title : "S'inscrire")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: formKey,
          child: Column(
            children: <Widget>[
              TextFormField(
                controller: emailController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.email),
                  labelText: "Email",
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Adresse e-mail requise' : null,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: passwordController,
                obscureText: obscureText,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock),
                  labelText: "Mot de passe",
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(obscureText ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => obscureText = !obscureText),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Mot de passe requis';
                  if (v.length < 6) return '6 caractères minimum';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // En mode inscription, juste confirmation de mot de passe (plus de choix de rôle)
              if (!forLogin) ...[
                TextFormField(
                  controller: passwordConfirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.lock),
                    labelText: "Confirmation du mot de passe",
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Confirmation requise';
                    if (v != passwordController.text) {
                      return 'Les mots de passe ne correspondent pas';
                    }
                    return null;
                  },
                ),
              ],

              Container(
                margin: const EdgeInsets.only(top: 30, bottom: 20),
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          setState(() => isLoading = true);
                          if (!formKey.currentState!.validate()) {
                            setState(() => isLoading = false);
                            return;
                          }
                          try {
                            if (forLogin) {
                              // ====== Connexion ======
                              final res = await SB.client.auth.signInWithPassword(
                                email: emailController.text.trim(),
                                password: passwordController.text,
                              );
                              if (res.session == null) {
                                throw const AuthException('Échec de connexion');
                              }
                              await _goHomeWithRole('visiteur'); // fallback
                            } else {
                              // ====== Inscription — autorisée seulement si "invité" ======
                              final res = await SB.client.auth.signUp(
                                email: emailController.text.trim(),
                                password: passwordController.text,
                                // si tu utilises email confirmation, pense à gérer le retour
                              );
                              if (res.session == null && res.user == null) {
                                throw const AuthException(
                                    'Inscription échouée (vérifiez votre email).');
                              }

                              // Si le trigger a refusé (pas invité), Supabase renvoie une erreur Auth/DB
                              // qui sera catch ci-dessous.

                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Compte créé et connecté."),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: Colors.green,
                                  showCloseIcon: true,
                                ),
                              );
                              await _goHomeWithRole('visiteur'); // fallback
                            }
                          } on AuthException catch (e) {
                            if (mounted) {
                              // le trigger "Inscription refusée..." apparaît ici
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(e.message),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: Colors.red,
                                  showCloseIcon: true,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("Une erreur s'est produite : $e"),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: Colors.red,
                                  showCloseIcon: true,
                                ),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => isLoading = false);
                          }
                        },
                  child: isLoading
                      ? const CircularProgressIndicator()
                      : Text(forLogin ? "Se connecter" : "S'inscrire"),
                ),
              ),
              TextButton(
                onPressed: () {
                  emailController.clear();
                  passwordController.clear();
                  passwordConfirmController.clear();
                  setState(() => forLogin = !forLogin);
                },
                child: Text(
                  forLogin
                      ? "Je n'ai pas de compte — s'inscrire"
                      : "J'ai déjà un compte — se connecter",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
