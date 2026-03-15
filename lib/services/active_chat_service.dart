class ActiveChatService {
  static final ActiveChatService _instance = ActiveChatService._internal();
  factory ActiveChatService() => _instance;
  ActiveChatService._internal();

  String? _activeTargetType;
  String? _activeTargetId;

  void setActiveChat({required String targetType, required String targetId}) {
    _activeTargetType = targetType.trim().toLowerCase();
    _activeTargetId = targetId.trim();
  }

  void clearActiveChat({required String targetType, required String targetId}) {
    final normalizedType = targetType.trim().toLowerCase();
    if (_activeTargetType == normalizedType &&
        _activeTargetId == targetId.trim()) {
      _activeTargetType = null;
      _activeTargetId = null;
    }
  }

  bool isActiveNotification(Map<String, dynamic> data) {
    if ((_activeTargetType ?? '').isEmpty || (_activeTargetId ?? '').isEmpty) {
      return false;
    }

    final targetType = (data['targetType'] ?? data['groupType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final targetId = (data['targetId'] ?? data['groupId'] ?? '')
        .toString()
        .trim();

    if (targetType.isEmpty || targetId.isEmpty) return false;
    return targetType == _activeTargetType && targetId == _activeTargetId;
  }
}
