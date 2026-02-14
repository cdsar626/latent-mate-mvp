import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../models/message.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _typingTimer;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage(GameProvider provider) {
    if (_controller.text.trim().isNotEmpty) {
      provider.sendMessage(_controller.text.trim());
      _controller.clear();
      _onStopTyping(provider);
      Future.delayed(const Duration(milliseconds: 50), _scrollToBottom);
    }
  }

  void _onTextChanged(GameProvider provider) {
    if (!_isTyping) {
      _isTyping = true;
      provider.sendTyping();
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _onStopTyping(provider);
    });
  }

  void _onStopTyping(GameProvider provider) {
    if (_isTyping) {
      _isTyping = false;
      provider.sendStopTyping();
    }
    _typingTimer?.cancel();
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    final now = DateTime.now();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return '$h:$m';
    }
    return '${local.month}/${local.day} $h:$m';
  }

  bool _shouldShowDateSeparator(List<ChatMessage> messages, int index) {
    if (index == 0) return true;
    final current = messages[index].timestamp;
    final previous = messages[index - 1].timestamp;
    if (current == null || previous == null) return false;
    return current.toLocal().day != previous.toLocal().day ||
        current.toLocal().month != previous.toLocal().month ||
        current.toLocal().year != previous.toLocal().year;
  }

  String _formatDateSeparator(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return 'Today';
    } else if (local.year == yesterday.year && local.month == yesterday.month && local.day == yesterday.day) {
      return 'Yesterday';
    }
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gp = Provider.of<GameProvider>(context);
    final messages = gp.messages;

    // Auto-scroll when messages change
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Column(
      children: [
        // Messages area
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_outlined, size: 48, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text(
                        'Start your conversation',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.grey[400],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final showDateSep = _shouldShowDateSeparator(messages, index);

                    // Check if next message is from same sender and within 2 min — group them
                    final bool isLastInGroup = index == messages.length - 1 ||
                        messages[index + 1].isMe != msg.isMe ||
                        (messages[index + 1].timestamp != null && msg.timestamp != null &&
                            messages[index + 1].timestamp!.difference(msg.timestamp!).inMinutes > 2);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Date separator
                        if (showDateSep)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _formatDateSeparator(msg.timestamp ?? DateTime.now()),
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: Colors.grey[500],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // Message row — full-width, left/right aligned
                        _buildMessage(msg, isLastInGroup),
                      ],
                    );
                  },
                ),
        ),

        // Input area
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F1F9),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _controller,
                      onChanged: (_) => _onTextChanged(gp),
                      onSubmitted: (_) => _sendMessage(gp),
                      textInputAction: TextInputAction.send,
                      style: GoogleFonts.poppins(fontSize: 14, color: const Color(0xFF2D2D3A)),
                      decoration: InputDecoration(
                        hintText: 'Write a message...',
                        hintStyle: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[400]),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        isDense: true,
                      ),
                      maxLines: 4,
                      minLines: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Material(
                  color: Colors.deepPurple,
                  borderRadius: BorderRadius.circular(22),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => _sendMessage(gp),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Modern, no-bubble message style — full-width, clean and space-efficient
  Widget _buildMessage(ChatMessage msg, bool isLastInGroup) {
    if (msg.type == 'question_summary') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: GestureDetector(
          onTap: () => _showQuestionDetails(context, msg),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber[50], // Distinctive color
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amber[200]!, width: 1.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline, color: Colors.amber, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Question Round",
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber[800]),
                      ),
                      Text(
                        msg.content, // "Question: ..."
                        style: GoogleFonts.poppins(fontSize: 13, color: Colors.black87),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.amber),
              ],
            ),
          ),
          ),
        ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.1, end: 0, curve: Curves.easeOutBack);
    }

    final isMe = msg.isMe;
    final time = _formatTime(msg.timestamp);

    return Padding(
      padding: EdgeInsets.only(
        bottom: isLastInGroup ? 10 : 2,
        left: isMe ? 48 : 0,
        right: isMe ? 0 : 48,
      ),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Message container — no traditional bubble, uses subtle background + edge accent
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMe
                  ? const Color(0xFFEDE8F8) // soft lavender for own msgs
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border(
                left: BorderSide(
                  color: isMe ? Colors.deepPurple : const Color(0xFFD1D1E0),
                  width: isMe ? 3 : 2,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.025),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg.content,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: const Color(0xFF2D2D3A),
                    height: 1.4,
                  ),
                ),
                if (isLastInGroup && time.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Text(
                      time,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: Colors.grey[400],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showQuestionDetails(BuildContext context, ChatMessage msg) {
    if (msg.metadata == null) return;
    
    final meta = msg.metadata!;
    final question = meta['question'] ?? 'Question';
    final user1 = meta['user1'] ?? {};
    final user2 = meta['user2'] ?? {};
    final matched = meta['matched'] ?? false;
    
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Dismiss",
      pageBuilder: (dialogContext, anim1, anim2) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            elevation: 16,
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              height: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.horizontal(left: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                     padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                     color: Colors.deepPurple,
                     child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                           Row(
                              children: [
                                 const Icon(Icons.lightbulb, color: Colors.amber, size: 28),
                                 const SizedBox(width: 8),
                                 Text("Round Result", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                 const Spacer(),
                                 IconButton(
                                    icon: const Icon(Icons.close, color: Colors.white70),
                                    onPressed: () => Navigator.of(context).pop(),
                                 )
                              ],
                           ),
                           const SizedBox(height: 16),
                           Text(
                              question,
                              style: GoogleFonts.poppins(fontSize: 16, color: Colors.white, height: 1.4),
                           ),
                        ],
                     ),
                  ),
                  
                  // Body
                  Expanded(
                     child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                           children: [
                              _buildAnswerCard(user1, Colors.blue),
                              const SizedBox(height: 16),
                              _buildAnswerCard(user2, Colors.orange),
                              const SizedBox(height: 32),
                              if (matched) 
                                 Column(
                                    children: [
                                       const Icon(Icons.favorite, color: Colors.pink, size: 48),
                                       const SizedBox(height: 8),
                                       Text("It's a match!", style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.pink)),
                                       Text("+1 Affinity", style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey)),
                                    ],
                                 )
                              else
                                 Text("No match this time.", style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey, fontStyle: FontStyle.italic)),
                           ],
                        ),
                     ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim, secondaryAnim, child) {
         return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
            child: child,
         );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }
  
  Widget _buildAnswerCard(Map<String, dynamic> data, Color color) {
     final username = data['username'] ?? 'User';
     final answer = data['answer'] ?? '...';
     return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
           color: color.withValues(alpha: 0.05),
           borderRadius: BorderRadius.circular(12),
           border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
              Text(username, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
              const SizedBox(height: 4),
              Text(answer, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500)),
           ],
        ),
     );
  }
}
