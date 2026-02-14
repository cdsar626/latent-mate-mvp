import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../widgets/pet_widget.dart';
import '../models/active_match.dart';
import 'game_screen.dart';
import 'splash_screen.dart';
import 'edit_profile_screen.dart';
import '../services/auth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    // Fetch archived matches on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<GameProvider>(context, listen: false).fetchArchivedMatches();
    });
  }

  void _confirmFindMatch(GameProvider provider) {
    if (provider.activeMatches.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Maximum of 3 matches. Dismiss one first.")),
      );
      return;
    }
    if (provider.isSearching) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Find Latent Mate"),
        content: const Text("Search for a new connection?"),
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

  void _confirmDeleteMatch(GameProvider provider, ActiveMatch match) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Permanently Delete?"),
        content: Text("This will remove ${match.opponentUsername} from your archive. You may be matched with them again."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              provider.deleteMatch(match.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gp = Provider.of<GameProvider>(context);

    final List<ActiveMatch?> slots = List.filled(3, null);
    for (int i = 0; i < gp.activeMatches.length && i < 3; i++) {
      slots[i] = gp.activeMatches[i];
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('LatentMate', style: GoogleFonts.pacifico(color: Colors.deepPurple, fontSize: 24)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person, color: Colors.deepPurple),
            tooltip: "Edit Profile",
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.grey),
            onPressed: () async {
              final gp = Provider.of<GameProvider>(context, listen: false);
              gp.disconnect(); // Tear down WS first to prevent ghost reconnects
              await _authService.logout();
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const SplashScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const PetWidget(size: 48, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Hello, ${gp.currentUser?.username ?? 'User'}!",
                        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        "Connections (${gp.activeMatches.length}/3)",
                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ).animate().slideX(),
            const SizedBox(height: 20),

            // 3 match slots in a single horizontal row
            SizedBox(
              height: 140,
              child: Row(
                children: List.generate(3, (index) {
                  final match = slots[index];
                  if (match == null) {
                    return Expanded(
                      child: GestureDetector(
                        onTap: gp.isSearching ? null : () => _confirmFindMatch(gp),
                        child: Container(
                          margin: EdgeInsets.only(
                            left: index == 0 ? 0 : 6,
                            right: index == 2 ? 0 : 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey[300]!, width: 1.5),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (gp.isSearching && index == gp.activeMatches.length)
                                const SizedBox(
                                  width: 28, height: 28,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepPurple),
                                )
                              else
                                const Icon(Icons.add_circle_outline, size: 32, color: Colors.grey),
                              const SizedBox(height: 6),
                              Text(
                                gp.isSearching && index == gp.activeMatches.length
                                    ? "Searching..."
                                    : "Find",
                                style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ).animate().fadeIn(delay: (index * 80).ms),
                    );
                  } else {
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => _openMatch(match),
                        child: Container(
                          margin: EdgeInsets.only(
                            left: index == 0 ? 0 : 6,
                            right: index == 2 ? 0 : 6,
                          ),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(color: Colors.deepPurple.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 4))
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: match.isOnline ? Colors.green : Colors.grey[400]!,
                                    width: 2,
                                  ),
                                ),
                                child: PetWidget(size: 36, color: match.isOnline ? Colors.orange : Colors.grey),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                match.opponentUsername,
                                style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              LinearProgressIndicator(
                                value: (match.affinity / 20).clamp(0.0, 1.0),
                                backgroundColor: Colors.grey[200],
                                color: Colors.deepPurple,
                                minHeight: 3,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "${match.affinity} ❤️",
                                style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ).animate().fadeIn(delay: (index * 80).ms).slideY(begin: 0.1, end: 0),
                    );
                  }
                }),
              ),
            ),

            const SizedBox(height: 24),

            // Archived section toggle
            GestureDetector(
              onTap: () {
                setState(() => _showArchived = !_showArchived);
                if (_showArchived) gp.fetchArchivedMatches();
              },
              child: Row(
                children: [
                  Icon(
                    _showArchived ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                    color: Colors.grey[600],
                    size: 20,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "Archived (${gp.archivedMatches.length})",
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),

            if (_showArchived) ...[
              const SizedBox(height: 8),
              Expanded(
                child: gp.archivedMatches.isEmpty
                    ? Center(
                        child: Text("No archived matches", style: GoogleFonts.poppins(color: Colors.grey)),
                      )
                    : ListView.builder(
                        itemCount: gp.archivedMatches.length,
                        itemBuilder: (context, index) {
                          final match = gp.archivedMatches[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Row(
                              children: [
                                PetWidget(size: 32, color: Colors.grey),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(match.opponentUsername, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                                      Text("${match.affinity} ❤️ affinity", style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_forever, color: Colors.red, size: 22),
                                  tooltip: "Permanently delete",
                                  onPressed: () => _confirmDeleteMatch(gp, match),
                                ),
                              ],
                            ),
                          ).animate().fadeIn(delay: (index * 60).ms);
                        },
                      ),
              ),
            ] else
              const Spacer(),
          ],
        ),
      ),
    );
  }
}
