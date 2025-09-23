import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _currentPwdCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  final _newPwd2Ctrl = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentUser;
    _emailCtrl.text = user?.email ?? '';
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _currentPwdCtrl.dispose();
    _newPwdCtrl.dispose();
    _newPwd2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final sb = Supabase.instance.client;
    final user = sb.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expirée, reconnectez-vous."), backgroundColor: Colors.red),
      );
      return;
    }

    final newEmail = _emailCtrl.text.trim().toLowerCase();
    final bool wantEmailChange = newEmail.isNotEmpty && newEmail != (user.email ?? '');
    final newPwd = _newPwdCtrl.text.trim();
    final bool wantPwdChange = newPwd.isNotEmpty;

    if (!wantEmailChange && !wantPwdChange) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Aucune modification à enregistrer.")),
      );
      return;
    }

    // ⚠️ Pour des raisons de sécurité, on redemande le mot de passe actuel avant de modifier email/pwd
    final currentPwd = _currentPwdCtrl.text.trim();
    if (currentPwd.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Entrez votre mot de passe actuel pour confirmer."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final msgs = <String>[];

    try {
      // 1) Réauthentification → évite les erreurs de type "current email/password invalid"
      await sb.auth.signInWithPassword(
        email: user.email!, // on se base sur l'email actuel
        password: currentPwd,
      );

      // 2) Mise à jour email
      if (wantEmailChange) {
        await sb.auth.updateUser(UserAttributes(email: newEmail));
        msgs.add("E-mail mis à jour.");
        // (option) garder public.users en phase côté client si ta policy UPDATE self le permet
        try {
          await sb.from('users').update({'email': newEmail}).eq('id', user.id);
        } catch (_) {}
      }

      // 3) Mise à jour mot de passe
      if (wantPwdChange) {
        await sb.auth.updateUser(UserAttributes(password: newPwd));
        msgs.add("Mot de passe mis à jour.");
      }

      // 4) Rafraîchir la session / l’utilisateur
      try {
        await sb.auth.refreshSession();
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msgs.join(" "))),
      );
      Navigator.pop(context, true); // → signal “changé” à la Home pour refresh
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Email
              Align(
                alignment: Alignment.centerLeft,
                child: Text("E-mail", style: theme.textTheme.titleMedium),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.email),
                  labelText: "Nouvel e-mail (laisser vide pour ne pas changer)",
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return null; // pas de changement
                  final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(value);
                  return ok ? null : "E-mail invalide";
                },
              ),
              const SizedBox(height: 24),

              // Mot de passe
              Align(
                alignment: Alignment.centerLeft,
                child: Text("Mot de passe", style: theme.textTheme.titleMedium),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _newPwdCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.lock),
                  labelText: "Nouveau mot de passe (laisser vide pour ne pas changer)",
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return null;
                  if (value.length < 6) return "Au moins 6 caractères";
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newPwd2Ctrl,
                obscureText: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.lock_outline),
                  labelText: "Confirmation du mot de passe",
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (_newPwdCtrl.text.trim().isEmpty) return null;
                  if (value != _newPwdCtrl.text.trim()) return "Les mots de passe ne correspondent pas";
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Mot de passe actuel (obligatoire si on change qqch)
              Align(
                alignment: Alignment.centerLeft,
                child: Text("Confirmation", style: theme.textTheme.titleMedium),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _currentPwdCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.verified_user),
                  labelText: "Mot de passe actuel (requis pour valider)",
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: Text(_saving ? "Enregistrement..." : "Enregistrer"),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),

              const SizedBox(height: 8),
              const Text(
                "Note : si la confirmation d’e-mail est activée, un lien de confirmation est envoyé à la nouvelle adresse.",
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
