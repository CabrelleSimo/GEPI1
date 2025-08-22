import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gepi/services/firebase/auth.dart';
import 'package:gepi/pages/home_page.dart'; // NOUVEAUTÉ : Import de la page d'accueil

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

  // NOUVEAUTÉ : Variables pour la gestion des rôles
  String? _selectedRole;
  final List<String> _roles = ['visiteur', 'technicien', 'super-admin'];

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    passwordConfirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(forLogin ? widget.title : "s'inscrire"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              TextFormField(
                controller: emailController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.email),
                  labelText: "Email",
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Adresse e-mail requise';
                  } else {
                    return null;
                  }
                },
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
                    icon: Icon(
                      obscureText ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        obscureText = !obscureText;
                      });
                    },
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Mot de passe requis';
                  } else {
                    return null;
                  }
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
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'La confirmation du mot de passe est requise';
                    } else if (value != passwordController.text) {
                      return 'Les deux mots de passe ne correspondent pas!';
                    } else {
                      return null;
                    }
                  },
                ),
                const SizedBox(height: 20),
                // NOUVEAUTÉ : Le sélecteur de rôle
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Rôle',
                    border: OutlineInputBorder(),
                  ),
                  value: _selectedRole,
                  hint: const Text('Sélectionner un rôle'),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedRole = newValue;
                    });
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Le rôle est requis';
                    }
                    return null;
                  },
                  items: _roles.map((String role) {
                    return DropdownMenuItem<String>(
                      value: role,
                      child: Text(role),
                    );
                  }).toList(),
                ),
              ],
              Container(
                margin: const EdgeInsets.only(top: 30, bottom: 20),
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    setState(() {
                      isLoading = true;
                    });
                    if (formKey.currentState!.validate()) {
                      try {
                        if (forLogin) {
                          // NOUVEAUTÉ : Récupération du rôle après la connexion
                          final userData = await Auth().loginWithEmailAndPassword(
                            emailController.text,
                            passwordController.text,
                          );
                          if (userData != null) {
                            Navigator.of(context).pushReplacement(
  MaterialPageRoute(
    builder: (context) => MyHomePage(
      title: "Page d'accueil",
      userRole: userData['role'],
    ),
  ),
);

                          }
                        } else {
                          // NOUVEAUTÉ : Passer le rôle à la création de l'utilisateur
                          if (_selectedRole != null) {
                            await Auth().createUserWithEmailAndPassword(
                              emailController.text,
                              passwordController.text,
                              _selectedRole!,
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Inscription réussie, veuillez vous connecter."),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: Colors.green,
                                showCloseIcon: true,
                              ),
                            );
                            setState(() {
                              forLogin = true;
                              _selectedRole = null;
                            });
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Veuillez sélectionner un rôle."),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: Colors.red,
                                showCloseIcon: true,
                              ),
                            );
                          }
                        }
                      } on FirebaseAuthException catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("${e.message}"),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: Colors.red,
                            showCloseIcon: true,
                          ),
                        );
                      } catch (e) {
                         ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("Une erreur s'est produite : $e"),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: Colors.red,
                            showCloseIcon: true,
                          ),
                        );
                      } finally {
                        setState(() {
                          isLoading = false;
                        });
                      }
                    } else {
                      setState(() {
                        isLoading = false;
                      });
                    }
                  },
                  child: isLoading
                      ? const CircularProgressIndicator()
                      : Text(forLogin ? "se connecter" : "s'inscrire"),
                ),
              ),
              SizedBox(
                child: TextButton(
                  onPressed: () {
                    emailController.text = "";
                    passwordController.text = "";
                    passwordConfirmController.text = "";
                    setState(() {
                      forLogin = !forLogin;
                    });
                  },
                  child: Text(
                    forLogin
                        ? "Je n'ai pas de compte s'inscrire"
                        : "J'ai déjà un compte se connecter",
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
