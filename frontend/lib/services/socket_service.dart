import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../providers/game_provider.dart';
import '../models/user.dart';
import '../models/question.dart';
import '../models/message.dart';

class SocketService {
  final GameProvider gameProvider;
  WebSocketChannel? _channel;
  String? _username;

  SocketService(this.gameProvider);

  void connect(String username) {
    _username = username;
    // Using localhost for web/desktop.
    // If testing on Android Emulator, use 'ws://10.0.2.2:3000/ws'
    final uri = Uri.parse('ws://127.0.0.1:3000/ws');
    _channel = WebSocketChannel.connect(uri);

    _channel!.stream.listen(
      (message) {
        _handleMessage(message);
      },
      onError: (error) {
        print("Socket error: $error");
      },
      onDone: () {
        print("Socket closed");
      },
    );

    _send({'type': 'Connect', 'payload': {'username': username}});
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

  void _send(Map<String, dynamic> data) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  void dispose() {
    _channel?.sink.close();
  }
}
