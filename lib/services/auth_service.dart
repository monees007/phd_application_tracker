import 'package:firebase_auth/firebase_auth.dart';

/// Sign-in strategy: start anonymous so the app is usable in one tap, then let
/// the user attach an email/password to the *same* uid later. Linking (rather
/// than a fresh sign-in) preserves everything already saved under that uid.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<User?> get userChanges => _auth.userChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signInAnonymously() => _auth.signInAnonymously();

  Future<UserCredential> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<UserCredential> register(String email, String password) => _auth
      .createUserWithEmailAndPassword(email: email.trim(), password: password);

  /// Upgrades the current anonymous account in place.
  Future<UserCredential> linkEmail(String email, String password) {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
          code: 'no-current-user', message: 'Not signed in.');
    }
    final cred =
        EmailAuthProvider.credential(email: email.trim(), password: password);
    return user.linkWithCredential(cred);
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> signOut() => _auth.signOut();

  static String describeError(Object e) {
    if (e is FirebaseAuthException) {
      return switch (e.code) {
        'invalid-email' => 'That email address is not valid.',
        'user-disabled' => 'This account has been disabled.',
        'user-not-found' || 'wrong-password' || 'invalid-credential' =>
          'Email or password is incorrect.',
        'email-already-in-use' => 'An account already exists for that email.',
        'weak-password' => 'Password must be at least 6 characters.',
        'credential-already-in-use' =>
          'That email is already linked to another account.',
        'network-request-failed' => 'No network connection.',
        _ => e.message ?? 'Authentication failed (${e.code}).',
      };
    }
    return e.toString();
  }
}
