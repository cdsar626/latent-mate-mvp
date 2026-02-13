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
  bool _isPartnerTyping = false;
  bool _initialized = false;

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
  bool get isPartnerTyping => _isPartnerTyping;

  void init(String username) {
    if (_initialized) return;
    _initialized = true;
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
    _isPartnerTyping = false;
    _gameState = GameState.inGame;

    // Request session join and history from server
    _socketService.sendJoinSession(match.id);
    _socketService.sendFetchHistory(match.id);

    notifyListeners();
  }

  void setSessionJoined(String matchId, int affinity, bool chatUnlocked) {
    if (_currentMatch?.id == matchId) {
      _affinity = affinity;
      _chatUnlocked = chatUnlocked;
      notifyListeners();
    }
  }

  void clearSelection() {
    _currentMatch = null;
    _currentQuestion = null;
    _hasAnswered = false;
    _noMoreQuestions = false;
    _isPartnerTyping = false;
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
    if (_currentMatch == null) return;
    _hasAnswered = true;
    _socketService.sendAnswer(_currentMatch!.id, choice);
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

  void setHistory(List<ChatMessage> msgs) {
    _messages.clear();
    _messages.addAll(msgs);
    notifyListeners();
  }

  void confirmMessage(ChatMessage serverMsg) {
    // Update the locally-added message with server-assigned id/timestamp
    // Find the last message from this sender without an id
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].isMe && _messages[i].id == null) {
        _messages[i] = serverMsg;
        notifyListeners();
        return;
      }
    }
  }

  void sendMessage(String content) {
    if (_chatUnlocked && _currentMatch != null) {
      // Add locally first for instant feedback
      _messages.add(ChatMessage(
        senderId: _currentUser?.id ?? '',
        content: content,
        isMe: true,
        timestamp: DateTime.now(),
      ));
      _socketService.sendMessage(_currentMatch!.id, content);
      notifyListeners();
    }
  }

  void setPartnerTyping(String matchId, bool isTyping) {
    if (_currentMatch?.id == matchId) {
      _isPartnerTyping = isTyping;
      notifyListeners();
    }
  }

  void sendTyping() {
    if (_currentMatch != null) {
      _socketService.sendTyping(_currentMatch!.id);
    }
  }

  void sendStopTyping() {
    if (_currentMatch != null) {
      _socketService.sendStopTyping(_currentMatch!.id);
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

  void disconnect() {
    _socketService.dispose();
    _initialized = false;
    _currentUser = null;
    _currentMatch = null;
    _activeMatches = [];
    _archivedMatches = [];
    _messages.clear();
    _gameState = GameState.connecting;
    _currentQuestion = null;
    _hasAnswered = false;
    _isSearching = false;
    _noMoreQuestions = false;
    _isPartnerTyping = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _socketService.dispose();
    super.dispose();
  }
}
