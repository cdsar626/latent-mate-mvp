import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../widgets/pet_widget.dart';
import '../models/active_match.dart';
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

  void _confirmFindMatch(GameProvider provider) {
    if (provider.activeMatches.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Maximum of 3 matches allowed. Finish a conversation first.")),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Find Latent Mate"),
        content: const Text("Are you sure you want to search for a new connection?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              provider.findMatch();
            },
            child: const Text("Search"),
          ),
        ],
      ),
    );
  }

  void _openMatch(ActiveMatch match) {
    Provider.of<GameProvider>(context, listen: false).selectMatch(match);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GameScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gameProvider = Provider.of<GameProvider>(context);

    // List of 3 slots (null if empty, Match if full)
    final List<ActiveMatch?> slots = List.filled(3, null);
    for (int i = 0; i < gameProvider.activeMatches.length && i < 3; i++) {
      slots[i] = gameProvider.activeMatches[i];
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
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const PetWidget(size: 60, color: Colors.blue),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Hello, ${gameProvider.currentUser?.username ?? 'User'}!",
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "Your Active Connections (${gameProvider.activeMatches.length}/3)",
                      style: GoogleFonts.poppins(color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ).animate().slideX(),
            const SizedBox(height: 32),

            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 1,
                  childAspectRatio: 1.5,
                  mainAxisSpacing: 16,
                ),
                itemCount: 3,
                itemBuilder: (context, index) {
                  final match = slots[index];
                  if (match == null) {
                    return GestureDetector(
                      onTap: () => _confirmFindMatch(gameProvider),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey[300]!, width: 2, style: BorderStyle.solid),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_circle_outline, size: 48, color: Colors.grey),
                            const SizedBox(height: 8),
                            Text("Find Latent Mate", style: GoogleFonts.poppins(color: Colors.grey, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ).animate().fadeIn(delay: (index * 100).ms);
                  } else {
                    // Match Card
                    Color haloColor = Colors.grey;
                    if (match.isOnline) {
                      final diff = DateTime.now().difference(match.lastActivity);
                      if (diff.inSeconds < 30) {
                        haloColor = Colors.green;
                      } else if (diff.inMinutes < 3) {
                        haloColor = Colors.orange;
                      }
                    }

                    return GestureDetector(
                      onTap: () => _openMatch(match),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(color: Colors.deepPurple.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: haloColor, width: 3),
                              ),
                              child: const PetWidget(size: 60, color: Colors.orange), // Use config later
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(match.opponentUsername, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value: match.affinity / 100, // Normalized
                                    backgroundColor: Colors.grey[200],
                                    color: Colors.deepPurple,
                                  ),
                                  const SizedBox(height: 4),
                                  Text("${match.affinity}% Affinity", style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: Colors.grey),
                          ],
                        ),
                      ),
                    ).animate().fadeIn(delay: (index * 100).ms).slideY(begin: 0.1, end: 0);
                  }
                },
              ),
            ),

            if (gameProvider.gameState == GameState.matching)
              Center(child: Text("Searching...", style: GoogleFonts.poppins(color: Colors.deepPurple))),
          ],
        ),
      ),
    );
  }
}
