import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../models/question.dart';
import 'chat_screen.dart';
import 'profile_view_screen.dart';

class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gp = Provider.of<GameProvider>(context);
    final question = gp.currentQuestion;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            gp.clearSelection();
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          gp.currentMatch?.opponentUsername ?? "Match",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        actions: [
          // View partner profile
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: "View Profile",
            onPressed: () {
              // We need the opponent's user ID — for now we'll use the match info
              // The match object doesn't carry opponent_id directly, so we use a fetch
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileViewScreen()),
              );
            },
          ),
          // Suppress/dismiss match
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'suppress') {
                _confirmSuppressMatch(context, gp);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'suppress', child: Text("Dismiss Match")),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "❤️ ${gp.affinity}",
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Question area
          _buildQuestionArea(gp, question),
          const Divider(height: 1),
          // Chat area — locked until affinity threshold
          Expanded(
            flex: 3,
            child: gp.chatUnlocked
                ? const ChatScreen()
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_outline, size: 40, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text(
                            "Chat is locked",
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Answer questions together to build affinity and unlock the chat!",
                            style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[400]),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ).animate().fadeIn(),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionArea(GameProvider gp, Question? question) {
    if (gp.noMoreQuestions) {
      return Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.celebration, size: 36, color: Colors.amber),
            const SizedBox(height: 8),
            Text(
              "You've answered all available questions!",
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            Text(
              "Keep chatting to grow your connection.",
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ).animate().fadeIn();
    }

    if (question == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 8),
            const SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 8),
            Text("Waiting for question...", style: GoogleFonts.poppins(color: Colors.grey)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          Text(
            question.text,
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ).animate().fadeIn(),
          const SizedBox(height: 16),
          if (gp.hasAnswered)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepPurple),
                ),
                const SizedBox(width: 8),
                Text("Waiting for opponent...", style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey)),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: question.options.map((option) {
                return ElevatedButton(
                  onPressed: () => gp.answerQuestion(option),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple.withOpacity(0.1),
                    foregroundColor: Colors.deepPurple,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(option, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 13)),
                );
              }).toList(),
            ).animate().fadeIn(delay: 100.ms),
        ],
      ),
    );
  }

  void _confirmSuppressMatch(BuildContext context, GameProvider gp) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Dismiss Match?"),
        content: Text("${gp.currentMatch?.opponentUsername} will be moved to your archive."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (gp.currentMatch != null) {
                gp.suppressMatch(gp.currentMatch!.id);
                Navigator.of(context).pop(); // Go back to home
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Dismiss"),
          ),
        ],
      ),
    );
  }
}
