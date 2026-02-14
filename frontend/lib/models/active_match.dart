class ActiveMatch {
  final String id;
  final String opponentId;
  final String opponentUsername;
  final String? avatarConfig;
  final int affinity;
  final String lastActivity;
  final bool isOnline;

  ActiveMatch({
    required this.id,
    required this.opponentId,
    required this.opponentUsername,
    this.avatarConfig,
    required this.affinity,
    required this.lastActivity,
    required this.isOnline,
  });

  factory ActiveMatch.fromJson(Map<String, dynamic> json) {
    return ActiveMatch(
      id: json['id'],
      opponentId: json['opponent_id'] ?? '',
      opponentUsername: json['opponent_username'],
      avatarConfig: json['avatar_config'],
      affinity: json['affinity'] ?? 0,
      lastActivity: json['last_activity'] ?? '',
      isOnline: json['is_online'] ?? false,
    );
  }
}
