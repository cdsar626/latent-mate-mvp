import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../providers/game_provider.dart';
import '../models/user.dart';
import '../models/question.dart';
import '../models/message.dart';
import 'auth_service.dart';

class SocketService {
  final GameProvider gameProvider;
  final AuthService _authService = AuthService();
  WebSocketChannel? _channel;
  String? _username;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isConnected = false;

  SocketService(this.gameProvider);

  void connect(String username) {
    _username = username;
    _initConnection();
  }

  void _initConnection() {
    if (_username == null) return;

    // Using localhost for web/desktop.
    // If testing on Android Emulator, use 'ws://10.0.2.2:3000/ws'
    final uri = Uri.parse('ws://127.0.0.1:3000/ws');
    _channel = WebSocketChannel.connect(uri);
    _isConnected = true;

    _channel!.stream.listen(
      (message) {
        _handleMessage(message);
      },
      onError: (error) {
        print("Socket error: $error");
        _isConnected = false;
        _scheduleReconnect();
      },
      onDone: () {
        print("Socket closed");
        _isConnected = false;
        _scheduleReconnect();
      },
    );

    // Send user_id for "authentication" / syncing with DB
    _send({
      'type': 'Connect',
      'payload': {
        'user_id': _authService.currentUserId ?? "unknown",
        'username': _username,
        'email': _authService.currentUserEmail
      }
    });
    _startHeartbeat();
  }

  void _scheduleReconnect() {
    _pingTimer?.cancel();
    if (_reconnectTimer?.isActive ?? false) return;

    print("Scheduling reconnect in 3 seconds...");
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      print("Attempting reconnect...");
      _initConnection();
    });
  }

  void _startHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_isConnected) {
        _send({'type': 'Ping', 'payload': null});
      }
    });
  }

  void _handleMessage(String message) {
    try {
      final Map<String, dynamic> data = jsonDecode(message);
      final String type = data['type'];
      final dynamic payload = data['payload'];

      switch (type) {
        case 'Connected':
          if (_username != null) {
             final user = User(id: payload['user_id'], username: _username!);
             gameProvider.setConnected(user);
             // Auto-fetch history on connect
             sendFetchHistory();
          }
          break;
        case 'MatchFound':
          gameProvider.setMatchFound(payload['opponent_name']);
          break;
        case 'Question':
          final question = Question.fromJson(payload);
          gameProvider.setQuestion(question);
          break;
        case 'AffinityUpdate':
          gameProvider.updateAffinity(payload['score'], payload['unlocked']);
          break;
        case 'ChatMessage':
          final msg = ChatMessage(
            senderId: payload['sender_id'],
            content: payload['content'],
            isMe: false,
          );
          gameProvider.addMessage(msg);
          break;
        case 'History':
          final List<dynamic> msgs = payload['messages'];
          final List<ChatMessage> parsedMsgs = msgs.map((m) => ChatMessage(
            senderId: m['sender_id'],
            content: m['content'],
            isMe: m['sender_id'] == gameProvider.currentUser?.id,
          )).toList();
          for (var msg in parsedMsgs) {
             gameProvider.addMessage(msg);
          }
          break;
        case 'Pong':
          break;
        case 'Error':
          print("Server Error: ${payload['message']}");
          break;
      }
    } catch (e) {
      print("Error parsing message: $e");
    }
  }

  void sendFindMatch() {
    _send({'type': 'FindMatch', 'payload': null});
  }

  void sendAnswer(String choice) {
    _send({
      'type': 'AnswerQuestion',
      'payload': {'choice': choice, 'comment': null}
    });
  }

  void sendMessage(String content) {
    _send({
      'type': 'SendMessage',
      'payload': {'content': content}
    });
  }

  void sendUpdateProfile(String bio, List<String> tags, String avatarConfig) {
    _send({
      'type': 'UpdateProfile',
      'payload': {
        'bio': bio,
        'tags': tags,
        'avatar_config': avatarConfig,
      }
    });
  }

  void sendFetchHistory() {
    _send({'type': 'FetchHistory', 'payload': null});
  }

  void _send(Map<String, dynamic> data) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
  }
}
