import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;

  Future<AuthResponse> signUp(String email, String password, {String? username, String? gender, String? interest}) async {
    return await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        if (username != null) 'username': username,
        if (gender != null) 'gender': gender,
        if (interest != null) 'interest': interest,
        'profile_setup_completed': false,
      },
    );
  }

  Future<AuthResponse> signIn(String email, String password) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> logout() async {
    await _supabase.auth.signOut();
  }

  String? get currentUsername {
     // For MVP, using email part as username or metadata if available
     // Ideally we store username in user_metadata
     final user = currentUser;
     if (user == null) return null;
     return user.userMetadata?['username'] ?? user.email?.split('@')[0];
  }

  String? get currentUserId => currentUser?.id;

  String? get currentUserEmail => currentUser?.email;
}
