import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../widgets/pet_widget.dart';

/// Shows the partner's profile info (fetched from DB)
class ProfileViewScreen extends StatefulWidget {
  const ProfileViewScreen({super.key});

  @override
  State<ProfileViewScreen> createState() => _ProfileViewScreenState();
}

class _ProfileViewScreenState extends State<ProfileViewScreen> {
  @override
  void initState() {
    super.initState();
    // Trigger a profile fetch for the current match opponent
    // Note: requires opponent's user_id. We'll use match info.
    // For now, we show whatever viewedProfile data is available.
  }

  @override
  Widget build(BuildContext context) {
    final gp = Provider.of<GameProvider>(context);
    final profile = gp.viewedProfile;
    final matchName = gp.currentMatch?.opponentUsername ?? "User";

    return Scaffold(
      appBar: AppBar(
        title: Text("Profile", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Avatar
            Hero(
              tag: 'profile_avatar',
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [Color(0xFF6A11CB), Color(0xFF2575FC)]),
                ),
                child: const CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.white,
                  child: PetWidget(size: 60, color: Colors.deepPurple),
                ),
              ),
            ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 16),

            // Username
            Text(
              matchName,
              style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold),
            ).animate().fadeIn(),

            const SizedBox(height: 8),

            // Affinity
            if (gp.currentMatch != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "❤️ ${gp.currentMatch!.affinity} affinity",
                  style: GoogleFonts.poppins(fontSize: 14, color: Colors.deepPurple, fontWeight: FontWeight.w600),
                ),
              ).animate().fadeIn(delay: 100.ms),

            const SizedBox(height: 24),

            // Bio section
            if (profile != null) ...[
              _buildInfoCard("Bio", profile['bio'] ?? "No bio yet"),
              const SizedBox(height: 12),
              _buildInfoCard("Interests", _parseTags(profile['tags'])),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.grey),
                    const SizedBox(height: 8),
                    Text(
                      "Profile details will load when the backend sends them.",
                      style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(content, style: GoogleFonts.poppins(fontSize: 14)),
        ],
      ),
    ).animate().fadeIn().slideX(begin: 0.05, end: 0);
  }

  String _parseTags(String? tagsJson) {
    if (tagsJson == null || tagsJson.isEmpty) return "No interests listed";
    try {
      // Try to parse as JSON array
      final List<dynamic> tags = tagsJson.startsWith('[')
          ? (tagsJson.replaceAll('[', '').replaceAll(']', '').replaceAll('"', '').split(','))
          : [tagsJson];
      return tags.map((t) => t.toString().trim()).where((t) => t.isNotEmpty).join(", ");
    } catch (_) {
      return tagsJson;
    }
  }
}
