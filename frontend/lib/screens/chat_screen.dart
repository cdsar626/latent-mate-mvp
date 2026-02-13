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
    final matchName = gp.currentMatch?.opponentUsername ?? 'Chat';

    // Auto-scroll when messages change
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18, color: Color(0xFF2D2D3A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              matchName,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2D2D3A),
              ),
            ),
            if (gp.isPartnerTyping)
              Text(
                'typing...',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: Colors.deepPurple,
                  fontWeight: FontWeight.w500,
                ),
              ).animate(onPlay: (c) => c.repeat(reverse: true))
                .fadeIn(duration: 600.ms)
                .then()
                .fadeOut(duration: 600.ms),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.withOpacity(0.1)),
        ),
      ),
      body: Column(
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
                                    color: Colors.grey.withOpacity(0.08),
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
                  color: Colors.black.withOpacity(0.04),
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
      ),
    );
  }

  /// Modern, no-bubble message style — full-width, clean and space-efficient
  Widget _buildMessage(ChatMessage msg, bool isLastInGroup) {
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
                  color: Colors.black.withOpacity(0.025),
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
}
