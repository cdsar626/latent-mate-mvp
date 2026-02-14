// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/game_provider.dart';
import '../services/auth_service.dart';
import 'profile_setup_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String? _gender;
  String? _interest;
  bool _isLogin = true;
  bool _isLoading = false;
  bool _isCheckingSession = true;

  @override
  void initState() {
    super.initState();
    // Defer session check until after the first frame to avoid
    // navigating while the Navigator is still locked during build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSession());
  }

  Future<void> _checkSession() async {
    // Quick check — no artificial delay
    if (_authService.currentUser != null) {
      if (!mounted) return;
      final username = _authService.currentUsername ?? "User";
      Provider.of<GameProvider>(context, listen: false).init(username);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
      return;
    }
    // No session found, show the login form
    if (mounted) {
      setState(() => _isCheckingSession = false);
    }
  }

  Future<void> _authenticate() async {
    setState(() => _isLoading = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      if (email.isEmpty || password.isEmpty) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fill all fields")));
         return;
      }

      if (!_isLogin && (_gender == null || _interest == null)) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select gender and interest")));
         return;
      }

      if (_isLogin) {
        await _authService.signIn(email, password);
      } else {
        final response = await _authService.signUp(email, password);

        if (response.session == null && response.user != null) {
           if (!mounted) return;
           await showDialog(
             context: context,
             builder: (context) => AlertDialog(
               title: const Text("Verify your email"),
               content: Text("An email has been sent to $email. Please verify your account to log in."),
               actions: [
                 TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))
               ],
             ),
           );
           setState(() => _isLogin = true);
           return;
        }
      }

      if (!mounted) return;

      final username = email.split('@')[0];

      if (!_isLogin) {
         Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => ProfileSetupScreen(username: username, gender: _gender, interest: _interest)),
        );
      } else {
         Provider.of<GameProvider>(context, listen: false).init(username);
         Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }

    } on AuthException catch (e) {
      String message = e.message;
      if (e.message.toLowerCase().contains("email not confirmed")) {
        message = "Please confirm your email address before logging in.";
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF00C6FF), Color(0xFF0072FF), Color(0xFF6A11CB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: _isCheckingSession
              ? _buildSplashView()
              : _buildAuthView(),
        ),
      ),
    );
  }

  /// Branded splash shown while checking auth session
  Widget _buildSplashView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.favorite, size: 80, color: Colors.white)
            .animate()
            .scale(duration: 600.ms, curve: Curves.easeOutBack),
        const SizedBox(height: 24),
        Text(
          'LatentMate',
          style: GoogleFonts.ooohBaby(fontSize: 48, color: Colors.white),
        ).animate().fadeIn().moveY(begin: 20, end: 0),
        const SizedBox(height: 32),
        const CircularProgressIndicator(color: Colors.white70),
      ],
    );
  }

  /// Login / Sign-up form
  Widget _buildAuthView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.favorite, size: 80, color: Colors.white)
              .animate()
              .scale(duration: 600.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 24),
          Text(
            'LatentMate',
            style: GoogleFonts.ooohBaby(fontSize: 48, color: Colors.white),
          ).animate().fadeIn().moveY(begin: 20, end: 0),
          const SizedBox(height: 48),
          TextField(
            controller: _emailController,
            decoration: InputDecoration(
              hintText: "Email",
              filled: true,
              fillColor: Colors.white.withOpacity(0.9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: InputDecoration(
              hintText: "Password",
              filled: true,
              fillColor: Colors.white.withOpacity(0.9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ).animate().fadeIn(delay: 300.ms),
          if (!_isLogin) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _gender,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withOpacity(0.9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                hintText: "I am...",
              ),
              items: ['Male', 'Female'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (newValue) => setState(() => _gender = newValue),
            ).animate().fadeIn(delay: 350.ms),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _interest,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withOpacity(0.9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                hintText: "Looking for...",
              ),
              items: ['Male', 'Female', 'Both'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (newValue) => setState(() => _interest = newValue),
            ).animate().fadeIn(delay: 350.ms),
          ],
          const SizedBox(height: 24),
          if (_isLoading)
            const CircularProgressIndicator(color: Colors.white)
          else
            Column(
              children: [
                ElevatedButton(
                  onPressed: _authenticate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF2575FC),
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: Text(_isLogin ? "Login" : "Sign Up", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(
                    _isLogin ? "Create an account" : "I have an account",
                    style: const TextStyle(color: Colors.white),
                  ),
                )
              ],
            ).animate().fadeIn(delay: 400.ms).moveY(begin: 20, end: 0),
        ],
      ),
    );
  }
}
