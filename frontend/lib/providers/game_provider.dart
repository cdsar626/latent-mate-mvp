import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/question.dart';
import '../models/message.dart';
import '../services/socket_service.dart';

enum GameState {
  connecting,
  lobby,
  matching,
  inGame,
}

class GameProvider with ChangeNotifier {
  GameState _gameState = GameState.connecting;
  User? _currentUser;
  String? _opponentName;
  Question? _currentQuestion;
  int _affinity = 0;
  bool _chatUnlocked = false;
  final List<ChatMessage> _messages = [];
  bool _hasAnswered = false;

  late SocketService _socketService;

  GameState get gameState => _gameState;
  User? get currentUser => _currentUser;
  String? get opponentName => _opponentName;
  Question? get currentQuestion => _currentQuestion;
  int get affinity => _affinity;
  bool get chatUnlocked => _chatUnlocked;
  List<ChatMessage> get messages => _messages;
  bool get hasAnswered => _hasAnswered;

  void init(String username) {
     _socketService = SocketService(this);
     _socketService.connect(username);
  }

  void setConnected(User user) {
    _currentUser = user;
    _gameState = GameState.lobby;
    notifyListeners();
  }

  void findMatch() {
    _gameState = GameState.matching;
    _socketService.sendFindMatch();
    notifyListeners();
  }

  void setMatchFound(String opponent) {
    _opponentName = opponent;
    _gameState = GameState.inGame;
    notifyListeners();
  }

  void setQuestion(Question q) {
    _currentQuestion = q;
    _hasAnswered = false;
    notifyListeners();
  }

  void answerQuestion(String choice) {
    _hasAnswered = true;
    _socketService.sendAnswer(choice);
    notifyListeners();
  }

  void updateAffinity(int score, bool unlocked) {
    _affinity = score;
    _chatUnlocked = unlocked;
    notifyListeners();
  }

  void addMessage(ChatMessage msg) {
    _messages.add(msg);
    notifyListeners();
  }

  void sendMessage(String content) {
    if (_chatUnlocked) {
        _socketService.sendMessage(content);
        // Optimistic update
        if (_currentUser != null) {
          _messages.add(ChatMessage(senderId: _currentUser!.id, content: content, isMe: true));
          notifyListeners();
        }
    }
  }

  void updateProfile(String bio, List<String> tags, String avatarConfig) {
    _socketService.sendUpdateProfile(bio, tags, avatarConfig);
  }

  @override
  void dispose() {
    _socketService.dispose();
    super.dispose();
  }
}
