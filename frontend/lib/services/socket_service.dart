import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../providers/game_provider.dart';
import '../models/user.dart';
import '../models/question.dart';
import '../models/message.dart';
import '../models/active_match.dart';
import 'auth_service.dart';

class SocketService {
  final GameProvider gameProvider;
  final AuthService _authService = AuthService();
  WebSocketChannel? _channel;
  String? _username;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isConnected = false;
  bool _disposed = false;

  SocketService(this.gameProvider);

  void connect(String username) {
    _username = username;
    _disposed = false;
    _initConnection();
  }

  void _initConnection() {
    if (_disposed) return;
    if (_username == null) return;

    // Don't reconnect if user is no longer authenticated
    if (_authService.currentUserId == null) {
      debugPrint("SocketService: skipping connect — no authenticated user");
      return;
    }

    // If testing on Android Emulator, use 'ws://10.0.2.2:3000/ws'
    final uri = Uri.parse('ws://lmate.cdsar626.com/ws');
    _channel = WebSocketChannel.connect(uri);
    _isConnected = true;

    _channel!.stream.listen(
      (message) {
        _handleMessage(message);
      },
      onError: (error) {
        debugPrint("Socket error: $error");
        _isConnected = false;
        _scheduleReconnect();
      },
      onDone: () {
        debugPrint("Socket closed");
        _isConnected = false;
        _scheduleReconnect();
      },
    );

    // Send user_id for "authentication" / syncing with DB
    _send({
      'type': 'Connect',
      'payload': {
        'user_id': _authService.currentUserId ?? "",
        'username': _username,
        'email': _authService.currentUserEmail
      }
    });
    _startHeartbeat();
  }

  void _scheduleReconnect() {
    _pingTimer?.cancel();
    if (_disposed) return;
    if (_reconnectTimer?.isActive ?? false) return;

    // Don't reconnect if user is no longer authenticated
    if (_authService.currentUserId == null) {
      debugPrint("SocketService: skipping reconnect — user logged out");
      return;
    }

    debugPrint("Scheduling reconnect in 3 seconds...");
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_disposed) return;
      debugPrint("Attempting reconnect...");
      _initConnection();
    });
  }

  void _startHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_isConnected && !_disposed) {
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
             sendFetchActiveMatches();
          }
          break;
        case 'SearchingAck':
          gameProvider.setSearching(true);
          break;
        case 'MatchFound':
          gameProvider.setSearching(false);
          gameProvider.setMatchFound(payload['opponent_name']);
          break;
        case 'SessionJoined':
          gameProvider.setSessionJoined(
            payload['match_id'],
            payload['affinity'],
            payload['unlocked'] ?? payload['chat_unlocked'] ?? false,
          );
          break;
        case 'ActiveMatches':
          final List<dynamic> matches = payload['matches'];
          final List<ActiveMatch> parsed = matches.map((m) => ActiveMatch.fromJson(m)).toList();
          gameProvider.setActiveMatches(parsed);
          break;
        case 'ArchivedMatches':
          final List<dynamic> matches = payload['matches'];
          final List<ActiveMatch> parsed = matches.map((m) => ActiveMatch.fromJson(m)).toList();
          gameProvider.setArchivedMatches(parsed);
          break;
        case 'UserStatus':
          sendFetchActiveMatches();
          break;
        case 'Question':
          final question = Question.fromJson(payload);
          gameProvider.setQuestion(question);
          break;
        case 'NoMoreQuestions':
          gameProvider.setNoMoreQuestions();
          break;
        case 'AffinityUpdate':
          gameProvider.updateAffinity(payload['score'], payload['unlocked']);
          break;
        case 'ChatMessage':
          final currentUserId = gameProvider.currentUser?.id ?? '';
          final msg = ChatMessage.fromJson(payload, currentUserId);
          // Don't add if it's our own echoed message (we already added it locally)
          if (!msg.isMe) {
            gameProvider.addMessage(msg);
          } else {
            // Update local message with server-assigned id and timestamp
            gameProvider.confirmMessage(msg);
          }
          break;
        case 'History':
          final currentUserId = gameProvider.currentUser?.id ?? '';
          final List<dynamic> msgs = payload['messages'];
          final List<ChatMessage> parsedMsgs = msgs.map((m) =>
            ChatMessage.fromJson(m as Map<String, dynamic>, currentUserId)
          ).toList();
          gameProvider.setHistory(parsedMsgs);
          break;
        case 'UserProfile':
          gameProvider.setViewedProfile(payload);
          break;
        case 'ProfileUpdated':
          gameProvider.onProfileUpdated();
          break;
        case 'MatchSuppressed':
          gameProvider.onMatchSuppressed(payload['match_id']);
          break;
        case 'MatchDeleted':
          gameProvider.onMatchDeleted(payload['match_id']);
          break;
        case 'PartnerTyping':
          gameProvider.setPartnerTyping(payload['match_id'], true);
          break;
        case 'PartnerStopTyping':
          gameProvider.setPartnerTyping(payload['match_id'], false);
          break;
        case 'Pong':
          break;
        case 'Error':
          debugPrint("Server Error: ${payload['message']}");
          gameProvider.setSearching(false);
          break;
      }
    } catch (e) {
      debugPrint("Error parsing message: $e");
    }
  }

  void sendFindMatch() {
    _send({'type': 'FindMatch', 'payload': null});
  }

  void sendJoinSession(String matchId) {
    _send({
      'type': 'JoinSession',
      'payload': {'match_id': matchId}
    });
  }

  void sendAnswer(String matchId, String choice) {
    _send({
      'type': 'AnswerQuestion',
      'payload': {'match_id': matchId, 'choice': choice, 'comment': null}
    });
  }

  void sendMessage(String matchId, String content) {
    _send({
      'type': 'SendMessage',
      'payload': {'match_id': matchId, 'content': content}
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

  void sendFetchHistory(String matchId) {
    _send({
      'type': 'FetchHistory',
      'payload': {'match_id': matchId}
    });
  }

  void sendFetchActiveMatches() {
    _send({'type': 'FetchActiveMatches', 'payload': null});
  }

  void sendFetchArchivedMatches() {
    _send({'type': 'FetchArchivedMatches', 'payload': null});
  }

  void sendFetchUserProfile(String userId) {
    _send({
      'type': 'FetchUserProfile',
      'payload': {'user_id': userId}
    });
  }

  void sendSuppressMatch(String matchId) {
    _send({
      'type': 'SuppressMatch',
      'payload': {'match_id': matchId}
    });
  }

  void sendDeleteMatch(String matchId) {
    _send({
      'type': 'DeleteMatch',
      'payload': {'match_id': matchId}
    });
  }

  void sendTyping(String matchId) {
    _send({
      'type': 'Typing',
      'payload': {'match_id': matchId}
    });
  }

  void sendStopTyping(String matchId) {
    _send({
      'type': 'StopTyping',
      'payload': {'match_id': matchId}
    });
  }

  void _send(Map<String, dynamic> data) {
    if (_channel != null && _isConnected && !_disposed) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _isConnected = false;
  }
}
