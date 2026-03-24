import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'connectivity_service.dart';

/// WhatsApp-style pending announcement queue.
/// Queue is persisted in SharedPreferences so it survives app restarts.
/// When connectivity is restored the pending items are flushed automatically.
class PendingAnnouncementService {
  static final PendingAnnouncementService _instance =
      PendingAnnouncementService._internal();

  factory PendingAnnouncementService() => _instance;
  PendingAnnouncementService._internal();

  static const _prefKey = 'pending_announcements';

  StreamSubscription<bool>? _connectivitySub;
  bool _flushing = false;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Enqueue an announcement (no images – those must be uploaded before queuing).
  /// [data] must be JSON-serialisable (no Timestamps; use ISO strings instead).
  Future<void> enqueue(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    final List<dynamic> list = raw != null ? jsonDecode(raw) : [];
    list.add(data);
    await prefs.setString(_prefKey, jsonEncode(list));
    _startWatching();
  }

  Future<int> get pendingCount async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null || raw.isEmpty) return 0;
    return (jsonDecode(raw) as List).length;
  }

  /// Immediately flush if online, otherwise start watching.
  void startProcessing() {
    if (ConnectivityService().isOnline) {
      _flush();
    } else {
      _startWatching();
    }
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _startWatching() {
    _connectivitySub?.cancel();
    _connectivitySub = ConnectivityService().onConnectivityChanged.listen((
      isOnline,
    ) {
      if (isOnline) _flush();
    });
  }

  Future<void> _flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw == null || raw.isEmpty) return;

      final List<dynamic> list = jsonDecode(raw);
      if (list.isEmpty) return;

      final remaining = <dynamic>[];

      for (final item in list) {
        try {
          final data = Map<String, dynamic>.from(item as Map);

          // Restore server-side fields
          data['createdAt'] = FieldValue.serverTimestamp();

          // expiresAt was stored as ISO string; convert back to Timestamp
          if (data['expiresAt'] is String) {
            final dt = DateTime.tryParse(data['expiresAt'] as String);
            if (dt != null) data['expiresAt'] = Timestamp.fromDate(dt);
          }

          final docRef = await FirebaseFirestore.instance
              .collection(data['_collection'] as String? ?? 'class_highlights')
              .add(
                data
                  ..remove('_collection')
                  ..remove('_createViewsPlaceholder'),
              );

          // Announcement notifications are intentionally disabled.
          debugPrint(
            'ℹ️ [PendingAnnouncement] Skipped announcement notification for ${docRef.id}',
          );

          debugPrint('✅ [PendingAnnouncement] Flushed queued announcement');
        } catch (e) {
          debugPrint(
            '⚠️ [PendingAnnouncement] Failed to flush item, keeping: $e',
          );
          remaining.add(item);
        }
      }

      if (remaining.isEmpty) {
        await prefs.remove(_prefKey);
        _connectivitySub?.cancel();
        _connectivitySub = null;
      } else {
        await prefs.setString(_prefKey, jsonEncode(remaining));
      }
    } finally {
      _flushing = false;
    }
  }
}
