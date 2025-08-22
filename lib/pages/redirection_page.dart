
/*import 'package:flutter/material.dart';
import 'package:gepi/pages/home_page.dart';
import 'package:gepi/pages/page_login.dart';
import 'package:gepi/services/firebase/auth.dart';*/
/*import 'package:gepi/lib/pages/home_page.dart';
import 'package:gepi/lib/pages/login_page.dart';*/

/*class RedirectionPage extends StatefulWidget{
  const RedirectionPage({super.key});

  @override
  State<StatefulWidget> createState(){
    return _RedirectionPageState();
  }
}

class _RedirectionPageState extends State<RedirectionPage> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Auth().authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }else if (snapshot.hasData) {
          return const MyHomePage(title:"HomePage");
        }else{
          return LoginPage(title:"LoginPage");
        }
        
      },
    );
  }
}*/
import 'package:flutter/material.dart';
import 'package:gepi/pages/home_page.dart';
import 'package:gepi/pages/page_login.dart'; // Nom corrigé si nécessaire
import 'package:gepi/services/firebase/auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // NOUVEAUTÉ : Import pour Firestore

class RedirectionPage extends StatefulWidget {
  const RedirectionPage({super.key});

  @override
  State<StatefulWidget> createState() {
    return _RedirectionPageState();
  }
}

class _RedirectionPageState extends State<RedirectionPage> {
  // NOUVEAUTÉ : Fonction pour récupérer le rôle de l'utilisateur
  Future<String?> getUserRole(String uid) async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (userDoc.exists) {
        return userDoc.data()?['role'] as String?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: Auth().authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasData) {
          // NOUVEAUTÉ : Récupération du rôle et redirection
          final user = snapshot.data;
          if (user != null) {
            return FutureBuilder<String?>(
              future: getUserRole(user.uid),
              builder: (context, roleSnapshot) {
                if (roleSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (roleSnapshot.hasData && roleSnapshot.data != null) {
                  return MyHomePage(
                    title: "Accueil",
                    userRole: roleSnapshot.data!, // Passer le rôle à la page d'accueil
                  );
                } else {
                  // Gérer le cas où l'utilisateur est connecté mais n'a pas de rôle
                  return const Text("Erreur: Rôle non trouvé.");
                }
              },
            );
          } else {
            return LoginPage(title: "Connexion"); // Fallback
          }
        } else {
          return LoginPage(title: "Connexion");
        }
      },
    );
  }
}
