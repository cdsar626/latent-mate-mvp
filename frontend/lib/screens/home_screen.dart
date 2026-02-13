import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../widgets/pet_widget.dart';
import 'game_screen.dart';
import 'splash_screen.dart';
import '../services/auth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    final gameProvider = Provider.of<GameProvider>(context);

    if (gameProvider.gameState == GameState.inGame) {
        return const GameScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('LatentMate', style: GoogleFonts.pacifico(color: Colors.deepPurple, fontSize: 24)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.grey),
            onPressed: () async {
              await _authService.logout();
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const SplashScreen()),
                );
              }
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Profile Header
              Row(
                children: [
                  const PetWidget(size: 80, color: Colors.blue), // Using default/mock color for now
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Hello, ${gameProvider.currentUser?.username ?? 'User'}!",
                        style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        "Ready to connect?",
                        style: GoogleFonts.poppins(color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ).animate().slideX(),

              const SizedBox(height: 32),

              // Active Matches Section
              Text("Active Matches", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              // Mocking Active Matches List for now as backend doesn't send list yet (only one active match logic in MVP)
              // If we had a list in GameProvider, we would use it here.
              // For MVP visualization:
              Container(
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: 3, // Mock count
                  itemBuilder: (context, index) {
                    return Container(
                      width: 100,
                      margin: const EdgeInsets.only(right: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          PetWidget(size: 50, color: index == 0 ? Colors.pink : Colors.orange),
                          const SizedBox(height: 8),
                          Text("Match ${index + 1}", style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500)),
                          Text("${(index + 1) * 20}% Affinity", style: GoogleFonts.poppins(fontSize: 10, color: Colors.deepPurple)),
                        ],
                      ),
                    );
                  },
                ),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 32),

              // Nearby Users Section
              Text("Nearby Online", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Container(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: 5,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 16.0),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.green, width: 2),
                            ),
                            child: const PetWidget(size: 50, color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ).animate().fadeIn(delay: 400.ms),

              if (gameProvider.gameState == GameState.matching)
                Padding(
                  padding: const EdgeInsets.only(top: 40.0),
                  child: Center(
                    child: Column(
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text('Looking for a match...', style: GoogleFonts.poppins()),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: gameProvider.gameState == GameState.lobby
        ? FloatingActionButton.extended(
            onPressed: () {
              gameProvider.findMatch();
            },
            icon: const Icon(Icons.favorite),
            label: const Text("Find New Match"),
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
          ).animate().scale(delay: 600.ms)
        : null,
    );
  }
}
