class ActiveMatch {
  final String id;
  final String opponentUsername;
  final String? avatarConfig;
  final int affinity;
  final DateTime lastActivity;
  final bool isOnline;

  ActiveMatch({
    required this.id,
    required this.opponentUsername,
    this.avatarConfig,
    required this.affinity,
    required this.lastActivity,
    required this.isOnline,
  });

  factory ActiveMatch.fromJson(Map<String, dynamic> json) {
    return ActiveMatch(
      id: json['id'],
      opponentUsername: json['opponent_username'],
      avatarConfig: json['avatar_config'],
      affinity: json['affinity'],
      lastActivity: DateTime.tryParse(json['last_activity']) ?? DateTime.now(),
      isOnline: json['is_online'] ?? false,
    );
  }
}
