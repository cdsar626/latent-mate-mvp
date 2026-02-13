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
  ActiveMatch? _currentMatch;
  List<ActiveMatch> _activeMatches = [];
  List<ActiveMatch> _archivedMatches = [];

  Question? _currentQuestion;
  int _affinity = 0;
  bool _chatUnlocked = false;
  final List<ChatMessage> _messages = [];
  bool _hasAnswered = false;
  bool _isSearching = false;
  bool _noMoreQuestions = false;
  Map<String, dynamic>? _viewedProfile;
  bool _profileUpdated = false;

  late SocketService _socketService;

  GameState get gameState => _gameState;
  User? get currentUser => _currentUser;
  ActiveMatch? get currentMatch => _currentMatch;
  List<ActiveMatch> get activeMatches => _activeMatches;
  List<ActiveMatch> get archivedMatches => _archivedMatches;
  Question? get currentQuestion => _currentQuestion;
  int get affinity => _affinity;
  bool get chatUnlocked => _chatUnlocked;
  List<ChatMessage> get messages => _messages;
  bool get hasAnswered => _hasAnswered;
  bool get isSearching => _isSearching;
  bool get noMoreQuestions => _noMoreQuestions;
  Map<String, dynamic>? get viewedProfile => _viewedProfile;
  bool get profileUpdated => _profileUpdated;

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
    if (_isSearching) return; // Guard against multiple taps
    _isSearching = true;
    _gameState = GameState.matching;
    _socketService.sendFindMatch();
    notifyListeners();
  }

  void setSearching(bool searching) {
    _isSearching = searching;
    if (searching) {
      _gameState = GameState.matching;
    }
    notifyListeners();
  }

  void setMatchFound(String opponent) {
    _isSearching = false;
    _gameState = GameState.lobby;
    _socketService.sendFetchActiveMatches();
    notifyListeners();
  }

  void setActiveMatches(List<ActiveMatch> matches) {
    _activeMatches = matches;
    _isSearching = false;
    if (_gameState == GameState.matching) {
      _gameState = GameState.lobby;
    }
    notifyListeners();
  }

  void setArchivedMatches(List<ActiveMatch> matches) {
    _archivedMatches = matches;
    notifyListeners();
  }

  void fetchArchivedMatches() {
    _socketService.sendFetchArchivedMatches();
  }

  void selectMatch(ActiveMatch match) {
    _currentMatch = match;
    _affinity = match.affinity;
    _chatUnlocked = match.affinity >= 1;
    _messages.clear();
    _currentQuestion = null;
    _hasAnswered = false;
    _noMoreQuestions = false;
    _gameState = GameState.inGame;
    notifyListeners();
  }

  void clearSelection() {
    _currentMatch = null;
    _currentQuestion = null;
    _hasAnswered = false;
    _noMoreQuestions = false;
    _messages.clear();
    _gameState = GameState.lobby;
    _socketService.sendFetchActiveMatches();
    notifyListeners();
  }

  void setQuestion(Question q) {
    _currentQuestion = q;
    _hasAnswered = false;
    _noMoreQuestions = false;
    notifyListeners();
  }

  void setNoMoreQuestions() {
    _noMoreQuestions = true;
    _currentQuestion = null;
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
    _profileUpdated = false;
    _socketService.sendUpdateProfile(bio, tags, avatarConfig);
  }

  void onProfileUpdated() {
    _profileUpdated = true;
    notifyListeners();
  }

  void fetchUserProfile(String userId) {
    _viewedProfile = null;
    _socketService.sendFetchUserProfile(userId);
  }

  void setViewedProfile(Map<String, dynamic> profile) {
    _viewedProfile = profile;
    notifyListeners();
  }

  void suppressMatch(String matchId) {
    _socketService.sendSuppressMatch(matchId);
  }

  void onMatchSuppressed(String matchId) {
    _activeMatches.removeWhere((m) => m.id == matchId);
    if (_currentMatch?.id == matchId) {
      _currentMatch = null;
      _gameState = GameState.lobby;
    }
    _socketService.sendFetchActiveMatches();
    _socketService.sendFetchArchivedMatches();
    notifyListeners();
  }

  void deleteMatch(String matchId) {
    _socketService.sendDeleteMatch(matchId);
  }

  void onMatchDeleted(String matchId) {
    _archivedMatches.removeWhere((m) => m.id == matchId);
    _socketService.sendFetchArchivedMatches();
    notifyListeners();
  }

  @override
  void dispose() {
    _socketService.dispose();
    super.dispose();
  }
}
