import 'package:cloud_firestore/cloud_firestore.dart';

class ReactionTarget {
  final DocumentReference<Map<String, dynamic>> messageRef;

  const ReactionTarget._(this.messageRef);

  CollectionReference<Map<String, dynamic>> get reactionsRef =>
      messageRef.collection('reactions');

  static ReactionTarget classSubjectMessage({
    required String classId,
    required String subjectId,
    required String messageId,
  }) {
    return ReactionTarget._(
      FirebaseFirestore.instance
          .collection('classes')
          .doc(classId)
          .collection('subjects')
          .doc(subjectId)
          .collection('messages')
          .doc(messageId),
    );
  }

  static ReactionTarget communityMessage({
    required String communityId,
    required String messageId,
  }) {
    return ReactionTarget._(
      FirebaseFirestore.instance
          .collection('communities')
          .doc(communityId)
          .collection('messages')
          .doc(messageId),
    );
  }

  static ReactionTarget parentTeacherGroupMessage({
    required String groupId,
    required String messageId,
  }) {
    return ReactionTarget._(
      FirebaseFirestore.instance
          .collection('parent_teacher_groups')
          .doc(groupId)
          .collection('messages')
          .doc(messageId),
    );
  }

  static ReactionTarget staffRoomMessage({
    required String staffRoomId,
    required String messageId,
  }) {
    return ReactionTarget._(
      FirebaseFirestore.instance
          .collection('staff_rooms')
          .doc(staffRoomId)
          .collection('messages')
          .doc(messageId),
    );
  }

  static ReactionTarget conversationMessage({
    required String conversationId,
    required String messageId,
  }) {
    return ReactionTarget._(
      FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId),
    );
  }
}

class MessageReactionService {
  MessageReactionService._();

  static final MessageReactionService instance = MessageReactionService._();

  Future<void> toggleReaction({
    required ReactionTarget target,
    required String userId,
    required String emoji,
    List<String> userAliases = const <String>[],
  }) async {
    final reactionDocRef = target.reactionsRef.doc(userId);
    final aliasSet = <String>{
      userId.trim(),
      ...userAliases.map((e) => e.trim()).where((e) => e.isNotEmpty),
    }..removeWhere((e) => e.isEmpty);

    // Transaction API does not support query reads directly, so prefetch candidates first.
    final prefetchedDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
    if (aliasSet.length == 1) {
      final snap = await reactionDocRef.get();
      if (snap.exists) {
        prefetchedDocs.add(snap);
      }
    } else {
      final aliases = aliasSet.toList(growable: false);
      final queryAliases = aliases.length > 10
          ? aliases.take(10).toList(growable: false)
          : aliases;
      final querySnap = await target.reactionsRef
          .where('userId', whereIn: queryAliases)
          .limit(10)
          .get();
      prefetchedDocs.addAll(querySnap.docs);
    }

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final messageSnap = await tx.get(target.messageRef);
      if (!messageSnap.exists) {
        throw StateError('Message no longer exists');
      }

      final messageData = messageSnap.data() ?? const <String, dynamic>{};
      final summary = _parseSummaryFromMessageData(messageData);

      final existingDocs = <DocumentSnapshot<Map<String, dynamic>>>[];

      // Always inspect direct doc IDs for aliases (covers legacy docs without userId field).
      for (final alias in aliasSet) {
        final aliasRef = target.reactionsRef.doc(alias);
        final liveAlias = await tx.get(aliasRef);
        if (liveAlias.exists) {
          final alreadyAdded = existingDocs.any(
            (e) => e.reference.path == liveAlias.reference.path,
          );
          if (!alreadyAdded) {
            existingDocs.add(liveAlias);
          }
        }
      }

      // Include query-prefetched alias docs by userId field.
      for (final doc in prefetchedDocs) {
        final live = await tx.get(doc.reference);
        if (!live.exists) continue;
        final liveUserId = live.data()?['userId']?.toString().trim() ?? '';
        final alreadyAdded = existingDocs.any(
          (e) => e.reference.path == live.reference.path,
        );
        if (aliasSet.contains(liveUserId) && !alreadyAdded) {
          existingDocs.add(live);
        }
      }

      String? previousEmoji;
      for (final doc in existingDocs) {
        if (doc.id == userId) {
          previousEmoji = doc.data()?['emoji']?.toString();
          break;
        }
      }
      if (previousEmoji == null && existingDocs.isNotEmpty) {
        previousEmoji = existingDocs.first.data()?['emoji']?.toString();
      }

      // Decrement the previous reaction once and only delete the canonical
      // reaction doc for the signed-in Firebase UID. Alias docs may use
      // legacy IDs that current rules do not allow this user to delete.
      if (previousEmoji != null && previousEmoji.isNotEmpty) {
        _decrement(summary, previousEmoji);
      }

      for (final doc in existingDocs) {
        if (doc.id == userId) {
          tx.delete(doc.reference);
        }
      }

      if (!(previousEmoji == emoji && existingDocs.isNotEmpty)) {
        summary[emoji] = (summary[emoji] ?? 0) + 1;

        tx.set(reactionDocRef, {
          'emoji': emoji,
          'userId': userId,
          'reactedAt': FieldValue.serverTimestamp(),
        });
      }

      final reactionCount = summary.values.fold<int>(
        0,
        (total, value) => total + value,
      );

      tx.update(target.messageRef, {
        'reactionSummary': summary,
        'reactionCount': reactionCount,
        'reactionUpdatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<String?> getUserReaction({
    required ReactionTarget target,
    required String userId,
    List<String> userAliases = const <String>[],
  }) async {
    final aliasSet = <String>{
      userId.trim(),
      ...userAliases.map((e) => e.trim()).where((e) => e.isNotEmpty),
    }..removeWhere((e) => e.isEmpty);

    // Prefer direct doc ID lookups first (fast + works for legacy docs without userId field).
    for (final alias in aliasSet) {
      final snap = await target.reactionsRef.doc(alias).get();
      if (!snap.exists) continue;
      final value = snap.data()?['emoji'];
      final emoji = value?.toString().trim() ?? '';
      if (emoji.isNotEmpty && alias == userId) {
        return emoji;
      }
    }

    if (aliasSet.length <= 1) {
      return null;
    }

    final aliases = aliasSet.toList(growable: false);
    final queryAliases = aliases.length > 10
        ? aliases.take(10).toList()
        : aliases;
    final querySnap = await target.reactionsRef
        .where('userId', whereIn: queryAliases)
        .limit(10)
        .get();

    if (querySnap.docs.isEmpty) return null;

    for (final doc in querySnap.docs) {
      if (doc.id == userId) {
        final value = doc.data()['emoji'];
        final emoji = value?.toString().trim() ?? '';
        return emoji.isEmpty ? null : emoji;
      }
    }

    final fallback = querySnap.docs.first.data()['emoji'];
    final fallbackEmoji = fallback?.toString().trim() ?? '';
    return fallbackEmoji.isEmpty ? null : fallbackEmoji;
  }

  Map<String, int> _parseSummaryFromMessageData(Map<String, dynamic> data) {
    final summary = <String, int>{};
    final rawSummary = data['reactionSummary'];
    if (rawSummary is Map) {
      for (final entry in rawSummary.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (key.isEmpty) continue;
        if (value is int && value > 0) {
          summary[key] = value;
        } else if (value is num && value > 0) {
          summary[key] = value.toInt();
        }
      }
    }
    return summary;
  }

  void _decrement(Map<String, int> summary, String emoji) {
    final current = summary[emoji] ?? 0;
    if (current <= 1) {
      summary.remove(emoji);
    } else {
      summary[emoji] = current - 1;
    }
  }
}
