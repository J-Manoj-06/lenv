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
      final existingDocs = <DocumentSnapshot<Map<String, dynamic>>>[];

      // Always inspect direct doc IDs for aliases (covers legacy docs without userId field).
      for (final alias in aliasSet) {
        final aliasRef = target.reactionsRef.doc(alias);
        final liveAlias = await tx.get(aliasRef);
        if (liveAlias.exists) {
          existingDocs.add(liveAlias);
        }
      }

      for (final doc in prefetchedDocs) {
        final live = await tx.get(doc.reference);
        if (!live.exists) continue;
        final liveUserId = live.data()?['userId']?.toString().trim() ?? '';
        final alreadyAdded = existingDocs.any((e) => e.reference.path == live.reference.path);
        if (aliasSet.contains(liveUserId) && !alreadyAdded) {
          existingDocs.add(live);
        }
      }

      String? previousEmoji;
      for (final doc in existingDocs) {
        if (doc.id == userId) {
          final map = doc.data();
          previousEmoji = map == null ? null : map['emoji']?.toString();
          break;
        }
      }
      if (previousEmoji == null && existingDocs.isNotEmpty) {
        final firstMap = existingDocs.first.data();
        previousEmoji = firstMap == null ? null : firstMap['emoji']?.toString();
      }

      final summary = _coerceSummary(messageSnap.data());

      // Clean up any previous reactions from alias IDs before applying new state.
      for (final doc in existingDocs) {
        final map = doc.data();
        final existingEmoji = map == null ? null : map['emoji']?.toString();
        if (existingEmoji != null && existingEmoji.isNotEmpty) {
          _decrement(summary, existingEmoji);
        }
        tx.delete(doc.reference);
      }

      if (previousEmoji == emoji && existingDocs.isNotEmpty) {
        // Same emoji tapped: fully toggle off after cleanup.
      } else {
        summary[emoji] = (summary[emoji] ?? 0) + 1;
        tx.set(reactionDocRef, {
          'emoji': emoji,
          'userId': userId,
          'reactedAt': FieldValue.serverTimestamp(),
        });
      }

      tx.set(target.messageRef, {
        'reactionSummary': summary,
        'reactionCount': summary.values.fold<int>(0, (sum, v) => sum + v),
        'reactionUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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
      if (emoji.isNotEmpty) {
        if (alias == userId) return emoji;
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

  Map<String, int> _coerceSummary(Map<String, dynamic>? data) {
    final out = <String, int>{};

    final dynamicSummary = data?['reactionSummary'];
    if (dynamicSummary is Map) {
      for (final entry in dynamicSummary.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (key.isEmpty) continue;
        if (value is int && value > 0) {
          out[key] = value;
        } else if (value is num && value > 0) {
          out[key] = value.toInt();
        }
      }
      if (out.isNotEmpty) return out;
    }

    final legacy = data?['reactions'];
    if (legacy is Map) {
      for (final entry in legacy.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (key.isEmpty) continue;
        if (value is List) {
          final count = value.where((e) => e != null).length;
          if (count > 0) {
            out[key] = count;
          }
        }
      }
    }

    return out;
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
