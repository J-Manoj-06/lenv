/// Poll Model for Chat Polls
/// Stores poll data in Firestore messages collection
/// Path: chats/{chatId}/messages/{messageId} or communities/{id}/messages/{messageId}
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class PollOption {
  final String id;
  final String text;
  final int voteCount;

  PollOption({required this.id, required this.text, this.voteCount = 0});

  Map<String, dynamic> toMap() {
    return {'id': id, 'text': text, 'voteCount': voteCount};
  }

  factory PollOption.fromMap(Map<String, dynamic> map) {
    return PollOption(
      id: map['id'] as String,
      text: map['text'] as String,
      voteCount: map['voteCount'] as int? ?? 0,
    );
  }

  PollOption copyWith({String? id, String? text, int? voteCount}) {
    return PollOption(
      id: id ?? this.id,
      text: text ?? this.text,
      voteCount: voteCount ?? this.voteCount,
    );
  }
}

class PollModel {
  final String? id; // Message ID (null when creating)
  final String question;
  final List<PollOption> options;
  final bool allowMultiple;
  final String createdBy;
  final String createdByName;
  final String createdByRole;
  final DateTime? createdAt;
  final Map<String, List<String>> voters; // userId => list of optionIds

  PollModel({
    this.id,
    required this.question,
    required this.options,
    this.allowMultiple = false,
    required this.createdBy,
    required this.createdByName,
    required this.createdByRole,
    this.createdAt,
    this.voters = const {},
  });

  /// Total vote count across all options
  int get totalVotes {
    return options.fold(0, (sum, option) => sum + option.voteCount);
  }

  /// Get options the current user voted for
  List<String> getUserVotes(String userId) {
    return voters[userId] ?? [];
  }

  /// Check if user has voted for a specific option
  bool hasUserVoted(String userId, String optionId) {
    final userVotes = voters[userId] ?? [];
    return userVotes.contains(optionId);
  }

  /// Check if user has voted at all
  bool hasUserVotedAny(String userId) {
    final userVotes = voters[userId] ?? [];
    return userVotes.isNotEmpty;
  }

  /// Convert to Firestore document (for message)
  Map<String, dynamic> toMessageMap() {
    return {
      'type': 'poll',
      'question': question,
      'options': options.map((o) => o.toMap()).toList(),
      'allowMultiple': allowMultiple,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'createdByRole': createdByRole,
      'senderId': createdBy, // Compatibility with existing message structure
      'senderName': createdByName,
      'senderRole': createdByRole,
      'content': 'Poll: $question', // For message list preview
      'message': 'Poll: $question', // Compatibility
      'text': 'Poll: $question', // Compatibility
      'createdAt': FieldValue.serverTimestamp(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'voters': voters,
      'isEdited': false,
      'isDeleted': false,
      'reactions': {},
    };
  }

  /// Create from Firestore document
  factory PollModel.fromMap(Map<String, dynamic> map, String documentId) {
    Map<String, dynamic> asStringDynamicMap(dynamic raw) {
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) {
        final mapped = <String, dynamic>{};
        raw.forEach((k, v) {
          mapped[k.toString()] = v;
        });
        return mapped;
      }
      return <String, dynamic>{};
    }

    final optionsList =
        (map['options'] as List<dynamic>?)
            ?.map((o) => PollOption.fromMap(asStringDynamicMap(o)))
            .toList() ??
        [];

    // Parse voters map
    final votersMap = <String, List<String>>{};
    final votersData = asStringDynamicMap(map['voters']);
    votersData.forEach((key, value) {
      if (value is List) {
        votersMap[key] = value.map((e) => e.toString()).toList();
      }
    });

    // Handle createdAt - can be Timestamp or int (milliseconds)
    DateTime? createdAt;
    final createdAtField = map['createdAt'];
    if (createdAtField is Timestamp) {
      createdAt = createdAtField.toDate();
    } else if (createdAtField is int) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(createdAtField);
    } else if (map['timestamp'] is int) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int);
    }

    return PollModel(
      id: documentId,
      question: map['question'] as String? ?? '',
      options: optionsList,
      allowMultiple: map['allowMultiple'] as bool? ?? false,
      createdBy:
          map['createdBy'] as String? ?? map['senderId'] as String? ?? '',
      createdByName:
          map['createdByName'] as String? ?? map['senderName'] as String? ?? '',
      createdByRole:
          map['createdByRole'] as String? ?? map['senderRole'] as String? ?? '',
      createdAt: createdAt,
      voters: votersMap,
    );
  }

  PollModel copyWith({
    String? id,
    String? question,
    List<PollOption>? options,
    bool? allowMultiple,
    String? createdBy,
    String? createdByName,
    String? createdByRole,
    DateTime? createdAt,
    Map<String, List<String>>? voters,
  }) {
    return PollModel(
      id: id ?? this.id,
      question: question ?? this.question,
      options: options ?? this.options,
      allowMultiple: allowMultiple ?? this.allowMultiple,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      createdByRole: createdByRole ?? this.createdByRole,
      createdAt: createdAt ?? this.createdAt,
      voters: voters ?? this.voters,
    );
  }
}
