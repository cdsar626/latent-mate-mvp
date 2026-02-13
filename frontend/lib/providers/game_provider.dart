import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/question.dart';
import '../models/message.dart';
import '../models/active_match.dart';
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
  ActiveMatch? _currentMatch; // Selected match for chat/game
  List<ActiveMatch> _activeMatches = [];

  Question? _currentQuestion;
  int _affinity = 0;
  bool _chatUnlocked = false;
  final List<ChatMessage> _messages = [];
  bool _hasAnswered = false;

  late SocketService _socketService;

  GameState get gameState => _gameState;
  User? get currentUser => _currentUser;
  ActiveMatch? get currentMatch => _currentMatch;
  List<ActiveMatch> get activeMatches => _activeMatches;
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
    _socketService.sendFetchActiveMatches();
    notifyListeners();
  }

  void findMatch() {
    _gameState = GameState.matching;
    _socketService.sendFindMatch();
    notifyListeners();
  }

  void setMatchFound(String opponent) {
    // Ideally backend sends full ActiveMatch structure on MatchFound.
    // For now we assume a fetch refresh happens or we build a temporary one.
    // Simulating refresh:
    _socketService.sendFetchActiveMatches();
    notifyListeners();
  }

  void setActiveMatches(List<ActiveMatch> matches) {
    _activeMatches = matches;
    notifyListeners();
  }

  void selectMatch(ActiveMatch match) {
    _currentMatch = match;
    _affinity = match.affinity;
    // Assume logic to check if unlocked based on affinity or backend data
    _chatUnlocked = match.affinity >= 100; // MVP rule? Or backend says so.

    // Fetch history for this match (Need to update protocol to support match_id, or backend infers)
    // _socketService.sendFetchHistory(match.id);
    _gameState = GameState.inGame;
    notifyListeners();
  }

  void clearSelection() {
    _currentMatch = null;
    _gameState = GameState.lobby;
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
