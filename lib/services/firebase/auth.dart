import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Auth {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Utilisateur actuellement connecté
  User? get currentUser => _firebaseAuth.currentUser;

  /// Flux qui écoute les changements d'état d'authentification
  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  /// Connexion avec email et mot de passe
  /// Retourne une Map contenant l'utilisateur et son rôle
  Future<Map<String, dynamic>?> loginWithEmailAndPassword(
      String email, String password) async {
    try {
      // Authentification Firebase
      final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Récupération du rôle dans Firestore
      final userDoc = await _firestore
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();

      if (userDoc.exists) {
        return {
          'user': userCredential.user,
          'role': userDoc.data()?['role'],
        };
      } else {
        throw FirebaseAuthException(
          code: 'no-role-found',
          message:
              "Aucun rôle n'est défini pour cet utilisateur dans la base de données.",
        );
      }
    } on FirebaseAuthException catch (e) {
      rethrow; // On laisse la page appelante gérer l'affichage de l'erreur
    } catch (e) {
      throw Exception("Erreur lors de la connexion : $e");
    }
  }

  /// Déconnexion
  Future<void> logout() async {
    await _firebaseAuth.signOut();
  }

  /// Création d'un compte avec un rôle
  Future<void> createUserWithEmailAndPassword(
      String email, String password, String role) async {
    try {
      // Création compte Firebase
      final userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Sauvegarde du rôle et infos utilisateur dans Firestore
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'uid': userCredential.user!.uid,
        'email': email,
        'role': role,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseAuthException catch (e) {
      rethrow;
    } catch (e) {
      throw Exception("Erreur lors de l'inscription : $e");
    }
  }
}
