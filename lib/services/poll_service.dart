/// Poll Service - Handles poll creation, voting, and real-time updates
/// Uses Firestore transactions to ensure vote count consistency
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/poll_model.dart';

class PollService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Send a poll message to a chat
  /// chatType: 'community', 'group', 'individual', 'staff_room'
  Future<String> sendPoll({
    required String chatId,
    required PollModel poll,
    required String chatType,
  }) async {
    print('🟣 PollService.sendPoll called');
    print('🟣 Chat ID: $chatId');
    print('🟣 Chat Type: $chatType');
    print('🟣 Poll question: ${poll.question}');
    try {
      DocumentReference messageRef;

      // Determine the correct path based on chat type
      if (chatType == 'community') {
        print('🟣 Using community path');
        messageRef = _firestore
            .collection('communities')
            .doc(chatId)
            .collection('messages')
            .doc();
      } else if (chatType == 'group') {
        print('🟣 Using group path');
        messageRef = _firestore
            .collection('parent_teacher_groups')
            .doc(chatId)
            .collection('messages')
            .doc();
      } else if (chatType == 'staff_room') {
        print('🟣 Using staff_room path');
        messageRef = _firestore
            .collection('staff_rooms')
            .doc(chatId)
            .collection('messages')
            .doc();
      } else {
        print('🟣 Using conversations path');
        // Individual chat (conversations)
        messageRef = _firestore
            .collection('conversations')
            .doc(chatId)
            .collection('messages')
            .doc();
      }

      print('🟣 Message ref path: ${messageRef.path}');
      final messageData = poll.toMessageMap();
      messageData['id'] = messageRef.id;
      print('🟣 Message data prepared, ID: ${messageRef.id}');

      // Write poll message
      print('🟣 Writing to Firestore...');
      await messageRef.set(messageData);
      print('🟣 ✅ Poll message written to Firestore');

      // Update last message in parent document (if needed)
      print('🟣 Updating last message...');
      await _updateLastMessage(chatId, chatType, messageRef.id, poll.question);
      print('🟣 ✅ Last message updated');

      return messageRef.id;
    } catch (e) {
      print('🟣 ❌ Error in sendPoll: $e');
      print('🟣 Stack trace: ${StackTrace.current}');
      throw Exception('Failed to send poll: $e');
    }
  }

  /// Update last message in parent document
  Future<void> _updateLastMessage(
    String chatId,
    String chatType,
    String messageId,
    String question,
  ) async {
    try {
      DocumentReference parentRef;

      if (chatType == 'community') {
        parentRef = _firestore.collection('communities').doc(chatId);
      } else if (chatType == 'group') {
        parentRef = _firestore.collection('parent_teacher_groups').doc(chatId);
      } else if (chatType == 'staff_room') {
        parentRef = _firestore.collection('staff_rooms').doc(chatId);
      } else {
        parentRef = _firestore.collection('conversations').doc(chatId);
      }

      await parentRef.update({
        'lastMessage': 'Poll: $question',
        'lastTimestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Non-critical error - poll was sent successfully
      print('Warning: Failed to update last message: $e');
    }
  }

  /// Get real-time poll stream
  Stream<PollModel?> pollStream({
    required String chatId,
    required String messageId,
    required String chatType,
  }) {
    DocumentReference messageRef;

    if (chatType == 'community') {
      messageRef = _firestore
          .collection('communities')
          .doc(chatId)
          .collection('messages')
          .doc(messageId);
    } else if (chatType == 'group') {
      messageRef = _firestore
          .collection('parent_teacher_groups')
          .doc(chatId)
          .collection('messages')
          .doc(messageId);
    } else {
      messageRef = _firestore
          .collection('conversations')
          .doc(chatId)
          .collection('messages')
          .doc(messageId);
    }

    return messageRef.snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      final data = snapshot.data() as Map<String, dynamic>?;
      if (data == null || data['type'] != 'poll') return null;
      return PollModel.fromMap(data, snapshot.id);
    });
  }

  /// Vote on a poll option
  /// Uses Firestore transaction to ensure consistency
  Future<void> vote({
    required String chatId,
    required String messageId,
    required String optionId,
    required String userId,
    required String chatType,
    required bool allowMultiple,
  }) async {
    DocumentReference messageRef;

    if (chatType == 'community') {
      messageRef = _firestore
          .collection('communities')
          .doc(chatId)
          .collection('messages')
          .doc(messageId);
    } else if (chatType == 'group') {
      messageRef = _firestore
          .collection('parent_teacher_groups')
          .doc(chatId)
          .collection('messages')
          .doc(messageId);
    } else if (chatType == 'staff_room') {
      messageRef = _firestore
          .collection('staff_rooms')
          .doc(chatId)
          .collection('messages')
          .doc(messageId);
    } else {
      messageRef = _firestore
          .collection('conversations')
          .doc(chatId)
          .collection('messages')
          .doc(messageId);
    }

    // Retry up to 3 times with exponential backoff
    int retries = 0;
    const maxRetries = 3;

    while (retries < maxRetries) {
      try {
        await _firestore.runTransaction((transaction) async {
          // Read current poll data
          final snapshot = await transaction.get(messageRef);
          if (!snapshot.exists) {
            throw Exception('Poll message not found');
          }

          final data = snapshot.data() as Map<String, dynamic>;
          final poll = PollModel.fromMap(data, messageId);

          // Get current user votes
          final currentVotes = List<String>.from(poll.voters[userId] ?? []);
          final newVotes = <String>[];

          // Calculate new votes and vote count changes
          final voteChanges = <String, int>{}; // optionId => change (+1 or -1)

          if (allowMultiple) {
            // Multi-select: toggle the option
            if (currentVotes.contains(optionId)) {
              // Remove vote
              newVotes.addAll(currentVotes.where((id) => id != optionId));
              voteChanges[optionId] = -1;
            } else {
              // Add vote
              newVotes.addAll(currentVotes);
              newVotes.add(optionId);
              voteChanges[optionId] = 1;
            }
          } else {
            // Single-select: replace vote
            if (currentVotes.contains(optionId)) {
              // Clicking same option - no change (or could toggle off)
              // For better UX, we'll keep it selected (no-op)
              return;
            } else {
              // Remove old vote (if any)
              if (currentVotes.isNotEmpty) {
                for (final oldVote in currentVotes) {
                  voteChanges[oldVote] = -1;
                }
              }
              // Add new vote
              newVotes.add(optionId);
              voteChanges[optionId] = 1;
            }
          }

          // Update options with new vote counts
          final updatedOptions = poll.options.map((option) {
            final change = voteChanges[option.id] ?? 0;
            if (change != 0) {
              return option.copyWith(
                voteCount: (option.voteCount + change)
                    .clamp(0, double.infinity)
                    .toInt(),
              );
            }
            return option;
          }).toList();

          // Update voters map
          final updatedVoters = Map<String, dynamic>.from(poll.voters);
          if (newVotes.isEmpty) {
            updatedVoters.remove(userId);
          } else {
            updatedVoters[userId] = newVotes;
          }

          // Write updated data
          transaction.update(messageRef, {
            'options': updatedOptions.map((o) => o.toMap()).toList(),
            'voters': updatedVoters,
          });
        });

        // Success - exit retry loop
        return;
      } catch (e) {
        retries++;
        if (retries >= maxRetries) {
          throw Exception('Failed to vote after $maxRetries attempts: $e');
        }
        // Exponential backoff
        await Future.delayed(Duration(milliseconds: 100 * (1 << retries)));
      }
    }
  }

  /// Get poll by message ID (one-time read)
  Future<PollModel?> getPoll({
    required String chatId,
    required String messageId,
    required String chatType,
  }) async {
    try {
      DocumentSnapshot snapshot;

      if (chatType == 'community') {
        snapshot = await _firestore
            .collection('communities')
            .doc(chatId)
            .collection('messages')
            .doc(messageId)
            .get();
      } else if (chatType == 'group') {
        snapshot = await _firestore
            .collection('parent_teacher_groups')
            .doc(chatId)
            .collection('messages')
            .doc(messageId)
            .get();
      } else if (chatType == 'staff_room') {
        snapshot = await _firestore
            .collection('staff_rooms')
            .doc(chatId)
            .collection('messages')
            .doc(messageId)
            .get();
      } else {
        snapshot = await _firestore
            .collection('conversations')
            .doc(chatId)
            .collection('messages')
            .doc(messageId)
            .get();
      }

      if (!snapshot.exists) return null;
      final data = snapshot.data() as Map<String, dynamic>?;
      if (data == null || data['type'] != 'poll') return null;
      return PollModel.fromMap(data, snapshot.id);
    } catch (e) {
      print('Error fetching poll: $e');
      return null;
    }
  }
}
