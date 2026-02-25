import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/link_utils.dart';
import '../../models/group_chat_message.dart';
import '../../services/group_messaging_service.dart';
import '../../services/community_service.dart' hide MessageSearchPage;
import '../../providers/auth_provider.dart';
import '../../models/user_model.dart';
import '../../providers/unread_count_provider.dart';
import '../../utils/chat_type_config.dart';
import '../../widgets/media_preview_card.dart';
import '../../widgets/multi_image_message_bubble.dart';
import '../../models/media_metadata.dart';
import '../../services/background_upload_service.dart';
import '../create_poll_screen.dart';
import '../../widgets/poll_message_widget.dart';
import '../../models/poll_model.dart';
import '../../utils/message_scroll_highlight_mixin.dart';
// OFFLINE-FIRST IMPORTS
import '../../repositories/local_message_repository.dart';
import '../../services/firebase_message_sync_service.dart';
import '../../models/local_message.dart';
import 'offline_message_search_page.dart';

class CommunityChatPage extends StatefulWidget {
  final String communityId;
  final String communityName;
  final String icon;

  const CommunityChatPage({
    super.key,
    required this.communityId,
    required this.communityName,
    required this.icon,
  });

  @override
  State<CommunityChatPage> createState() => _CommunityChatPageState();
}

class _CommunityChatPageState extends State<CommunityChatPage>
    with MessageScrollAndHighlightMixin, WidgetsBindingObserver {
  final GroupMessagingService _messagingService = GroupMessagingService();
  final CommunityService _communityService = CommunityService();
  final TextEditingController _messageController = TextEditingController();
  late Stream<Timestamp?> _lastReadAtStream;
  final bool _showUnreadDivider = true;
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _isSendingRecording = false; // Prevent multiple simultaneous sends
  String? _recordingPath;
  final ValueNotifier<int> _recordingDuration = ValueNotifier<int>(0);
  Timer? _recordingTimer;

  // OFFLINE-FIRST SERVICES
  late final LocalMessageRepository _localRepo;
  late final FirebaseMessageSyncService _syncService;

  // Track pending scroll request from search
  String? _scrollToMessageId;
  bool _isScrollingToMessage = false;
  bool _userHasScrolled = false;
  double _lastScrollPosition = 0.0;
  int _lastItemCount = 0;
  bool _isProcessingScroll = false;

  // Track if we're initialized
  bool _isInitialized = false;

  // ✅ Cached stream to prevent reloading community on every rebuild
  late final Stream<List<GroupChatMessage>> _messagesStream;

  // ===== Date helpers for day separators =====
  String _formatDayLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    return DateFormat('MMM dd, yyyy').format(dt);
  }

  Widget _buildDayDivider(DateTime dt) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF222222),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            _formatDayLabel(dt),
            style: const TextStyle(
              color: Color(0xFF9E9E9E),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnreadDivider() {
    // Get user role to determine theme color
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userRole = authProvider.currentUser?.role;
    final isPrincipal = userRole == UserRole.institute;
    final themeColor = isPrincipal
        ? const Color(0xFF00A884)
        : const Color(0xFFFF8800);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(
            child: Divider(color: Color(0x339E9E9E), thickness: 1),
          ),
          const SizedBox(width: 8),
          Text(
            'Unread messages',
            style: TextStyle(
              color: themeColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Divider(color: Color(0x339E9E9E), thickness: 1),
          ),
        ],
      ),
    );
  }

  final FocusNode _messageFocusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  bool _showEmojiPicker = false;

  // Optimistic pending uploads (parity with student group chat)
  final List<GroupChatMessage> _pendingMessages = [];
  final Set<String> _uploadingMessageIds = {};
  final Map<String, double> _pendingUploadProgress = {};
  final Map<String, String> _localSenderMediaPaths = {};
  DateTime? _lastMarkedMessageAt;

  // ✅ ValueNotifiers for smooth progress updates without full rebuilds
  final Map<String, ValueNotifier<double>> _progressNotifiers = {};

  // ✅ Message cache for stable instances to prevent widget recreation (reserved for future use)
  // ignore: unused_field
  final Map<String, GroupChatMessage> _messageCache = {};

  // Notification for background uploads
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  int _activeUploads = 0;

  // Selection mode for delete (ValueNotifiers for flicker-free updates)
  final ValueNotifier<Set<String>> _selectedMessages = ValueNotifier({});
  final ValueNotifier<bool> _isSelectionMode = ValueNotifier(false);

  // Timer to poll cache for progress updates
  Timer? _progressPollTimer;

  // Throttle setState calls to prevent excessive rebuilds
  Timer? _rebuildThrottleTimer;
  bool _pendingRebuild = false;

  // Throttle cache updates to prevent excessive disk writes
  final Map<String, double> _lastSavedProgress = {};

  // Track last upload timestamp to maintain message order
  int _lastUploadTimestamp = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _messageController.addListener(() => setState(() {}));
    _messageFocusNode.addListener(() {
      if (_messageFocusNode.hasFocus && _showEmojiPicker) {
        setState(() => _showEmojiPicker = false);
      }
    });

    // ✅ Initialize cached messages stream (prevents reloading on rebuild)
    _messagesStream = _messagingService.getCommunityMessages(
      widget.communityId,
    );

    // Initialize offline-first services
    _initOfflineFirst();

    // Listen to scroll events to detect user scrolling
    scrollController.addListener(_onScroll);

    // Start polling for progress updates every 2 seconds
    _startProgressPolling();

    // Initialize background upload service
    _initBackgroundUploadService();

    // Setup last read stream for unread divider
    _setupLastReadStream();

    // Scroll to bottom on initial load only and mark as read after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(force: true);
      // Mark as read and refresh unread counts after frame
      _markAsRead();
      try {
        final unread = Provider.of<UnreadCountProvider>(context, listen: false);
        unread.refreshChat(widget.communityId);
      } catch (_) {}
      // Mark as initialized
      _isInitialized = true;
      print('✅ [LIFECYCLE] Community chat page initialized');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print(
      '🔄 [LIFECYCLE] App state changed: $state (isInitialized: $_isInitialized)',
    );
    if (state == AppLifecycleState.resumed && _isInitialized) {
      print('🔄 [LIFECYCLE] App RESUMED - reloading pending messages');
      print(
        '   Current pending count before reload: ${_pendingMessages.length}',
      );
      _loadPendingMessages().then((_) {
        print('🔄 [LIFECYCLE] Pending messages reloaded');
        print('   Pending count after reload: ${_pendingMessages.length}');
      });
    }
  }

  void _startProgressPolling() {
    _progressPollTimer?.cancel();
    _progressPollTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_pendingMessages.isNotEmpty) {
        _checkCacheForProgressUpdates();
      }
    });
  }

  Future<void> _showUploadNotification(double progress) async {
    final progressPercent = (progress * 100).toInt();

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'upload_channel',
          'File Uploads',
          channelDescription: 'Shows progress of file uploads',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          showProgress: true,
          maxProgress: 100,
          progress: progressPercent,
          playSound: false,
          enableVibration: false,
        );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      998, // Fixed ID for community upload notification
      'Uploading to Community',
      progressPercent < 100
          ? 'Upload in progress... $progressPercent%'
          : 'Upload complete',
      notificationDetails,
    );
  }

  Future<void> _cancelUploadNotification() async {
    await _flutterLocalNotificationsPlugin.cancel(998);
  }

  void _initBackgroundUploadService() async {
    await BackgroundUploadService().initialize();

    // Track upload progress and show persistent notification
    BackgroundUploadService()
        .onUploadProgress = (messageId, isUploading, progress) async {
      if (!mounted) return;

      // ✅ Update ValueNotifier for smooth progress (milestone-based)
      final milestones = [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0];
      if (_progressNotifiers[messageId] != null) {
        final currentValue = _progressNotifiers[messageId]!.value;
        // Only update on significant changes to prevent excessive redraws
        if ((progress - currentValue).abs() > 0.05 ||
            milestones.any((m) => (progress - m).abs() < 0.01)) {
          _progressNotifiers[messageId]!.value = progress;
        }
      } else if (isUploading) {
        // Create notifier if it doesn't exist
        _progressNotifiers[messageId] = ValueNotifier<double>(progress);
      }

      _throttledSetState(() {
        if (isUploading) {
          if (!_uploadingMessageIds.contains(messageId)) {
            _activeUploads++;
          }
          _uploadingMessageIds.add(messageId);
          _pendingUploadProgress[messageId] = progress;

          // Update cache with progress so it survives navigation
          _updateCachedProgress(messageId, progress);
        } else {
          // Upload to R2 complete - but DON'T remove pending message yet!
          // Keep it until Firestore sync completes (message appears in stream)
          if (_uploadingMessageIds.contains(messageId)) {
            _activeUploads--;
          }
          _uploadingMessageIds.remove(messageId);
          _pendingUploadProgress.remove(messageId);

          // ✅ Dispose ValueNotifier when upload complete
          _progressNotifiers[messageId]?.dispose();
          _progressNotifiers.remove(messageId);
        }
      });

      // Show/update persistent notification
      if (_activeUploads > 0) {
        await _showUploadNotification(progress);
      } else {
        await _cancelUploadNotification();
      }

      // Save progress to cache at 5% intervals
      final progressPercent = (progress * 100).round();
      if (isUploading && (progressPercent % 5 == 0 || progressPercent == 100)) {
        try {
          // Find the group message ID from this media ID
          String? groupMessageId;
          for (final pending in _pendingMessages) {
            if (pending.multipleMedia != null) {
              for (final media in pending.multipleMedia!) {
                if (media.messageId == messageId) {
                  groupMessageId = pending.id.replaceFirst('pending:', '');
                  break;
                }
              }
            }
            if (groupMessageId != null) break;
          }

          if (groupMessageId != null) {
            final cachedMsg = await _localRepo.getMessageById(groupMessageId);
            if (cachedMsg != null && cachedMsg.multipleMedia != null) {
              final updatedMedia = cachedMsg.multipleMedia!.map((media) {
                if (media['messageId'] == messageId) {
                  return {...media, 'uploadProgress': progress};
                }
                return media;
              }).toList();

              final updatedMsg = LocalMessage(
                messageId: cachedMsg.messageId,
                chatId: cachedMsg.chatId,
                chatType: cachedMsg.chatType,
                senderId: cachedMsg.senderId,
                senderName: cachedMsg.senderName,
                timestamp: cachedMsg.timestamp,
                messageText: cachedMsg.messageText,
                multipleMedia: updatedMedia,
                isPending: true,
              );
              await _localRepo.saveMessage(updatedMsg);
            }
          }
        } catch (e) {
          // Silent fail - progress still updates in UI
        }
      }
    };

    // Handle group upload completion
    BackgroundUploadService().onGroupComplete = (groupId) async {
      print(
        '🎉 Group upload complete: $groupId - Waiting for Firestore sync...',
      );

      // Delete pending message from cache
      try {
        await _localRepo.deletePendingMessage(groupId);
        print('💾 Deleted pending message from cache: $groupId');
      } catch (e) {
        print('⚠️ Failed to delete pending message from cache: $e');
      }

      // DON'T remove pending message here - let Firestore sync handle it
      // Clean up tracking data only
      if (mounted) {
        setState(() {
          _uploadingMessageIds.removeWhere((id) => id.startsWith(groupId));
          _pendingUploadProgress.removeWhere((k, v) => k.startsWith(groupId));
          _localSenderMediaPaths.removeWhere((k, v) => k.startsWith(groupId));

          // ✅ Dispose ValueNotifiers for this group
          _progressNotifiers.forEach((id, notifier) {
            if (id.startsWith(groupId)) {
              notifier.dispose();
            }
          });
          _progressNotifiers.removeWhere((k, v) => k.startsWith(groupId));
        });
      }
    };
  }

  // Throttled setState to prevent excessive rebuilds
  void _throttledSetState(VoidCallback fn) {
    fn(); // Apply state change immediately

    if (_pendingRebuild) return; // Already scheduled

    _pendingRebuild = true;
    _rebuildThrottleTimer?.cancel();
    _rebuildThrottleTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) {
        _pendingRebuild = false;
        setState(() {});
      }
    });
  }

  // Update cached message with latest upload progress
  // Throttled: Only saves if progress changed by 5% or reached 100%
  void _updateCachedProgress(String mediaId, double progress) async {
    try {
      // Throttle: Only update cache if progress changed by 5% or completed
      final lastSaved = _lastSavedProgress[mediaId] ?? 0.0;
      final progressDiff = (progress - lastSaved).abs();
      final shouldSave = progressDiff >= 0.05 || progress >= 1.0;

      if (!shouldSave) return; // Skip this update

      // Update tracking
      _lastSavedProgress[mediaId] = progress;

      // Find which pending message this media belongs to
      for (final pendingMsg in _pendingMessages) {
        if (pendingMsg.multipleMedia == null) continue;

        for (final media in pendingMsg.multipleMedia!) {
          if (media.messageId == mediaId) {
            // Found the media item - get parent message ID
            final parentMessageId = pendingMsg.id.replaceFirst('pending:', '');

            // Load message from cache
            final cachedMsg = await _localRepo.getMessageById(parentMessageId);
            if (cachedMsg != null && cachedMsg.multipleMedia != null) {
              // Update progress in the cached message
              final updatedMedia = cachedMsg.multipleMedia!.map((m) {
                if (m['messageId'] == mediaId) {
                  return {...m, 'uploadProgress': progress};
                }
                return m;
              }).toList();

              // Save updated message back to cache
              final updatedMessage = LocalMessage(
                messageId: cachedMsg.messageId,
                chatId: cachedMsg.chatId,
                chatType: cachedMsg.chatType,
                senderId: cachedMsg.senderId,
                senderName: cachedMsg.senderName,
                messageText: cachedMsg.messageText,
                timestamp: cachedMsg.timestamp,
                multipleMedia: updatedMedia,
                isPending: cachedMsg.isPending,
              );
              await _localRepo.saveMessage(updatedMessage);
            }
            return;
          }
        }
      }
    } catch (e) {
      // Silent fail - cache update is not critical
    }
  }

  Future<void> _checkCacheForProgressUpdates() async {
    if (_pendingMessages.isEmpty || !mounted) return;

    final toRemove = <String>[];

    for (final pendingMsg in _pendingMessages) {
      final messageId = pendingMsg.id;

      // Skip cache checks for BackgroundUploadService pending messages
      if (messageId.startsWith('pending:')) {
        continue;
      }

      try {
        final cachedMsg = await _localRepo.getMessageById(messageId);

        // If message was deleted from cache, it means upload completed
        // Remove it from UI pending list
        if (cachedMsg == null) {
          toRemove.add(messageId);
          continue;
        }

        if (cachedMsg.multipleMedia == null) continue;

        // If message is no longer marked as pending, remove from UI
        if (cachedMsg.isPending == false) {
          toRemove.add(messageId);
          continue;
        }

        bool hasChanges = false;

        for (final media in cachedMsg.multipleMedia!) {
          final mediaId = media['messageId'] as String?;
          if (mediaId == null) continue;

          // Update progress from cache
          final cachedProgress = media['uploadProgress'] as double?;
          if (cachedProgress != null) {
            final currentProgress = _pendingUploadProgress[mediaId] ?? 0.0;
            if ((cachedProgress - currentProgress).abs() > 0.01) {
              _pendingUploadProgress[mediaId] = cachedProgress;
              hasChanges = true;
            }
          }

          // Check if this media item completed (has publicUrl)
          final publicUrl = media['publicUrl'] as String?;
          if (publicUrl != null && publicUrl.isNotEmpty) {
            // Media completed - update the pending message to show uploaded image
            hasChanges = true;
          }
        }

        if (hasChanges && mounted) {
          setState(() {
            // Update will trigger rebuild with new progress/images
          });
        }
      } catch (e) {
        // Silent fail - cache might be updating
      }
    }

    // Remove completed messages from pending list
    if (toRemove.isNotEmpty && mounted) {
      setState(() {
        _pendingMessages.removeWhere((m) => toRemove.contains(m.id));
        for (final messageId in toRemove) {
          _uploadingMessageIds.removeWhere((id) => id.startsWith(messageId));
          _pendingUploadProgress.removeWhere((k, v) => k.startsWith(messageId));
          _localSenderMediaPaths.removeWhere((k, v) => k.startsWith(messageId));
        }
      });
    }
  }

  void _setupLastReadStream() {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      _lastReadAtStream = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('chatReads')
          .doc(widget.communityId)
          .snapshots()
          .map((doc) {
            if (doc.exists && doc.data() != null && doc['lastReadAt'] != null) {
              return doc['lastReadAt'] as Timestamp?;
            }
            return Timestamp.fromDate(
              DateTime.now().subtract(const Duration(days: 30)),
            );
          });
    } catch (e) {
      _lastReadAtStream = Stream.value(
        Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 30))),
      );
    }
  }

  void _initOfflineFirst() async {
    // Initialize offline-first services
    _localRepo = LocalMessageRepository();
    _syncService = FirebaseMessageSyncService(_localRepo);

    await _localRepo.initialize();

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    if (currentUser != null) {
      // Load pending messages from cache (survive navigation during upload)
      await _loadPendingMessages();
      // Load from cache first (works offline)
      final cachedMessages = await _localRepo.getMessagesForChat(
        widget.communityId,
        limit: 50,
      );

      if (cachedMessages.isEmpty) {
        print('📥 No cache - fetching initial messages from Firebase...');
        await _syncService.initialSyncForChat(
          chatId: widget.communityId,
          chatType: 'community',
          limit: 50,
        );
      } else {
        print(
          '✅ Loaded ${cachedMessages.length} messages from cache (offline-ready)',
        );

        // Sync new messages in background
        _syncService.syncNewMessages(
          chatId: widget.communityId,
          chatType: 'community',
          lastTimestamp: cachedMessages.first.timestamp,
        );
      }

      // Start real-time listener for new messages
      await _syncService.startSyncForChat(
        chatId: widget.communityId,
        chatType: 'community',
        userId: currentUser.uid,
      );
    }
  }

  Future<void> _loadPendingMessages() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    // Load pending messages for this chat from cache
    final pendingMessages = await _localRepo.getPendingMessages(
      chatId: widget.communityId,
      senderId: currentUser.uid,
    );

    if (pendingMessages.isNotEmpty && mounted) {
      setState(() {
        // ✅ CRITICAL: Clear stale state before reload
        _pendingMessages.clear();
        _uploadingMessageIds.clear();
        _pendingUploadProgress.clear();
        _localSenderMediaPaths.clear();

        print(
          '🔄 [LOAD_PENDING] Loading ${pendingMessages.length} pending messages',
        );

        // Convert LocalMessage to GroupChatMessage format
        for (final msg in pendingMessages) {
          if (msg.multipleMedia != null && msg.multipleMedia!.isNotEmpty) {
            // ✅ Detect single file stored in multipleMedia format
            final isSingleFileInMultiMedia =
                msg.multipleMedia!.length == 1 &&
                (msg.multipleMedia!.first['mimeType']?.toString().contains(
                          'pdf',
                        ) ==
                        true ||
                    msg.multipleMedia!.first['mimeType']?.toString().contains(
                          'document',
                        ) ==
                        true ||
                    msg.multipleMedia!.first['mimeType']?.toString().contains(
                          'application',
                        ) ==
                        true);

            if (isSingleFileInMultiMedia) {
              // ✅ Restore as single attachment, not multi-media
              final first = msg.multipleMedia!.first as Map<String, dynamic>;
              final mediaId = first['messageId'] as String?;
              final localPath = first['localPath'] as String?;
              final uploadProgress = first['uploadProgress'] as double? ?? 0.0;

              print(
                '   📄 [SINGLE_FILE] Restoring single file: ${first['originalFileName']}',
              );

              final mediaMetadata = MediaMetadata(
                messageId: mediaId ?? msg.messageId,
                r2Key: first['r2Key'] ?? '',
                publicUrl: first['publicUrl'] ?? '',
                thumbnail: first['thumbnail'] ?? '',
                localPath: localPath ?? '',
                expiresAt: DateTime.now().add(const Duration(days: 30)),
                uploadedAt: DateTime.now(),
                originalFileName: first['originalFileName'] ?? '',
                fileSize: first['fileSize'] ?? 0,
                mimeType: first['mimeType'] ?? 'application/octet-stream',
              );

              _pendingMessages.insert(
                0,
                GroupChatMessage(
                  id: msg.messageId.startsWith('pending:')
                      ? msg.messageId
                      : 'pending:${msg.messageId}', // ✅ Ensure consistent prefix
                  senderId: msg.senderId,
                  senderName: msg.senderName,
                  message: msg.messageText ?? '',
                  timestamp: msg.timestamp,
                  mediaMetadata: mediaMetadata, // Single attachment
                  multipleMedia: null, // NOT multi-media
                ),
              );

              if (mediaId != null) {
                // ✅ Only add if not completed (progress < 1.0)
                if (uploadProgress < 1.0) {
                  _uploadingMessageIds.add(mediaId);
                  if (localPath != null) {
                    _localSenderMediaPaths[mediaId] = localPath;
                  }
                  _pendingUploadProgress[mediaId] = uploadProgress;

                  // ✅ Create ValueNotifier for smooth progress
                  _progressNotifiers[mediaId] = ValueNotifier<double>(
                    uploadProgress,
                  );

                  print(
                    '   📊 Restored single file: $mediaId at ${(uploadProgress * 100).toStringAsFixed(1)}%',
                  );
                } else {
                  print('   ✅ Skipped completed upload: $mediaId');
                }
              }
            } else {
              // ✅ Multi-media message
              _pendingMessages.insert(
                0,
                GroupChatMessage(
                  id: msg.messageId.startsWith('pending:')
                      ? msg.messageId
                      : 'pending:${msg.messageId}', // ✅ Ensure consistent prefix
                  senderId: msg.senderId,
                  senderName: msg.senderName,
                  message: msg.messageText ?? '',
                  timestamp: msg.timestamp,
                  multipleMedia: msg.multipleMedia!.map((m) {
                    return MediaMetadata(
                      messageId: m['messageId'] ?? '',
                      r2Key: m['r2Key'] ?? '',
                      publicUrl: m['publicUrl'] ?? '',
                      thumbnail: m['thumbnail'] ?? '',
                      localPath: m['localPath'] ?? '',
                      expiresAt: DateTime.now().add(const Duration(days: 30)),
                      uploadedAt: DateTime.now(),
                      originalFileName: m['originalFileName'] ?? '',
                      fileSize: m['fileSize'] ?? 0,
                      mimeType: m['mimeType'] ?? 'image/jpeg',
                    );
                  }).toList(),
                ),
              );

              // Restore local file paths, uploading state, and actual progress
              for (final media in msg.multipleMedia!) {
                final mediaId = media['messageId'] as String?;
                final localPath = media['localPath'] as String?;
                final uploadProgress = media['uploadProgress'] as double?;

                if (mediaId != null && uploadProgress != null) {
                  // ✅ Only add if not completed (progress < 1.0)
                  if (uploadProgress < 1.0) {
                    _uploadingMessageIds.add(mediaId);
                    if (localPath != null) {
                      _localSenderMediaPaths[mediaId] = localPath;
                    }
                    _pendingUploadProgress[mediaId] = uploadProgress;

                    // ✅ Create ValueNotifier for smooth progress
                    _progressNotifiers[mediaId] = ValueNotifier<double>(
                      uploadProgress,
                    );

                    print(
                      '   📊 Restored progress for $mediaId: ${(uploadProgress * 100).toStringAsFixed(1)}%',
                    );
                  } else {
                    print('   ✅ Skipped completed upload: $mediaId');
                  }
                }
              }
            }
          }
        }
      });
      print(
        '✅ [LOAD_PENDING] Restored ${pendingMessages.length} pending messages from cache',
      );
    }
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;

    final currentPosition = scrollController.offset;

    // Detect if user manually scrolled
    if ((currentPosition - _lastScrollPosition).abs() > 10.0) {
      if (!_isScrollingToMessage) {
        _userHasScrolled = true;
      }
    }

    // If scrolled to near bottom (within 100px), reset flag
    if (currentPosition < 100) {
      _userHasScrolled = false;
    }

    _lastScrollPosition = currentPosition;
  }

  Future<void> _markAsRead() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser != null) {
        final unread = Provider.of<UnreadCountProvider>(context, listen: false);
        debugPrint(
          '[CommunityChat] 🔔 Marking chat as read: ${widget.communityId}',
        );
        await unread.markChatAsRead(widget.communityId);
        // Force reload unread count for this chat after marking as read
        await unread.loadUnreadCount(
          chatId: widget.communityId,
          chatType: ChatTypeConfig.communityChat,
        );
      }
    } catch (e) {}
  }

  @override
  @override
  void dispose() {
    _isInitialized = false;
    _rebuildThrottleTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);

    // Mark chat as read when leaving to prevent self-unread badges
    try {
      final unread = Provider.of<UnreadCountProvider>(context, listen: false);
      unread.markChatAsRead(widget.communityId);
      _lastMarkedMessageAt = DateTime.now();
    } catch (_) {}

    _messageController.dispose();
    disposeScrollController(); // Use mixin's disposal method
    _messageFocusNode.dispose();
    _audioRecorder.dispose();
    _recordingTimer?.cancel();
    _progressPollTimer?.cancel(); // Cancel progress polling
    _recordingDuration.dispose();

    // Dispose selection notifiers
    _selectedMessages.dispose();
    _isSelectionMode.dispose();

    // ✅ Dispose all ValueNotifiers
    for (final notifier in _progressNotifiers.values) {
      notifier.dispose();
    }
    _progressNotifiers.clear();

    // Cancel upload notification
    _cancelUploadNotification();

    super.dispose();
  }

  void _onEmojiSelected(Emoji emoji) {
    _messageController.text += emoji.emoji;
  }

  void _onBackspacePressed() {
    final text = _messageController.text;
    if (text.isNotEmpty) {
      _messageController.text = text.substring(0, text.length - 1);
    }
  }

  void _scrollToBottom({bool force = false}) {
    // Don't auto-scroll if user has manually scrolled away (unless forced)
    if (!force && _userHasScrolled) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        // Only auto-scroll if user is at bottom (within 100 pixels) or force is true
        if (force || scrollController.offset < 100) {
          scrollController.jumpTo(0);
        }
      }
    });
  }

  void _openSearchPage() async {
    final selectedMessageId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => OfflineMessageSearchPage(
          chatId: widget.communityId,
          chatType: 'community',
        ),
      ),
    );

    // If a message was selected, scroll to it
    if (selectedMessageId != null && mounted) {
      setState(() {
        _scrollToMessageId = selectedMessageId;
      });
    }
  }

  // ========================================
  // ✅ PENDING MESSAGE PERSISTENCE METHODS
  // ========================================

  /// Save pending message to local database for persistence across navigation
  Future<void> _savePendingMessageToLocal(
    Map<String, dynamic> messageData,
  ) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      // ✅ CRITICAL: Store single attachment metadata in multipleMedia format
      // This ensures metadata (file name, size) persists even for single files
      List<dynamic>? metadataList = messageData['multipleMedia'];

      if (metadataList == null && messageData['attachmentName'] != null) {
        // Convert single attachment to multipleMedia format for consistent storage
        metadataList = [
          {
            'messageId':
                (messageData['mediaMessageId'] ?? messageData['messageId'])
                    as String,
            'originalFileName': messageData['attachmentName'] as String,
            'fileSize': messageData['attachmentSize'] as int? ?? 0,
            'mimeType':
                messageData['attachmentType'] as String? ??
                'application/octet-stream',
            'localPath': messageData['localFilePath'] as String?,
            'uploadProgress': 0.0,
          },
        ];
        print(
          '   ✅ Converted single attachment to multipleMedia format for storage',
        );
      }

      final localMsg = LocalMessage(
        messageId: messageData['messageId'] as String,
        chatId: widget.communityId,
        chatType: 'community',
        senderId: currentUser.uid,
        senderName: currentUser.name,
        timestamp: messageData['timestamp'] as int,
        messageText: messageData['text'] as String? ?? '',
        multipleMedia: metadataList,
        isPending: true,
      );

      await _localRepo.saveMessage(localMsg);
      print(
        '💾 [PERSIST] Saved pending message to local DB: ${messageData['messageId']}',
      );
    } catch (e) {
      print('❌ [PERSIST] Failed to save pending message: $e');
    }
  }

  /// Cleanup completed upload from pending state (Reserved for future use)
  /* Future<void> _cleanupUploadedMessage(String messageId) async {
    try {
      // Mark as no longer pending in local DB
      await _localRepo.markMessageAsUploaded(
        chatId: widget.communityId,
        messageId: messageId,
      );
      print('✅ [CLEANUP] Marked message as uploaded in local DB: $messageId');
    } catch (e) {
      print('❌ [CLEANUP] Failed to cleanup message: $e');
    }
  } */

  Future<void> _sendMessage({String? imageUrl}) async {
    final text = _messageController.text.trim();
    if (text.isEmpty && imageUrl == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    if (currentUser == null) return;

    // Clear input immediately for instant feedback
    _messageController.clear();

    // Keep keyboard open after clearing text
    _messageFocusNode.requestFocus();

    try {
      final message = GroupChatMessage(
        id: '',
        senderId: currentUser.uid,
        senderName: currentUser.name,
        message: text,
        imageUrl: imageUrl,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      // Send without blocking UI
      _messagingService.sendCommunityMessage(widget.communityId, message);
      // Don't auto-scroll - let user stay where they are
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
      }
    }
  }

  Future<void> _pickAndSendImages() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage(limit: 5);

    if (pickedFiles.isEmpty) return;

    // Copy files to temporary directory first to avoid file access issues
    final tempFiles = <File>[];
    try {
      for (final pickedFile in pickedFiles) {
        // Read file bytes
        final bytes = await File(pickedFile.path).readAsBytes();

        // Create temp file with unique name
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final extension = pickedFile.path.split('.').last;
        final tempPath =
            '${Directory.systemTemp.path}/upload_$timestamp${tempFiles.length}.$extension';
        final tempFile = File(tempPath);

        // Write bytes to temp file
        await tempFile.writeAsBytes(bytes);
        tempFiles.add(tempFile);
      }

      // Upload directly without preview
      if (mounted) {
        await _uploadMultipleImages(tempFiles);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading images: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }

      // Clean up temp files on error
      for (final tempFile in tempFiles) {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (e) {
          // Ignore cleanup errors
        }
      }
    }
  }

  /// Upload multiple images as a single message
  Future<void> _uploadMultipleImages(List<File> files) async {
    if (files.isEmpty) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    // Ensure each message has unique timestamp to maintain send order
    final now = DateTime.now().millisecondsSinceEpoch;
    final baseTimestamp = now > _lastUploadTimestamp
        ? now
        : _lastUploadTimestamp + 1; // Increment if sending too quickly
    _lastUploadTimestamp = baseTimestamp;

    final groupMessageId =
        'pending_${baseTimestamp}_${currentUser.uid.hashCode}';
    final List<MediaMetadata> mediaList = [];
    final List<String> localPaths = [];

    // Create metadata for each image with local path
    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      if (!file.existsSync()) continue;

      final messageId = '${groupMessageId}_$i';
      final fileSize = await file.length();
      final fileName = file.path.split('/').last;
      final absolutePath = file.absolute.path;
      localPaths.add(absolutePath);

      mediaList.add(
        MediaMetadata(
          messageId: messageId,
          r2Key: 'pending/$messageId',
          publicUrl: '',
          thumbnail: absolutePath,
          localPath: absolutePath,
          originalFileName: fileName,
          fileSize: fileSize,
          mimeType: 'image/jpeg',
          expiresAt: DateTime.now().add(const Duration(days: 30)),
          uploadedAt: DateTime.now(),
        ),
      );
    }

    if (mediaList.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No valid images found')));
      }
      return;
    }

    // Create single pending message with multiple media items
    final pendingMessage = GroupChatMessage(
      id: 'pending:$groupMessageId',
      senderId: currentUser.uid,
      senderName: currentUser.name,
      message: '',
      timestamp: baseTimestamp,
      mediaMetadata: mediaList.first,
      multipleMedia: mediaList.length > 1 ? mediaList : null,
    );

    print('📤 Creating pending message with ${mediaList.length} images');
    print('   Pending ID: $groupMessageId');

    // Save pending message to cache IMMEDIATELY (survives navigation)
    try {
      final pendingLocalMsg = LocalMessage(
        messageId: groupMessageId,
        chatId: widget.communityId,
        chatType: 'community',
        senderId: currentUser.uid,
        senderName: currentUser.name,
        timestamp: baseTimestamp,
        messageText: '',
        multipleMedia: mediaList
            .map(
              (m) => {
                'messageId': m.messageId,
                'localPath': m.localPath,
                'uploadProgress': 0.01,
              },
            )
            .toList(),
        isPending: true,
      );
      await _localRepo.saveMessage(pendingLocalMsg);
      print('💾 Pending message saved to cache (survives navigation)');
    } catch (e) {
      print('⚠️ Failed to cache pending message: $e');
    }

    // Store local file paths BEFORE adding pending message to ensure they're available for rendering
    print('🎯 [MULTI-IMAGE UPLOAD] Initialized:');
    print('   Group Message ID: $groupMessageId');
    print('   Number of images: ${mediaList.length}');
    for (int i = 0; i < mediaList.length; i++) {
      final messageId = mediaList[i].messageId;
      final localPath = localPaths[i];
      _localSenderMediaPaths[messageId] = localPath;
      _pendingUploadProgress[messageId] =
          0.01; // Start at 1% to trigger upload UI
      _uploadingMessageIds.add(messageId);

      // Create progress notifier for each image
      final progressNotifier = ValueNotifier<double>(0.01);
      _progressNotifiers[messageId] = progressNotifier;

      final file = File(localPath);
      print('   Image $i:');
      print('     - messageId: $messageId');
      print('     - localPath: $localPath');
      print('     - exists: ${file.existsSync()}');
      print('     - size: ${(mediaList[i].fileSize ?? 0) / 1024} KB');
    }
    print('   Total uploadingMessageIds: ${_uploadingMessageIds.length}');
    print('   Total localFilePaths: ${_localSenderMediaPaths.length}');
    print('   Total pendingUploadProgress: ${_pendingUploadProgress.length}');

    print('🔍 DEBUG: About to setState with pending message');
    print('   - Message ID: ${pendingMessage.id}');
    print('   - multipleMedia: ${pendingMessage.multipleMedia}');
    print('   - multipleMedia length: ${pendingMessage.multipleMedia?.length}');
    print(
      '   - multipleMedia[0]?.localPath: ${pendingMessage.multipleMedia?.first.localPath}',
    );

    setState(() {
      _pendingMessages.insert(0, pendingMessage);
      print('   ✅ Pending message added (count: ${_pendingMessages.length})');
      print('   📊 Calling setState - widget should rebuild now');
      print('   - First pending message: ${_pendingMessages.first.id}');
      print(
        '   - First pending multipleMedia: ${_pendingMessages.first.multipleMedia}',
      );
    });

    // Add a small delay to ensure setState completes
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      // Use BackgroundUploadService for each image in the group
      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final messageId = '${groupMessageId}_$i';

        await BackgroundUploadService().queueUpload(
          file: file,
          conversationId: widget.communityId,
          senderId: currentUser.uid,
          senderRole: 'student',
          mediaType: 'message',
          chatType: 'community',
          senderName: currentUser.name,
          messageId: messageId,
          groupId: groupMessageId, // Group all images together
        );

        print('✅ Image $i queued for background upload: $messageId');
      }

      print('✅ [MULTI-IMAGE UPLOAD] All ${files.length} images queued');

      // Scroll to bottom to show new message
      _scrollToBottom(force: true);
    } catch (e) {
      // Remove failed pending message
      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere(
            (m) => m.id == 'pending:$groupMessageId',
          );
          for (final media in mediaList) {
            final messageId = media.messageId;
            _uploadingMessageIds.remove(messageId);
            _pendingUploadProgress.remove(messageId);
            _localSenderMediaPaths.remove(messageId);
            _progressNotifiers.remove(messageId)?.dispose();
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading images: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickCamera() async {
    try {
      print('📷 Starting camera...');

      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) {
        print('⚠️ No image captured');
        return;
      }

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser == null) {
        print('❌ User not authenticated');
        return;
      }

      final conversationId = widget.communityId;

      // Ensure each message has unique timestamp to maintain send order
      final now = DateTime.now().millisecondsSinceEpoch;
      final baseTimestamp = now > _lastUploadTimestamp
          ? now
          : _lastUploadTimestamp + 1;
      _lastUploadTimestamp = baseTimestamp;

      final groupMessageId =
          'upload_${baseTimestamp}_${currentUser.uid.hashCode}';
      final messageId = '${groupMessageId}_0';
      final file = File(image.path);

      if (!file.existsSync()) {
        print('⚠️ File does not exist: ${image.path}');
        return;
      }

      final mediaList = [
        MediaMetadata(
          messageId: messageId,
          r2Key: 'pending/$messageId',
          publicUrl: '',
          thumbnail: file.path,
          localPath: file.path,
          expiresAt: DateTime.now().add(const Duration(days: 30)),
          uploadedAt: DateTime.now(),
          originalFileName: file.path.split('/').last,
          fileSize: await file.length(),
          mimeType: 'image/jpeg',
        ),
      ];

      print('✅ Created pending message with camera image');
      final pendingMessage = GroupChatMessage(
        id: 'pending:$groupMessageId',
        senderId: currentUser.uid,
        senderName: currentUser.name,
        message: '',
        timestamp: baseTimestamp,
        mediaMetadata: mediaList.first,
      );

      // ✅ Save pending message to local DB (survives navigation)
      await _savePendingMessageToLocal({
        'messageId': groupMessageId,
        'mediaMessageId': messageId,
        'timestamp': baseTimestamp,
        'text': '',
        'attachmentName': file.path.split('/').last,
        'attachmentSize': await file.length(),
        'attachmentType': 'image/jpeg',
        'localFilePath': file.path,
      });

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        _uploadingMessageIds.add(messageId);
        _pendingUploadProgress[messageId] = 0.01;
        _localSenderMediaPaths[messageId] = file.path;

        // ✅ Create ValueNotifier for smooth progress
        _progressNotifiers[messageId] = ValueNotifier<double>(0.01);
      });

      print('📤 Queueing camera upload for $messageId');
      await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: conversationId,
        senderId: currentUser.uid,
        senderRole: 'student',
        mediaType: 'message',
        chatType: 'community',
        senderName: currentUser.name,
        messageId: messageId,
        groupId: groupMessageId,
      );

      print('✅ Camera upload queued, scrolling to bottom');
      _scrollToBottom(force: true);
    } catch (e) {
      print('❌ Error in _pickCamera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send camera image: $e')),
        );
      }
    }
  }

  void _navigateToPollScreen() {
    print('🔴 _navigateToPollScreen called');
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/create_poll'),
        builder: (_) {
          print('🔴 CreatePollScreen builder executing');
          return CreatePollScreen(
            chatId: widget.communityId,
            chatType: 'community',
            onPollSent: _handlePollSent,
          );
        },
      ),
    );
  }

  /// Handle when a poll is sent - add it to pending messages for immediate display
  void _handlePollSent(PollModel poll, String messageId) {
    print('✅ Poll sent! Adding to pending messages...');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    try {
      // Create pending message for the poll with proper structure
      final now = DateTime.now().millisecondsSinceEpoch;
      final pendingPoll = GroupChatMessage(
        id: messageId,
        senderId: currentUser.uid,
        senderName: currentUser.name,
        message: 'Poll: ${poll.question}',
        timestamp: now,
        isDeleted: false,
        type: 'poll',
        rawData: {
          'type': 'poll',
          'question': poll.question,
          'options': poll.options
              .map(
                (opt) => {
                  'id': opt.id,
                  'text': opt.text,
                  'voteCount': opt.voteCount,
                },
              )
              .toList(),
          'allowMultiple': poll.allowMultiple,
          'createdBy': currentUser.uid,
          'createdByName': currentUser.name,
          'createdByRole': currentUser.role.toString().split('.').last,
          'timestamp': now,
          'createdAt': now,
          'message': 'Poll: ${poll.question}',
          'senderId': currentUser.uid,
          'senderName': currentUser.name,
        },
      );

      // Add to pending messages
      if (mounted) {
        setState(() {
          _pendingMessages.add(pendingPoll);
          print('   ➕ Added pending poll to _pendingMessages');
        });
      }
    } catch (e) {
      print('   ❌ Error handling poll sent: $e');
    }
  }

  void _showAttachmentPicker() {
    final primaryColor = const Color(0xFF00A884); // Community chat green
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? const Color(0xFF222222)
        : const Color(0xFFFFFFFF);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Send Attachment',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAttachmentOption(
                  icon: Icons.image,
                  label: 'Gallery',
                  color: primaryColor,
                  onTap: () {
                    Navigator.pop(bottomSheetContext);
                    _pickAndSendImages();
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  color: primaryColor,
                  onTap: () {
                    Navigator.pop(bottomSheetContext);
                    _pickCamera();
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.picture_as_pdf,
                  label: 'Document',
                  color: primaryColor,
                  onTap: () {
                    Navigator.pop(bottomSheetContext);
                    _pickDocument();
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.audiotrack,
                  label: 'Audio',
                  color: primaryColor,
                  onTap: () {
                    Navigator.pop(bottomSheetContext);
                    _pickAudio();
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.poll,
                  label: 'Poll',
                  color: primaryColor,
                  onTap: () {
                    print('🔴 POLL BUTTON TAPPED');
                    Navigator.pop(bottomSheetContext);
                    _navigateToPollScreen();
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf', // PDF
          'doc', 'docx', // Word
          'xls', 'xlsx', // Excel
          'ppt', 'pptx', // PowerPoint
          'txt', // Text
          'csv', // CSV
          'rtf', // Rich Text Format
          'odt', 'ods', 'odp', // OpenDocument formats
        ],
      );

      if (result != null && result.files.single.path != null) {
        await _sendFileMessage(File(result.files.single.path!));
      }
    } catch (e) {
      print('❌ Error picking document: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send document: $e')));
      }
    }
  }

  Future<void> _pickAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'wav', 'aac'],
      );

      if (result != null && result.files.single.path != null) {
        await _sendFileMessage(File(result.files.single.path!));
      }
    } catch (e) {
      print('❌ Error picking audio: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send audio: $e')));
      }
    }
  }

  Future<void> _sendFileMessage(File file) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      final conversationId = widget.communityId;
      final baseTimestamp = DateTime.now().millisecondsSinceEpoch;
      final groupMessageId =
          'upload_${baseTimestamp}_${currentUser.uid.hashCode}';
      final messageId = '${groupMessageId}_0';

      final fileSize = await file.length();
      final fileName = file.path.split('/').last;

      final mediaList = [
        MediaMetadata(
          messageId: messageId,
          r2Key: 'pending/$messageId',
          publicUrl: '',
          thumbnail: file.path,
          localPath: file.path,
          expiresAt: DateTime.now().add(const Duration(days: 30)),
          uploadedAt: DateTime.now(),
          originalFileName: fileName,
          fileSize: fileSize,
          mimeType: _getMimeType(file.path),
        ),
      ];

      final pendingMessage = GroupChatMessage(
        id: 'pending:$groupMessageId',
        senderId: currentUser.uid,
        senderName: currentUser.name,
        message: '',
        timestamp: baseTimestamp,
        mediaMetadata: mediaList.first,
      );

      // ✅ Save pending message to local DB (survives navigation)
      await _savePendingMessageToLocal({
        'messageId': groupMessageId,
        'mediaMessageId': messageId,
        'timestamp': baseTimestamp,
        'text': '',
        'attachmentName': fileName,
        'attachmentSize': fileSize,
        'attachmentType': _getMimeType(file.path),
        'localFilePath': file.path,
      });

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        _uploadingMessageIds.add(messageId);
        _pendingUploadProgress[messageId] = 0.01;
        _localSenderMediaPaths[messageId] = file.path;

        // ✅ Create ValueNotifier for smooth progress
        _progressNotifiers[messageId] = ValueNotifier<double>(0.01);
      });

      print('📤 Queueing file upload for $messageId');
      await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: conversationId,
        senderId: currentUser.uid,
        senderRole: 'student',
        mediaType: 'message',
        chatType: 'community',
        senderName: currentUser.name,
        messageId: messageId,
        groupId: groupMessageId,
      );

      print('✅ File upload queued, scrolling to bottom');
      _scrollToBottom(force: true);
    } catch (e) {
      print('❌ Error sending file: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send file: $e')));
      }
    }
  }

  String _getMimeType(String filePath) {
    final lower = filePath.toLowerCase();

    // PDF
    if (lower.endsWith('.pdf')) return 'application/pdf';

    // Word
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }

    // Excel
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }

    // PowerPoint
    if (lower.endsWith('.ppt')) return 'application/vnd.ms-powerpoint';
    if (lower.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }

    // Text formats
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.rtf')) return 'application/rtf';

    // OpenDocument
    if (lower.endsWith('.odt')) {
      return 'application/vnd.oasis.opendocument.text';
    }
    if (lower.endsWith('.ods')) {
      return 'application/vnd.oasis.opendocument.spreadsheet';
    }
    if (lower.endsWith('.odp')) {
      return 'application/vnd.oasis.opendocument.presentation';
    }

    // Audio
    if (lower.endsWith('.m4a') || lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.wav')) return 'audio/wav';

    return 'application/octet-stream';
  }

  Future<void> _sendRecording() async {
    if (_recordingPath == null) return;

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      // Stop recording FIRST - this is critical
      if (_isRecording) {
        try {
          await _audioRecorder.stop();
        } catch (e) {}

        try {
          _recordingTimer?.cancel();
        } catch (e) {}
      }

      // IMMEDIATELY update UI to show we're not recording anymore
      setState(() {
        _isRecording = false;
        _isSendingRecording = true;
        _recordingDuration.value = 0;
      });

      final conversationId = widget.communityId;
      final baseTimestamp = DateTime.now().millisecondsSinceEpoch;
      final groupMessageId =
          'upload_${baseTimestamp}_${currentUser.uid.hashCode}';
      final messageId = '${groupMessageId}_0';

      final file = File(_recordingPath!);
      final fileSize = await file.length();

      final mediaList = [
        MediaMetadata(
          messageId: messageId,
          r2Key: 'pending/$messageId',
          publicUrl: '',
          thumbnail: file.path,
          localPath: file.path,
          expiresAt: DateTime.now().add(const Duration(days: 30)),
          uploadedAt: DateTime.now(),
          originalFileName:
              'audio_${DateTime.now().millisecondsSinceEpoch}.m4a',
          fileSize: fileSize,
          mimeType: 'audio/aac',
        ),
      ];

      final pendingMessage = GroupChatMessage(
        id: 'pending:$groupMessageId',
        senderId: currentUser.uid,
        senderName: currentUser.name,
        message: '',
        timestamp: baseTimestamp,
        mediaMetadata: mediaList.first,
      );

      // ✅ Save pending message to local DB (survives navigation)
      await _savePendingMessageToLocal({
        'messageId': groupMessageId,
        'mediaMessageId': messageId,
        'timestamp': baseTimestamp,
        'text': '',
        'attachmentName': 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a',
        'attachmentSize': fileSize,
        'attachmentType': 'audio/aac',
        'localFilePath': file.path,
      });

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        _uploadingMessageIds.add(messageId);
        _pendingUploadProgress[messageId] = 0.01;
        _localSenderMediaPaths[messageId] = file.path;
        _recordingPath = null;
        _isSendingRecording = false;

        // ✅ Create ValueNotifier for smooth progress
        _progressNotifiers[messageId] = ValueNotifier<double>(0.01);
      });

      print('📤 Queueing voice message upload for $messageId');
      await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: conversationId,
        senderId: currentUser.uid,
        senderRole: 'institute',
        mediaType: 'message',
        chatType: 'community',
        senderName: currentUser.name,
        messageId: messageId,
        groupId: groupMessageId,
      );

      print('✅ Voice message queued');
      _scrollToBottom(force: true);
    } catch (e) {
      print('❌ Error sending recording: $e');
      if (mounted) {
        setState(() {
          _isSendingRecording = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send voice message: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = authProvider.currentUser?.uid;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF8FAFC);
    final appBarColor = isDark ? const Color(0xFF141414) : Colors.white;
    final cardColor = isDark
        ? const Color(0xFF222222)
        : const Color(0xFFFFFFFF);
    final inputBgColor = isDark
        ? const Color(0xFF1F2C34)
        : const Color(0xFFF1F5F9);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? Colors.white60 : const Color(0xFF64748B);
    final hintColor = isDark
        ? const Color(0xFF8696A0)
        : const Color(0xFF94A3B8);
    final primaryColor = const Color(0xFF00A884);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        leading: ValueListenableBuilder<bool>(
          valueListenable: _isSelectionMode,
          builder: (context, isSelectionMode, _) {
            return IconButton(
              icon: Icon(
                isSelectionMode ? Icons.close : Icons.arrow_back_ios_new,
                color: isDark ? Colors.white70 : const Color(0xFF475569),
              ),
              onPressed: () {
                if (isSelectionMode) {
                  _isSelectionMode.value = false;
                  _selectedMessages.value = {};
                } else {
                  Navigator.pop(context);
                }
              },
            );
          },
        ),
        title: ValueListenableBuilder<bool>(
          valueListenable: _isSelectionMode,
          builder: (context, isSelectionMode, _) {
            return ValueListenableBuilder<Set<String>>(
              valueListenable: _selectedMessages,
              builder: (context, selectedMessages, _) {
                return isSelectionMode
                    ? Text(
                        '${selectedMessages.length} selected',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : Row(
                        children: [
                          Text(
                            widget.icon,
                            style: const TextStyle(fontSize: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.communityName,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Open Community',
                                  style: TextStyle(
                                    color: subtitleColor,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
              },
            );
          },
        ),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _isSelectionMode,
            builder: (context, isSelectionMode, _) {
              return ValueListenableBuilder<Set<String>>(
                valueListenable: _selectedMessages,
                builder: (context, selectedMessages, _) {
                  return isSelectionMode
                      ? IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                            size: 24,
                          ),
                          onPressed: selectedMessages.isEmpty
                              ? null
                              : _showDeleteDialog,
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Search Icon
                            IconButton(
                              icon: Icon(
                                Icons.search,
                                color: isDark
                                    ? Colors.white70
                                    : const Color(0xFF475569),
                              ),
                              onPressed: _openSearchPage,
                              tooltip: 'Search messages',
                            ),
                            // More options menu
                            PopupMenuButton<String>(
                              icon: Icon(
                                Icons.more_vert,
                                color: isDark
                                    ? Colors.white70
                                    : const Color(0xFF475569),
                              ),
                              onSelected: (value) {
                                if (value == 'leave') {
                                  _showLeaveCommunityDialog();
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'leave',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.exit_to_app,
                                        color: Colors.redAccent,
                                        size: 20,
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        'Leave Community',
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                },
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages List
          Expanded(
            child: StreamBuilder<List<GroupChatMessage>>(
              stream: _messagesStream, // ✅ Use cached stream
              builder: (context, snapshot) {
                // ✅ CRITICAL: Show pending messages immediately while Firestore loads
                if (snapshot.connectionState == ConnectionState.waiting &&
                    _pendingMessages.isEmpty) {
                  return Center(
                    child: CircularProgressIndicator(color: primaryColor),
                  );
                }

                if (snapshot.hasError) {
                  // ✅ Show pending messages even if Firestore has error
                  if (_pendingMessages.isEmpty) {
                    return Center(
                      child: Text(
                        'Error loading messages',
                        style: TextStyle(color: subtitleColor),
                      ),
                    );
                  }
                  // Continue building with pending messages
                }

                // Proceed even while connecting so pending messages render immediately
                final firestoreMessages =
                    snapshot.data ?? const <GroupChatMessage>[];

                if (firestoreMessages.isEmpty && _pendingMessages.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet.\nBe the first to say hello! 👋',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: hintColor),
                    ),
                  );
                }

                return StreamBuilder<Timestamp?>(
                  stream: _lastReadAtStream,
                  builder: (context, readSnapshot) {
                    print('🔍 StreamBuilder rebuilding:');
                    print('   - Pending messages: ${_pendingMessages.length}');
                    for (int i = 0; i < _pendingMessages.length; i++) {
                      final msg = _pendingMessages[i];
                      print(
                        '     [$i] ID: ${msg.id}, multipleMedia: ${msg.multipleMedia?.length}',
                      );
                    }
                    print(
                      '   - Firestore messages: ${firestoreMessages.length}',
                    );

                    final hasValidData = readSnapshot.data != null;
                    final lastReadMs =
                        readSnapshot.data?.toDate().millisecondsSinceEpoch ??
                        DateTime.now()
                            .subtract(const Duration(days: 30))
                            .millisecondsSinceEpoch;

                    // Merge pending + Firestore messages and de-duplicate when server versions arrive
                    final allMessages = <GroupChatMessage>[
                      ..._pendingMessages,
                      ...firestoreMessages,
                    ];
                    print(
                      '   - All messages after merge: ${allMessages.length}',
                    );
                    final uploadingMessageIds = <String>{
                      ..._uploadingMessageIds,
                    };
                    final pendingIdsToRemove = <String>[];

                    allMessages.removeWhere((pendingMsg) {
                      if (!pendingMsg.id.startsWith('pending:')) return false;

                      // ✅ CRITICAL: Extract actual ID from "pending:upload_..." format
                      final pendingId = pendingMsg.id.replaceFirst(
                        'pending:',
                        '',
                      );

                      // 1️⃣ FIRST: Try exact ID matching (highest priority)
                      bool foundExactMatch = false;
                      for (final fsMsg in firestoreMessages) {
                        if (fsMsg.id.startsWith('pending:')) continue;

                        // Check if Firestore doc ID matches our pending ID
                        if (fsMsg.id == pendingId) {
                          foundExactMatch = true;
                          print(
                            '✅ [EXACT_ID_MATCH] Firestore ID matches pending ID: $pendingId',
                          );
                          break;
                        }
                      }

                      if (foundExactMatch) {
                        // Cleanup pending state
                        if (pendingMsg.multipleMedia != null) {
                          for (final pm in pendingMsg.multipleMedia!) {
                            if (pm.localPath != null &&
                                pm.localPath!.isNotEmpty) {
                              _localSenderMediaPaths[pm.messageId] =
                                  pm.localPath!;
                            }
                            _uploadingMessageIds.remove(pm.messageId);
                            _pendingUploadProgress.remove(pm.messageId);
                            _progressNotifiers[pm.messageId]?.dispose();
                            _progressNotifiers.remove(pm.messageId);
                          }
                        }
                        if (pendingMsg.mediaMetadata != null) {
                          final mediaId = pendingMsg.mediaMetadata!.messageId;
                          if (pendingMsg.mediaMetadata!.localPath != null) {
                            _localSenderMediaPaths[mediaId] =
                                pendingMsg.mediaMetadata!.localPath!;
                          }
                          _uploadingMessageIds.remove(mediaId);
                          _pendingUploadProgress.remove(mediaId);
                          _progressNotifiers[mediaId]?.dispose();
                          _progressNotifiers.remove(mediaId);
                        }
                        return true; // Remove pending message
                      }

                      // 2️⃣ FALLBACK: Media ID and attachment matching
                      final pendingMediaIds = <String>{};
                      if (pendingMsg.multipleMedia != null) {
                        pendingMediaIds.addAll(
                          pendingMsg.multipleMedia!.map((m) => m.messageId),
                        );
                      }
                      if (pendingMsg.mediaMetadata != null) {
                        pendingMediaIds.add(
                          pendingMsg.mediaMetadata!.messageId,
                        );
                      }

                      final pendingAttachmentKeys = <String>{};
                      if (pendingMsg.mediaMetadata?.originalFileName != null &&
                          pendingMsg.mediaMetadata?.fileSize != null) {
                        // ✅ Case-insensitive file name matching
                        pendingAttachmentKeys.add(
                          '${pendingMsg.mediaMetadata!.originalFileName!.toLowerCase()}|${pendingMsg.mediaMetadata!.fileSize}',
                        );
                      }
                      if (pendingMsg.multipleMedia != null) {
                        for (final m in pendingMsg.multipleMedia!) {
                          if (m.originalFileName != null &&
                              m.fileSize != null) {
                            // ✅ Case-insensitive file name matching
                            pendingAttachmentKeys.add(
                              '${m.originalFileName!.toLowerCase()}|${m.fileSize}',
                            );
                          }
                        }
                      }

                      final hasMatchingMedia =
                          pendingMediaIds.isNotEmpty &&
                          firestoreMessages.any((fsMsg) {
                            if (fsMsg.id.startsWith('pending:')) return false;
                            final fsMediaIds = <String>{};
                            if (fsMsg.multipleMedia != null) {
                              fsMediaIds.addAll(
                                fsMsg.multipleMedia!.map((m) => m.messageId),
                              );
                            }
                            if (fsMsg.mediaMetadata != null) {
                              fsMediaIds.add(fsMsg.mediaMetadata!.messageId);
                            }
                            if (fsMediaIds.isEmpty) return false;
                            return fsMediaIds.any(pendingMediaIds.contains);
                          });

                      final hasMatchingAttachment =
                          pendingAttachmentKeys.isNotEmpty &&
                          firestoreMessages.any((fsMsg) {
                            if (fsMsg.id.startsWith('pending:')) return false;
                            final fsAttachmentKeys = <String>{};
                            if (fsMsg.mediaMetadata?.originalFileName != null &&
                                fsMsg.mediaMetadata?.fileSize != null) {
                              // ✅ Case-insensitive file name matching
                              fsAttachmentKeys.add(
                                '${fsMsg.mediaMetadata!.originalFileName!.toLowerCase()}|${fsMsg.mediaMetadata!.fileSize}',
                              );
                            }
                            if (fsMsg.multipleMedia != null) {
                              for (final m in fsMsg.multipleMedia!) {
                                if (m.originalFileName != null &&
                                    m.fileSize != null) {
                                  // ✅ Case-insensitive file name matching
                                  fsAttachmentKeys.add(
                                    '${m.originalFileName!.toLowerCase()}|${m.fileSize}',
                                  );
                                }
                              }
                            }
                            if (fsAttachmentKeys.isEmpty) return false;
                            return fsAttachmentKeys.any(
                              pendingAttachmentKeys.contains,
                            );
                          });

                      final isMediaMessage =
                          (pendingMsg.multipleMedia != null &&
                              pendingMsg.multipleMedia!.isNotEmpty) ||
                          pendingMsg.mediaMetadata != null;
                      final hasServerVersion =
                          hasMatchingMedia ||
                          hasMatchingAttachment ||
                          (!isMediaMessage &&
                              firestoreMessages.any((fsMsg) {
                                final senderMatch =
                                    fsMsg.senderId == pendingMsg.senderId;
                                final diff =
                                    (fsMsg.timestamp - pendingMsg.timestamp)
                                        .abs();
                                final timeWindow = 30000;
                                final timeMatch = diff < timeWindow;
                                final isNotPending = !fsMsg.id.startsWith(
                                  'pending:',
                                );
                                return senderMatch && timeMatch && isNotPending;
                              }));

                      if (hasServerVersion) {
                        if (pendingMsg.multipleMedia != null) {
                          for (final pm in pendingMsg.multipleMedia!) {
                            if (pm.localPath != null &&
                                pm.localPath!.isNotEmpty) {
                              _localSenderMediaPaths[pm.messageId] =
                                  pm.localPath!;
                            }
                            _uploadingMessageIds.remove(pm.messageId);
                            _pendingUploadProgress.remove(pm.messageId);
                            // ✅ Dispose ValueNotifiers to prevent memory leaks
                            _progressNotifiers[pm.messageId]?.dispose();
                            _progressNotifiers.remove(pm.messageId);
                          }
                        }
                        if (pendingMsg.mediaMetadata?.localPath != null) {
                          final mediaId = pendingMsg.mediaMetadata!.messageId;
                          _localSenderMediaPaths[mediaId] =
                              pendingMsg.mediaMetadata!.localPath!;
                        }
                        if (pendingMsg.mediaMetadata != null) {
                          final mediaId = pendingMsg.mediaMetadata!.messageId;
                          _uploadingMessageIds.remove(mediaId);
                          _pendingUploadProgress.remove(mediaId);
                          // ✅ Dispose ValueNotifiers to prevent memory leaks
                          _progressNotifiers[mediaId]?.dispose();
                          _progressNotifiers.remove(mediaId);
                        }

                        pendingIdsToRemove.add(pendingMsg.id);
                        return true;
                      }

                      if (pendingMsg.multipleMedia != null &&
                          pendingMsg.multipleMedia!.isNotEmpty) {
                        final anyStillUploading = pendingMsg.multipleMedia!.any(
                          (m) => uploadingMessageIds.contains(m.messageId),
                        );
                        if (anyStillUploading) return false;
                      } else if (pendingMsg.mediaMetadata != null) {
                        if (uploadingMessageIds.contains(
                          pendingMsg.mediaMetadata!.messageId,
                        )) {
                          return false;
                        }
                      }

                      return false;
                    });

                    if (pendingIdsToRemove.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() {
                          _pendingMessages.removeWhere(
                            (m) => pendingIdsToRemove.contains(m.id),
                          );
                        });
                      });
                    }

                    allMessages.sort(
                      (a, b) => b.timestamp.compareTo(a.timestamp),
                    );

                    // Auto-mark as read when newest message is seen and newer than our last mark
                    if (allMessages.isNotEmpty) {
                      final latest = DateTime.fromMillisecondsSinceEpoch(
                        allMessages.first.timestamp,
                      );
                      if (_lastMarkedMessageAt == null ||
                          latest.isAfter(_lastMarkedMessageAt!)) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _markAsRead();
                          _lastMarkedMessageAt = latest;
                        });
                      }
                    }

                    int? unreadDividerIndex;
                    bool hasUnread = false;
                    bool hasRead = false;
                    for (int i = 0; i < allMessages.length; i++) {
                      final isUnread = allMessages[i].timestamp > lastReadMs;
                      hasUnread = hasUnread || isUnread;
                      hasRead = hasRead || !isUnread;
                      if (i > 0) {
                        final prevUnread =
                            allMessages[i - 1].timestamp > lastReadMs;
                        final currUnread = isUnread;
                        if (prevUnread &&
                            !currUnread &&
                            unreadDividerIndex == null) {
                          unreadDividerIndex = i;
                        }
                      }
                    }
                    if (unreadDividerIndex == null && hasUnread && hasRead) {
                      unreadDividerIndex = allMessages.length - 1;
                    }

                    // Handle pending scroll request from search
                    if (_scrollToMessageId != null &&
                        !_isScrollingToMessage &&
                        !_isProcessingScroll) {
                      final messageId = _scrollToMessageId!;
                      _scrollToMessageId = null; // Clear pending request
                      _isScrollingToMessage = true;
                      _userHasScrolled = true;

                      // Convert GroupChatMessage list to Map format for mixin
                      final messagesList = allMessages
                          .map((msg) => {'id': msg.id})
                          .toList();

                      // Schedule scroll after frame is rendered (single callback)
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        if (!mounted) return;

                        await scrollToMessage(messageId, messagesList);

                        // Wait for scroll animation to complete
                        await Future.delayed(const Duration(seconds: 3));
                        if (mounted) {
                          setState(() {
                            _isScrollingToMessage = false;
                            // Keep _userHasScrolled true
                          });
                        }
                      });
                    }

                    // Check if item count changed (avoid redundant callbacks)
                    final itemCountChanged =
                        allMessages.length != _lastItemCount;

                    // Check if should auto-scroll
                    final shouldAutoScroll =
                        itemCountChanged &&
                        allMessages.length > _lastItemCount &&
                        !_userHasScrolled &&
                        !_isScrollingToMessage &&
                        !_isProcessingScroll &&
                        scrollController.hasClients &&
                        scrollController.offset < 100;

                    // Only schedule callback when item count actually changed
                    if (itemCountChanged && !_isProcessingScroll) {
                      _isProcessingScroll = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _lastItemCount = allMessages.length;
                        _isProcessingScroll = false;

                        // Only auto-scroll if all conditions are met
                        if (shouldAutoScroll &&
                            scrollController.hasClients &&
                            !_isScrollingToMessage) {
                          scrollController.animateTo(
                            0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        }
                      });
                    }

                    return ListView.builder(
                      key: const PageStorageKey('community_messages'),
                      controller: scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: allMessages.length,
                      physics: const ClampingScrollPhysics(),
                      itemBuilder: (context, index) {
                        final message = allMessages[index];
                        if (index < 5) {
                          // Log first 5 messages
                          print(
                            '📩 Rendering message $index: ID=${message.id}, multipleMedia=${message.multipleMedia?.length}',
                          );
                        }
                        final isMe = message.senderId == currentUserId;
                        final currentDate = DateTime.fromMillisecondsSinceEpoch(
                          message.timestamp,
                        );
                        final isOldest = index == allMessages.length - 1;
                        final nextDate = isOldest
                            ? null
                            : DateTime.fromMillisecondsSinceEpoch(
                                allMessages[index + 1].timestamp,
                              );
                        final showDayDivider =
                            isOldest ||
                            _formatDayLabel(currentDate) !=
                                _formatDayLabel(nextDate!);

                        final isPending =
                            message.id.startsWith('pending:') ||
                            (message.mediaMetadata?.r2Key.startsWith(
                                  'pending/',
                                ) ??
                                false);
                        final uploadProgress = isPending
                            ? _pendingUploadProgress[message
                                  .mediaMetadata
                                  ?.messageId]
                            : null;

                        return ValueListenableBuilder<bool>(
                          valueListenable: _isSelectionMode,
                          builder: (context, isSelectionMode, _) {
                            return ValueListenableBuilder<Set<String>>(
                              valueListenable: _selectedMessages,
                              builder: (context, selectedMessages, _) {
                                final isSelected = selectedMessages.contains(
                                  message.id,
                                );
                                final isHighlighted =
                                    highlightedMessageId == message.id;

                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_showUnreadDivider &&
                                        hasValidData &&
                                        unreadDividerIndex == index)
                                      _buildUnreadDivider(),
                                    if (showDayDivider)
                                      _buildDayDivider(currentDate),
                                    HighlightedMessageWrapper(
                                      key: getMessageKey(message.id),
                                      isHighlighted: isHighlighted,
                                      child: GestureDetector(
                                        onLongPress: isMe
                                            ? () {
                                                _isSelectionMode.value = true;
                                                _selectedMessages.value = {
                                                  ...selectedMessages,
                                                  message.id,
                                                };
                                              }
                                            : null,
                                        onTap: isSelectionMode && isMe
                                            ? () {
                                                if (isSelected) {
                                                  final newSelection =
                                                      Set<String>.from(
                                                        selectedMessages,
                                                      )..remove(message.id);
                                                  _selectedMessages.value =
                                                      newSelection;
                                                  if (newSelection.isEmpty) {
                                                    _isSelectionMode.value =
                                                        false;
                                                  }
                                                } else {
                                                  _selectedMessages.value = {
                                                    ...selectedMessages,
                                                    message.id,
                                                  };
                                                }
                                              }
                                            : null,
                                        child: _MessageBubble(
                                          message: message,
                                          isMe: isMe,
                                          uploading: isPending,
                                          uploadProgress: uploadProgress,
                                          localSenderMediaPaths:
                                              _localSenderMediaPaths,
                                          uploadingMessageIds:
                                              _uploadingMessageIds,
                                          pendingUploadProgress:
                                              _pendingUploadProgress,
                                          selectionMode: isSelectionMode,
                                          isSelected: isSelected,
                                          communityId: widget.communityId,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),

          // Input Bar with Recording UI
          if (_isRecording)
            ValueListenableBuilder<int>(
              valueListenable: _recordingDuration,
              builder: (context, duration, _) {
                final minutes = duration ~/ 60;
                final seconds = duration % 60;
                final timeStr =
                    '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  color: isDark ? const Color(0xFF222222) : Colors.white,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Delete button
                      GestureDetector(
                        onTap: () async {
                          try {
                            print('🗑️ Deleting recording...');
                            _recordingTimer?.cancel();
                            await _audioRecorder.stop();

                            if (_recordingPath != null) {
                              final file = File(_recordingPath!);
                              if (await file.exists()) {
                                await file.delete();
                              }
                            }

                            setState(() {
                              _isRecording = false;
                              _recordingPath = null;
                              _recordingDuration.value = 0;
                            });

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Recording discarded'),
                                  duration: Duration(milliseconds: 800),
                                ),
                              );
                            }
                          } catch (e) {
                            print('❌ Error deleting recording: $e');
                          }
                        },
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.delete,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Recording indicator dot
                      Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),

                      const SizedBox(width: 16),

                      // Timer
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.all(Radius.circular(18)),
                        ),
                        child: Text(
                          timeStr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),

                      const Spacer(),

                      // Send button
                      GestureDetector(
                        onTap: _sendRecording,
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: const BoxDecoration(
                            color: Color(0xFF00A884),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.send,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            )
          else
            _buildInputBar(
              cardColor: cardColor,
              inputBgColor: inputBgColor,
              textColor: textColor,
              hintColor: hintColor,
              primaryColor: primaryColor,
              isDark: isDark,
            ),
          if (_showEmojiPicker)
            EmojiPicker(
              onEmojiSelected: (category, emoji) => _onEmojiSelected(emoji),
              onBackspacePressed: _onBackspacePressed,
              config: Config(
                height: 250,
                checkPlatformCompatibility: false,
                emojiViewConfig: EmojiViewConfig(
                  backgroundColor: cardColor,
                  columns: 7,
                  emojiSizeMax: 28,
                ),
                categoryViewConfig: CategoryViewConfig(
                  backgroundColor: cardColor,
                  iconColorSelected: primaryColor,
                  indicatorColor: primaryColor,
                ),
                bottomActionBarConfig: BottomActionBarConfig(
                  backgroundColor: cardColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputBar({
    required Color cardColor,
    required Color inputBgColor,
    required Color textColor,
    required Color hintColor,
    required Color primaryColor,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: cardColor,
        border: isDark
            ? null
            : const Border(
                top: BorderSide(color: Color(0xFFE2E8F0), width: 0.5),
              ),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, -4),
                ),
              ]
            : null,
      ),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: Row(
          children: [
            // Text Input
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: inputBgColor,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _showEmojiPicker
                            ? Icons.keyboard
                            : Icons.sentiment_satisfied_outlined,
                        color: hintColor,
                        size: 26,
                      ),
                      padding: const EdgeInsets.all(8),
                      onPressed: () {
                        setState(() {
                          _showEmojiPicker = !_showEmojiPicker;
                        });
                        if (!_showEmojiPicker) {
                          _messageFocusNode.requestFocus();
                        } else {
                          _messageFocusNode.unfocus();
                        }
                      },
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        focusNode: _messageFocusNode,
                        style: TextStyle(color: textColor, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'Message',
                          hintStyle: TextStyle(color: hintColor),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.send,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) {
                          _sendMessage();
                          Future.delayed(const Duration(milliseconds: 50), () {
                            _messageFocusNode.requestFocus();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: Icon(Icons.attach_file, color: hintColor, size: 26),
              padding: const EdgeInsets.all(8),
              onPressed: _showAttachmentPicker,
            ),
            const SizedBox(width: 8),
            // Mic/Send Button - Tap to record, tap to send
            ValueListenableBuilder<int>(
              valueListenable: _recordingDuration,
              builder: (context, duration, _) {
                final micPrimaryColor = const Color(0xFF00A884);
                return GestureDetector(
                  onTap: _isSendingRecording
                      ? null // Disable tap while sending
                      : () async {
                          if (_messageController.text.trim().isNotEmpty) {
                            _sendMessage();
                            return;
                          }

                          if (_isRecording) {
                            // Send the recording
                            await _sendRecording();
                          } else {
                            // Start recording
                            try {
                              final hasPermission = await _audioRecorder
                                  .hasPermission();
                              if (!hasPermission) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Microphone permission denied',
                                      ),
                                    ),
                                  );
                                }
                                return;
                              }

                              final tempDir = await getTemporaryDirectory();
                              final path =
                                  '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

                              print('🎤 Starting recording at: $path');

                              await _audioRecorder.start(
                                const RecordConfig(encoder: AudioEncoder.aacLc),
                                path: path,
                              );

                              setState(() {
                                _isRecording = true;
                                _recordingPath = path;
                                _recordingDuration.value = 0;
                              });

                              _recordingTimer = Timer.periodic(
                                const Duration(seconds: 1),
                                (_) {
                                  if (mounted) {
                                    _recordingDuration.value++;
                                  }
                                },
                              );

                              print('✅ Recording started successfully');
                            } catch (e) {
                              print('❌ Error starting recording: $e');
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')),
                                );
                              }
                            }
                          }
                        },
                  child: Opacity(
                    opacity: _isSendingRecording ? 0.5 : 1.0,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _isRecording ? Colors.red : micPrimaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: _isSendingRecording
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              ),
                            )
                          : IconButton(
                              icon: Icon(
                                _messageController.text.trim().isNotEmpty
                                    ? Icons.send_rounded
                                    : (_isRecording
                                          ? Icons.send_rounded
                                          : Icons.mic),
                                color: Colors.white,
                                size: 24,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: null,
                            ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Messages',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Delete message for everyone?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMessages();
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMessages() async {
    final messagesToDelete = _selectedMessages.value.toList();
    if (messagesToDelete.isEmpty) return;

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.currentUser?.uid;
      if (currentUserId == null) {
        throw Exception('User not found');
      }

      // Verify ownership and collect media to delete
      final validMessages = <String>[];
      final batch = FirebaseFirestore.instance.batch();

      for (final messageId in messagesToDelete) {
        final messageRef = FirebaseFirestore.instance
            .collection('communities')
            .doc(widget.communityId)
            .collection('messages')
            .doc(messageId);

        final docSnapshot = await messageRef.get();
        if (!docSnapshot.exists) continue;

        final data = docSnapshot.data();
        final senderId = data?['senderId'] as String?;

        if (senderId == null || senderId != currentUserId) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('You can only delete your own messages'),
                backgroundColor: Colors.red,
              ),
            );
          }
          continue;
        }

        validMessages.add(messageId);

        // Add to batch
        batch.update(messageRef, {
          'isDeleted': true,
          'message': '',
          'imageUrl': null,
          'mediaMetadata': null,
          'multipleMedia': null,
        });
      }

      // Execute batch delete - all messages deleted instantly
      if (validMessages.isNotEmpty) {
        await batch.commit();
      }

      _selectedMessages.value = {};
      _isSelectionMode.value = false;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${validMessages.length} message(s) deleted'),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showLeaveCommunityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Leave Community',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to leave this community? You can rejoin later from the explore page.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _leaveCommunity();
            },
            child: const Text(
              'Leave',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _leaveCommunity() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.currentUser?.uid;
      if (currentUserId == null) return;

      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Leaving community...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      // Leave community
      final success = await _communityService.leaveCommunity(
        widget.communityId,
        currentUserId,
      );

      if (success) {
        if (mounted) {
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You have left the community'),
              backgroundColor: Color(0xFF4CAF50),
            ),
          );

          // Navigate back to communities list
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to leave community'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _MessageBubble extends StatelessWidget {
  final GroupChatMessage message;
  final bool isMe;
  final bool uploading;
  final double? uploadProgress;
  final Map<String, String> localSenderMediaPaths;
  final Set<String> uploadingMessageIds;
  final Map<String, double> pendingUploadProgress;
  final bool selectionMode;
  final bool isSelected;
  final String communityId;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.uploading,
    required this.uploadProgress,
    required this.localSenderMediaPaths,
    required this.uploadingMessageIds,
    required this.pendingUploadProgress,
    this.selectionMode = false,
    this.isSelected = false,
    required this.communityId,
  });

  @override
  Widget build(BuildContext context) {
    // Get user role to determine theme color
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userRole = authProvider.currentUser?.role;
    final isPrincipal = userRole == UserRole.institute;

    // Use teal for principal, orange for others
    final themeColor = isPrincipal
        ? const Color(0xFF00A884)
        : const Color(0xFFFF8800);
    final bubbleColor = isMe ? themeColor : const Color(0xFF2A2A2A);
    final textColor = Colors.white;

    // DEBUG: Log message rendering details
    if (message.id.startsWith('pending:')) {
      print('🎨 _MessageBubble rendering pending: ${message.id}');
      print('   - Type: ${message.type}');
      print('   - multipleMedia: ${message.multipleMedia?.length}');
      print('   - multipleMedia != null: ${message.multipleMedia != null}');
      print(
        '   - multipleMedia!.isNotEmpty: ${message.multipleMedia?.isNotEmpty}',
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                    child: Text(
                      message.senderName,
                      style: TextStyle(
                        color: themeColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                // Check if this is a poll message
                if (message.type == 'poll')
                  SizedBox(
                    width: double.infinity,
                    child: Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: PollMessageWidget(
                        poll: PollModel.fromMap(message.toMap(), message.id),
                        chatId: communityId,
                        chatType: 'community',
                        isOwnMessage: isMe,
                      ),
                    ),
                  )
                else if (message.multipleMedia != null &&
                    message.multipleMedia!.isNotEmpty) ...[
                  MultiImageMessageBubble(
                    key: ValueKey('${message.id}_multi_image'),
                    imageUrls: message.multipleMedia!
                        .map((m) => m.localPath ?? m.publicUrl)
                        .toList(),
                    isMe: isMe,
                    uploadProgress: message.multipleMedia!
                        .map((m) => pendingUploadProgress[m.messageId])
                        .toList(),
                    onImageTap: (index) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _ImageGalleryViewer(
                            mediaList: message.multipleMedia!,
                            initialIndex: index,
                            localSenderMediaPaths: localSenderMediaPaths,
                            isMe: isMe,
                          ),
                        ),
                      );
                    },
                  ),
                  if (message.message.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: bubbleColor,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isMe ? 16 : 4),
                          bottomRight: Radius.circular(isMe ? 4 : 16),
                        ),
                      ),
                      child: _buildLinkifiedText(textColor),
                    ),
                  ],
                ] else ...[
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal:
                          (message.mediaMetadata != null ||
                                  message.imageUrl != null) &&
                              message.message.isEmpty
                          ? 6
                          : 16,
                      vertical:
                          (message.mediaMetadata != null ||
                                  message.imageUrl != null) &&
                              message.message.isEmpty
                          ? 6
                          : 10,
                    ),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isMe ? 16 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.mediaMetadata != null) ...[
                          _buildMetadataAttachment(
                            context,
                            message.mediaMetadata!,
                          ),
                          if (message.message.isNotEmpty)
                            const SizedBox(height: 8),
                        ] else if (message.imageUrl != null) ...[
                          _buildLegacyAttachment(context, message.imageUrl!),
                          if (message.message.isNotEmpty)
                            const SizedBox(height: 8),
                        ],
                        if (message.message.isNotEmpty)
                          _buildLinkifiedText(textColor),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.timestamp),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          if (selectionMode && isMe)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(
                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isSelected ? themeColor : Colors.grey,
                size: 24,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLinkifiedText(Color textColor) {
    return Linkify(
      onOpen: (link) async {
        final uri = Uri.parse(link.url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      text: LinkUtils.addProtocolToBareUrls(message.message),
      options: const LinkifyOptions(defaultToHttps: true),
      style: TextStyle(color: textColor, fontSize: 14),
      linkStyle: const TextStyle(
        color: Color(0xFF90CAF9),
        fontSize: 14,
        decoration: TextDecoration.underline,
      ),
    );
  }

  Widget _buildMetadataAttachment(
    BuildContext context,
    MediaMetadata metadata,
  ) {
    final fileSize = metadata.fileSize ?? 0;
    final isUploading = uploadingMessageIds.contains(metadata.messageId);
    final uploadProgressVal = pendingUploadProgress[metadata.messageId];

    return MediaPreviewCard(
      r2Key: metadata.r2Key,
      fileName: _fileNameFromMetadata(metadata),
      mimeType: metadata.mimeType ?? 'application/octet-stream',
      fileSize: fileSize,
      thumbnailBase64: metadata.thumbnail,
      localPath:
          metadata.localPath ?? localSenderMediaPaths[metadata.messageId],
      isMe: isMe,
      selectionMode: selectionMode,
      uploading: isUploading,
      uploadProgress: uploadProgressVal,
    );
  }

  Widget _buildLegacyAttachment(BuildContext context, String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return const SizedBox();
    final r2Key = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    final fileName = _fileNameFromUrl(url);
    final mimeType = _guessMimeType(fileName);

    return MediaPreviewCard(
      r2Key: r2Key,
      fileName: fileName,
      mimeType: mimeType,
      fileSize: 0,
      isMe: isMe,
      selectionMode: selectionMode,
      uploading: uploading,
      uploadProgress: uploadProgress,
    );
  }

  String _fileNameFromMetadata(MediaMetadata metadata) {
    return metadata.originalFileName ?? metadata.r2Key.split('/').last;
  }

  String _guessMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.m4a') || lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    return 'application/octet-stream';
  }

  String _fileNameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }
    return 'file';
  }

  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${date.day}/${date.month}/${date.year}';
  }
}

class _ImageGalleryViewer extends StatefulWidget {
  final List<MediaMetadata> mediaList;
  final int initialIndex;
  final Map<String, String> localSenderMediaPaths;
  final bool isMe;

  const _ImageGalleryViewer({
    required this.mediaList,
    required this.initialIndex,
    required this.localSenderMediaPaths,
    required this.isMe,
  });

  @override
  State<_ImageGalleryViewer> createState() => _ImageGalleryViewerState();
}

class _ImageGalleryViewerState extends State<_ImageGalleryViewer> {
  late PageController _pageController;
  late int _currentIndex;
  late Map<int, TransformationController> _transformationControllers;
  late Map<int, bool> _zoomStates;
  bool _isInteracting =
      false; // Track if user is currently interacting with zoom
  int _pointerCount = 0; // Track number of fingers on screen

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _transformationControllers = {};
    _zoomStates = {};

    // Initialize transformation controllers and zoom states for all images
    for (int i = 0; i < widget.mediaList.length; i++) {
      final controller = TransformationController();
      _transformationControllers[i] = controller;
      _zoomStates[i] = false;

      // Listen to transformation changes
      controller.addListener(() {
        final scale = controller.value.getMaxScaleOnAxis();
        final isZoomed = scale > 1.01;
        if (_zoomStates[i] != isZoomed) {
          setState(() {
            _zoomStates[i] = isZoomed;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (var controller in _transformationControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _shouldDisableScroll =>
      _isInteracting || (_zoomStates[_currentIndex] ?? false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${_currentIndex + 1} / ${widget.mediaList.length}',
          style: const TextStyle(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.horizontal,
        physics: _shouldDisableScroll
            ? const NeverScrollableScrollPhysics()
            : const AlwaysScrollableScrollPhysics(),
        onPageChanged: (index) {
          // Reset transformation of previous image when switching
          if (_transformationControllers[_currentIndex] != null) {
            _transformationControllers[_currentIndex]!.value =
                Matrix4.identity();
          }
          setState(() {
            _currentIndex = index;
          });
        },
        itemCount: widget.mediaList.length,
        itemBuilder: (context, index) {
          final metadata = widget.mediaList[index];
          final localPath =
              metadata.localPath ??
              widget.localSenderMediaPaths[metadata.messageId];

          return _buildImageViewer(metadata, localPath);
        },
      ),
    );
  }

  Widget _buildImageViewer(MediaMetadata metadata, String? localPath) {
    Widget imageWidget;
    final file = (localPath != null && localPath.isNotEmpty)
        ? File(localPath)
        : null;
    final hasLocalFile = file != null && file.existsSync();
    final hasNetwork = metadata.publicUrl.isNotEmpty;

    if (hasLocalFile) {
      imageWidget = RepaintBoundary(
        child: Image.file(
          file,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          cacheWidth: 1200,
          errorBuilder: (_, __, ___) => _buildFallbackImage(metadata),
        ),
      );
    } else if (hasNetwork) {
      imageWidget = RepaintBoundary(
        child: CachedNetworkImage(
          imageUrl: metadata.publicUrl,
          key: ValueKey(metadata.publicUrl),
          cacheKey: metadata.publicUrl,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          memCacheWidth: 1200,
          maxWidthDiskCache: 1200,
          fadeInDuration: const Duration(milliseconds: 0),
          fadeOutDuration: const Duration(milliseconds: 0),
          useOldImageOnUrlChange: true,
          imageBuilder: (context, imageProvider) => Image(
            image: imageProvider,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
          ),
          placeholder: (context, url) => const Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
          errorWidget: (context, url, error) => _buildFallbackImage(metadata),
        ),
      );
    } else if (metadata.thumbnail.isNotEmpty) {
      if (metadata.thumbnail.startsWith('/')) {
        imageWidget = Image.file(
          File(metadata.thumbnail),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => _buildFallbackImage(metadata),
        );
      } else {
        try {
          final bytes = base64Decode(metadata.thumbnail);
          imageWidget = Image.memory(
            bytes,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => _buildFallbackImage(metadata),
          );
        } catch (e) {
          imageWidget = _buildFallbackImage(metadata);
        }
      }
    } else {
      imageWidget = _buildFallbackImage(metadata);
    }

    // Get the index from the metadata to find the correct controller
    final index = widget.mediaList.indexOf(metadata);

    return Listener(
      onPointerDown: (event) {
        setState(() {
          _pointerCount++;
          // Only enable interaction when 2+ fingers detected
          if (_pointerCount >= 2) {
            _isInteracting = true;
          }
        });
      },
      onPointerUp: (event) {
        setState(() {
          _pointerCount--;
          // Re-enable PageView when less than 2 fingers
          if (_pointerCount < 2) {
            _isInteracting = false;
            // Snap back to center if at original scale
            final controller = _transformationControllers[index]!;
            final scale = controller.value.getMaxScaleOnAxis();
            if (scale <= 1.01) {
              // Reset to centered position
              controller.value = Matrix4.identity();
            }
          }
        });
      },
      onPointerCancel: (event) {
        setState(() {
          _pointerCount--;
          if (_pointerCount < 2) {
            _isInteracting = false;
            // Snap back to center if at original scale
            final controller = _transformationControllers[index]!;
            final scale = controller.value.getMaxScaleOnAxis();
            if (scale <= 1.01) {
              controller.value = Matrix4.identity();
            }
          }
        });
      },
      child: GestureDetector(
        onDoubleTap: () {
          final controller = _transformationControllers[index]!;
          final scale = controller.value.getMaxScaleOnAxis();

          if (scale > 1.1) {
            // Zoom out to original
            controller.value = Matrix4.identity();
          } else {
            // Zoom in to 2.5x at center
            final targetScale = 2.5;
            controller.value = Matrix4.identity()
              ..translate(
                -MediaQuery.of(context).size.width * (targetScale - 1) / 2,
                -MediaQuery.of(context).size.height * (targetScale - 1) / 2,
              )
              ..scale(targetScale);
          }
          setState(() {});
        },
        child: InteractiveViewer(
          transformationController: _transformationControllers[index],
          minScale: 1.0,
          maxScale: 5.0,
          panEnabled: _pointerCount >= 2, // Only pan with 2+ fingers
          scaleEnabled: true,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          clipBehavior: Clip.none,
          child: Center(child: imageWidget),
        ),
      ),
    );
  }

  Widget _buildFallbackImage(MediaMetadata metadata) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image, size: 64, color: Colors.white54),
          const SizedBox(height: 16),
          const Text(
            'Image not available locally',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            metadata.originalFileName ?? 'image.jpg',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
