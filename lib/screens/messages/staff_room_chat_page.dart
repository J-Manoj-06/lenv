import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'dart:io';
import '../../providers/auth_provider.dart';
import '../../services/cloudflare_r2_service.dart';
import '../../config/cloudflare_config.dart';
import '../../services/media_upload_service.dart';
import '../../services/local_cache_service.dart';
import '../../widgets/media_preview_card.dart';
import '../../widgets/multi_image_message_bubble.dart';
import '../create_poll_screen.dart';
import '../../widgets/poll_message_widget.dart';
import '../../models/poll_model.dart';
import 'message_search_page.dart';
import '../../utils/message_scroll_highlight_mixin.dart';
// OFFLINE-FIRST IMPORTS
import '../../repositories/local_message_repository.dart';
import '../../services/firebase_message_sync_service.dart';
import '../../models/local_message.dart';
import 'offline_message_search_page.dart';
import '../../services/background_upload_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Staff Room - Group chat for all principals and teachers in the institute
class StaffRoomChatPage extends StatefulWidget {
  final String instituteId;
  final String instituteName;
  final bool isTeacher; // True if accessed by teacher

  const StaffRoomChatPage({
    super.key,
    required this.instituteId,
    required this.instituteName,
    this.isTeacher = false,
  });

  @override
  State<StaffRoomChatPage> createState() => _StaffRoomChatPageState();
}

class _StaffRoomChatPageState extends State<StaffRoomChatPage>
    with MessageScrollAndHighlightMixin {
  final TextEditingController _messageController = TextEditingController();
  late final MediaUploadService _mediaUploadService;
  final ValueNotifier<bool> _isUploading = ValueNotifier<bool>(false);

  // OFFLINE-FIRST SERVICES
  late final LocalMessageRepository _localRepo;
  late final FirebaseMessageSyncService _syncService;
  final bool _useOfflineFirst = true; // Toggle to test offline vs old approach

  // Track pending scroll request from search
  String? _scrollToMessageId;
  bool _isScrollingToMessage =
      false; // Flag to prevent auto-scroll during search navigation
  bool _userHasScrolled = false; // Track if user manually scrolled
  double _lastScrollPosition = 0.0; // Track last scroll position
  int _lastItemCount = 0; // Track message count to detect new messages
  bool _isProcessingScroll = false; // Prevent duplicate scroll callbacks

  // Recording variables
  final AudioRecorder _audioRecorder = AudioRecorder();
  final ValueNotifier<bool> _isRecording = ValueNotifier<bool>(false);
  String? _recordingPath;
  final ValueNotifier<int> _recordingDuration = ValueNotifier<int>(0);
  Timer? _recordingTimer;

  // ValueNotifier to control input area rebuild without rebuilding entire screen
  final ValueNotifier<bool> _hasText = ValueNotifier<bool>(false);

  // Pending uploads tracking (like community chat)
  final List<Map<String, dynamic>> _pendingMessages = [];
  final Set<String> _uploadingMessageIds = {};
  final Map<String, double> _pendingUploadProgress = {};
  final Map<String, String> _localFilePaths = {};
  final Map<String, ValueNotifier<double>> _progressNotifiers = {};

  // Selection mode for delete (ValueNotifiers for flicker-free updates)
  final ValueNotifier<Set<String>> _selectedMessages = ValueNotifier({});
  final ValueNotifier<bool> _isSelectionMode = ValueNotifier(false);

  // Timer to poll cache for progress updates
  Timer? _progressPollTimer;

  // Message cache to maintain stable Map instances (prevents flickering)
  final Map<String, Map<String, dynamic>> _messageCache = {};

  // Cached stream to prevent StreamBuilder recreating stream on every build
  Stream<QuerySnapshot>? _messagesStream;

  // Notification for background uploads
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  int _activeUploads = 0;

  @override
  void initState() {
    super.initState();
    _initMediaService();
    _initOfflineFirst();
    _initMessagesStream();

    // Listen to scroll events to detect user scrolling
    scrollController.addListener(_onScroll);

    // Start polling for progress updates every 2 seconds
    _startProgressPolling();

    // Initialize background upload service
    _initBackgroundUploadService();
  }

  void _initMessagesStream() {
    // Create stream once and cache it to prevent rebuilds
    _messagesStream = FirebaseFirestore.instance
        .collection('staff_rooms')
        .doc(widget.instituteId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(300)
        .snapshots();
  }

  void _startProgressPolling() {
    _progressPollTimer?.cancel();
    _progressPollTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_pendingMessages.isNotEmpty) {
        _checkCacheForProgressUpdates();
      }
    });
  }

  Future<void> _checkCacheForProgressUpdates() async {
    if (_pendingMessages.isEmpty || !mounted) return;

    print('🔍 [POLLING] Checking cache for progress updates...');
    print('   Pending messages count: ${_pendingMessages.length}');

    final toRemove = <String>[];

    for (final pendingMsg in _pendingMessages) {
      final messageId = pendingMsg['id'] as String;

      print('   📝 Checking message in cache: $messageId');

      // Skip cache check for BackgroundUploadService messages (pending_ prefix)
      // These are managed by the onUploadProgress callback, not cache
      if (messageId.startsWith('pending_')) {
        print(
          '      ⏭️ Skipping cache check for BackgroundUploadService message',
        );
        continue;
      }

      try {
        final cachedMsg = await _localRepo.getMessageById(messageId);

        print('      Cache result: ${cachedMsg != null ? "FOUND" : "NULL"}');

        // If message was deleted from cache, it means upload completed
        // Remove it from UI pending list
        if (cachedMsg == null) {
          print('      ⚠️ NULL from cache - adding to toRemove list');
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
      print(
        '❌ [POLLING] Removing ${toRemove.length} messages from pending list:',
      );
      for (final id in toRemove) {
        print('   - $id');
      }
      setState(() {
        _pendingMessages.removeWhere((m) => toRemove.contains(m['id']));
        for (final messageId in toRemove) {
          _uploadingMessageIds.removeWhere((id) => id.startsWith(messageId));
          _pendingUploadProgress.removeWhere((k, v) => k.startsWith(messageId));
          _localFilePaths.removeWhere((k, v) => k.startsWith(messageId));
        }
      });
      print('   ✅ Removed. New pending count: ${_pendingMessages.length}');
    } else {
      print(
        '✅ [POLLING] No messages to remove. Pending count: ${_pendingMessages.length}',
      );
    }
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;

    final currentPosition = scrollController.offset;

    // Detect if user manually scrolled (position changed significantly)
    if ((currentPosition - _lastScrollPosition).abs() > 10.0) {
      // User scrolled - don't auto-scroll back to bottom
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
        widget.instituteId,
        limit: 50, // Initial load: 50 messages
      );

      if (cachedMessages.isEmpty) {
        // No cache: fetch initial batch from Firebase
        print('📥 No cache - fetching initial messages from Firebase...');
        await _syncService.initialSyncForChat(
          chatId: widget.instituteId,
          chatType: 'staff_room',
          limit: 50, // Fetch last 50 messages initially
        );
      } else {
        print(
          '✅ Loaded ${cachedMessages.length} messages from cache (offline-ready)',
        );

        // Sync new messages in background (if online)
        _syncService.syncNewMessages(
          chatId: widget.instituteId,
          chatType: 'staff_room',
          lastTimestamp: cachedMessages.first.timestamp,
        );
      }

      // Start real-time listener for new messages
      await _syncService.startSyncForChat(
        chatId: widget.instituteId,
        chatType: 'staff_room',
        userId: currentUser.uid,
      );
    }
  }

  Future<void> _loadPendingMessages() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    print('🔄 [RESTORE] Loading pending messages from cache...');

    // Load pending messages for this chat from cache
    final pendingMessages = await _localRepo.getPendingMessages(
      chatId: widget.instituteId,
      senderId: currentUser.uid,
    );

    print('   Found ${pendingMessages.length} pending messages in cache');

    if (pendingMessages.isNotEmpty && mounted) {
      setState(() {
        // Convert LocalMessage to widget format
        for (final msg in pendingMessages) {
          print('   Restoring message: ${msg.messageId}');

          if (msg.multipleMedia != null && msg.multipleMedia!.isNotEmpty) {
            print(
              '     Type: Multi-image (${msg.multipleMedia!.length} images)',
            );
            _pendingMessages.add({
              'id': msg.messageId,
              'text': msg.messageText ?? '',
              'senderId': msg.senderId,
              'senderName': msg.senderName,
              'senderRole': 'teacher',
              'createdAt': msg.timestamp,
              'multipleMedia': msg.multipleMedia,
              'isPending': true,
            });

            // Restore local file paths, uploading state, and actual progress
            for (int i = 0; i < msg.multipleMedia!.length; i++) {
              final media = msg.multipleMedia![i];
              final mediaId = media['messageId'] as String?;
              final localPath = media['localPath'] as String?;
              final uploadProgress = media['uploadProgress'] as double?;

              if (mediaId != null) {
                _uploadingMessageIds.add(mediaId);

                // Restore local file path for thumbnail display
                if (localPath != null) {
                  _localFilePaths[mediaId] = localPath;
                  final file = File(localPath);
                  print('       Image $i: path exists=${file.existsSync()}');
                }

                // Restore actual upload progress from cache, use 0.01 if null to trigger UI
                final restoredProgress = uploadProgress ?? 0.01;
                _pendingUploadProgress[mediaId] = restoredProgress;
                print('       Image $i: progress=${restoredProgress * 100}%');
              }
            }
          }
          // Note: Single file attachments cannot be restored from cache
          // because LocalMessage model doesn't have fields for:
          // - localFilePath, attachmentName, attachmentSize, thumbnailUrl, uploadProgress
          // Only multi-image messages (using multipleMedia field) can be restored.
        }
      });
      print('✅ Restored ${pendingMessages.length} pending messages from cache');
    } else {
      print('   No pending messages to restore');
    }
  }

  void _initBackgroundUploadService() async {
    await BackgroundUploadService().initialize();

    // Track upload progress and show persistent notification
    BackgroundUploadService()
        .onUploadProgress = (messageId, isUploading, progress) async {
      if (!mounted) return;

      setState(() {
        if (isUploading) {
          if (!_uploadingMessageIds.contains(messageId)) {
            _activeUploads++;
          }
          _uploadingMessageIds.add(messageId);
          _pendingUploadProgress[messageId] = progress;

          // Update progress notifier for smooth UI updates
          _progressNotifiers[messageId]?.value = progress;
        } else {
          // Upload to R2 complete - but DON'T remove pending message yet!
          // Keep it until Firestore sync completes (message appears in stream)
          // Only clean up tracking data
          if (_uploadingMessageIds.contains(messageId)) {
            _activeUploads--;
          }
          _uploadingMessageIds.remove(messageId);
          _pendingUploadProgress.remove(messageId);
          // Keep _localFilePaths[messageId] until Firestore sync

          print(
            '📤 R2 upload complete for: $messageId - Waiting for Firestore sync...',
          );
          // Note: Pending message will be auto-removed when Firestore message arrives
          // because merging logic filters out pending messages with same timestamp
        }
      });

      // Show/update persistent notification
      if (_activeUploads > 0) {
        await _showUploadNotification(progress);
      } else {
        await _cancelUploadNotification();
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
          // Clean up all tracking for images in this group
          final keysToRemove = <String>[];
          for (final key in _uploadingMessageIds) {
            if (key.startsWith(groupId)) {
              keysToRemove.add(key);
            }
          }

          for (final key in keysToRemove) {
            _uploadingMessageIds.remove(key);
            _pendingUploadProgress.remove(key);
            _progressNotifiers[key]?.dispose();
            _progressNotifiers.remove(key);
          }
          // Keep _localFilePaths and _pendingMessages until Firestore sync
          print(
            '✅ Cleaned up tracking for group: $groupId (pending message kept until Firestore sync)',
          );
        });
      }

      // Remove notification when all uploads complete
      if (_activeUploads <= 0) {
        await _cancelUploadNotification();
      }
    };
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
      999, // Fixed ID for upload notification
      'Uploading to Staff Room',
      progressPercent < 100
          ? 'Upload in progress... $progressPercent%'
          : 'Upload complete',
      notificationDetails,
    );
  }

  Future<void> _cancelUploadNotification() async {
    await _flutterLocalNotificationsPlugin.cancel(999);
  }

  void _initMediaService() {
    final r2 = CloudflareR2Service(
      accountId: CloudflareConfig.accountId,
      bucketName: CloudflareConfig.bucketName,
      accessKeyId: CloudflareConfig.accessKeyId,
      secretAccessKey: CloudflareConfig.secretAccessKey,
      r2Domain: CloudflareConfig.r2Domain,
    );

    _mediaUploadService = MediaUploadService(
      r2Service: r2,
      firestore: FirebaseFirestore.instance,
      cacheService: LocalCacheService(),
    );
  }

  @override
  void dispose() {
    print('⚠️ [DISPOSE] Staff Room Chat Page');
    print('   Pending messages: ${_pendingMessages.length}');
    print('   Uploading message IDs: ${_uploadingMessageIds.length}');
    print('   Local file paths: ${_localFilePaths.length}');
    print('   Pending upload progress: ${_pendingUploadProgress.length}');
    print('   Progress notifiers: ${_progressNotifiers.length}');

    if (_pendingMessages.isNotEmpty) {
      print('   ⚠️ WARNING: Disposing with pending uploads!');
      for (final msg in _pendingMessages) {
        print(
          '     - ${msg['id']}: ${msg['attachmentName'] ?? 'multi-images'}',
        );
      }
    }

    _messageController.dispose();
    disposeScrollController(); // Use mixin's disposal method
    _audioRecorder.dispose();
    _recordingTimer?.cancel();
    _progressPollTimer?.cancel(); // Cancel progress polling
    _recordingDuration.dispose();
    // Dispose all progress notifiers
    for (final notifier in _progressNotifiers.values) {
      notifier.dispose();
    }
    _progressNotifiers.clear();

    // Dispose selection notifiers
    _selectedMessages.dispose();
    _isSelectionMode.dispose();

    // Cancel upload notification
    _cancelUploadNotification();

    // Note: Pending messages are persisted in cache, not cleared on dispose
    // They will be auto-removed when upload completes or matched with server version

    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('staff_rooms')
          .doc(widget.instituteId)
          .collection('messages')
          .add({
            'text': text,
            'senderId': currentUser.uid,
            'senderName': currentUser.name,
            'senderRole': currentUser.role.toString().split('.').last,
            'timestamp': FieldValue.serverTimestamp(),
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          });

      _messageController.clear();
      _hasText.value = false; // Update ValueNotifier instead of setState

      // Scroll to bottom after sending only if user hasn't scrolled away
      if (!_userHasScrolled) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (scrollController.hasClients) {
            scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
      }
    }
  }

  Future<void> _pickImage() async {
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

  Future<void> _pickCamera() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      await _uploadFile(File(pickedFile.path));
    }
  }

  Future<void> _pickDocument() async {
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
      await _uploadFile(File(result.files.single.path!));
    }
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'wav', 'aac'],
    );

    if (result != null && result.files.single.path != null) {
      await _uploadFile(File(result.files.single.path!));
    }
  }

  /// Upload multiple images as a single message
  Future<void> _uploadMultipleImages(List<File> files) async {
    if (files.isEmpty) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    final baseTimestamp = DateTime.now().millisecondsSinceEpoch;
    final groupMessageId =
        'pending_${baseTimestamp}_${currentUser.uid.hashCode}';
    final List<Map<String, dynamic>> mediaList = [];
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

      mediaList.add({
        'messageId': messageId,
        'r2Key': 'pending/$messageId',
        'publicUrl': '',
        'thumbnail': absolutePath,
        'localPath': absolutePath,
        'originalFileName': fileName,
        'fileSize': fileSize,
        'mimeType': 'image/jpeg',
        'uploadProgress': 0.01, // Start at 1% to show as uploading, not 0%
      });
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
    final pendingMessage = {
      'id': groupMessageId,
      'text': '',
      'senderId': currentUser.uid,
      'senderName': currentUser.name,
      'senderRole': currentUser.role.toString().split('.').last,
      'createdAt': baseTimestamp,
      'multipleMedia': mediaList,
      'isPending': true,
    };

    print('📤 Creating pending message with ${mediaList.length} images');
    print('   Pending ID: $groupMessageId');

    // Save pending message to cache IMMEDIATELY (survives navigation)
    try {
      final pendingLocalMsg = LocalMessage(
        messageId: groupMessageId,
        chatId: widget.instituteId,
        chatType: 'staff_room',
        senderId: currentUser.uid,
        senderName: currentUser.name,
        timestamp: baseTimestamp,
        messageText: '',
        multipleMedia: mediaList,
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
      final messageId = mediaList[i]['messageId'];
      final localPath = localPaths[i];
      _localFilePaths[messageId] = localPath;
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
      print('     - size: ${mediaList[i]['fileSize'] / 1024} KB');
    }
    print('   Total uploadingMessageIds: ${_uploadingMessageIds.length}');
    print('   Total localFilePaths: ${_localFilePaths.length}');
    print('   Total pendingUploadProgress: ${_pendingUploadProgress.length}');

    setState(() {
      _pendingMessages.insert(0, pendingMessage);
      print('   ✅ Pending message added (count: ${_pendingMessages.length})');
      print(
        '   📊 Pending message structure: ${pendingMessage.toString().substring(0, 200)}...',
      );
      print('   📊 Calling setState - widget should rebuild now');
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
          conversationId: widget.instituteId,
          senderId: currentUser.uid,
          senderRole: currentUser.role.toString().split('.').last,
          mediaType: 'staff_room',
          chatType: 'staff_room',
          senderName: currentUser.name,
          messageId: messageId,
          groupId: groupMessageId, // Group all images together
        );

        print('✅ Image $i queued for background upload: $messageId');
      }

      print('✅ [MULTI-IMAGE UPLOAD] All ${files.length} images queued');

      // Scroll to bottom only if user hasn't scrolled away
      if (!_userHasScrolled) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (scrollController.hasClients) {
            scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      // Remove failed pending message
      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m['id'] == groupMessageId);
          for (final media in mediaList) {
            final messageId = media['messageId'];
            _uploadingMessageIds.remove(messageId);
            _pendingUploadProgress.remove(messageId);
            _localFilePaths.remove(messageId);
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

  Future<void> _uploadFile(File file) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    // Get file info
    final fileSize = await file.length();
    final fileName = file.path.split('/').last;
    final baseTimestamp = DateTime.now().millisecondsSinceEpoch;
    final messageId = 'pending_${baseTimestamp}_${currentUser.uid.hashCode}';

    // Determine mime type
    String mimeType = 'application/octet-stream';
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) {
      mimeType = 'application/pdf';
    } else if (lower.endsWith('.jpg') || lower.endsWith('.jpeg'))
      mimeType = 'image/jpeg';
    else if (lower.endsWith('.png'))
      mimeType = 'image/png';
    else if (lower.endsWith('.m4a') || lower.endsWith('.aac'))
      mimeType = 'audio/aac';
    else if (lower.endsWith('.mp3'))
      mimeType = 'audio/mpeg';
    else if (lower.endsWith('.doc'))
      mimeType = 'application/msword';
    else if (lower.endsWith('.docx'))
      mimeType =
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    else if (lower.endsWith('.odt'))
      mimeType = 'application/vnd.oasis.opendocument.text';

    // Add pending message
    final pendingMessage = {
      'id': messageId,
      'text': '',
      'senderId': currentUser.uid,
      'senderName': currentUser.name,
      'senderRole': currentUser.role.toString().split('.').last,
      'createdAt': baseTimestamp,
      'attachmentUrl': 'pending',
      'attachmentType': mimeType,
      'attachmentName': fileName,
      'attachmentSize': fileSize,
      'isPending': true,
    };

    // Store file path and progress BEFORE adding to pending messages
    final absolutePath = file.absolute.path;
    _localFilePaths[messageId] = absolutePath;
    _pendingUploadProgress[messageId] = 0.01; // Start at 1%
    _uploadingMessageIds.add(messageId);

    // Create progress notifier for UI updates
    final progressNotifier = ValueNotifier<double>(0.01);
    _progressNotifiers[messageId] = progressNotifier;

    print('🎯 [SINGLE FILE UPLOAD] Initialized with BackgroundUploadService:');
    print('   Message ID: $messageId');
    print('   File: $fileName');
    print('   Absolute Path: $absolutePath');
    print('   File exists: ${file.existsSync()}');
    print('   File size: ${fileSize / 1024} KB');
    print('   MIME type: $mimeType');

    setState(() {
      _pendingMessages.insert(0, pendingMessage);
      print(
        '   ✅ Pending message added to list (count: ${_pendingMessages.length})',
      );
      print('   📊 Total pending messages: ${_pendingMessages.length}');
      print('   📊 Uploading message IDs: ${_uploadingMessageIds.length}');
      print('   📊 Local file paths: ${_localFilePaths.length}');
      print('   📊 Pending message structure: $pendingMessage');
      print('   📊 Calling setState - widget should rebuild now');
    });

    // Add a small delay to ensure setState completes
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      // Use BackgroundUploadService to enable background upload
      await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: widget.instituteId,
        senderId: currentUser.uid,
        senderRole: currentUser.role.toString().split('.').last,
        mediaType: 'staff_room',
        chatType: 'staff_room',
        senderName: currentUser.name,
        messageId: messageId, // Use our pending messageId for progress tracking
      );

      print('✅ [SINGLE FILE UPLOAD] Queued for background upload: $messageId');

      // Scroll to bottom only if user hasn't scrolled away
      if (!_userHasScrolled) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (scrollController.hasClients) {
            scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      // Log the error to understand what's happening
      print('❌ [UPLOAD ERROR] Exception caught in _uploadFile:');
      print('   Error type: ${e.runtimeType}');
      print('   Error message: $e');
      print('   Stack trace: ${StackTrace.current}');

      // Remove failed pending message
      setState(() {
        _pendingMessages.removeWhere((m) => m['id'] == messageId);
        _uploadingMessageIds.remove(messageId);
        _pendingUploadProgress.remove(messageId);
        _localFilePaths.remove(messageId);
      });

      if (mounted) {
        // Show user-friendly error message
        String errorMessage = 'Failed to send file';
        if (e.toString().contains('Network error') ||
            e.toString().contains('SocketException') ||
            e.toString().contains('Failed host lookup')) {
          errorMessage =
              'Network error. Please check your internet connection and try again.';
        } else if (e.toString().contains('timeout') ||
            e.toString().contains('Timeout')) {
          errorMessage =
              'Upload timed out. Please try again or use a smaller file.';
        } else if (e.toString().contains('too large')) {
          errorMessage = e.toString().replaceAll('Exception: ', '');
        } else {
          errorMessage = 'Failed to send file. Please try again.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () {
                // Allow user to retry by picking the file again
                _pickDocument();
              },
            ),
          ),
        );
      }
    }
  }

  void _navigateToPollScreen() {
    print('🟢 _navigateToPollScreen called');
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/create_poll'),
        builder: (_) {
          print('🟢 CreatePollScreen builder executing');
          return CreatePollScreen(
            chatId: widget.instituteId,
            chatType: 'staff_room',
          );
        },
      ),
    );
  }

  void _showAttachmentPicker() {
    final primaryColor = widget.isTeacher
        ? const Color(0xFFF97316)
        : const Color(0xFF146D7A);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
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
                  label: 'Images',
                  color: primaryColor,
                  onTap: () {
                    Navigator.pop(bottomSheetContext);
                    _pickImage();
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
                    print('🟢 POLL BUTTON TAPPED');
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

  Future<void> _sendRecording() async {
    // Prevent duplicate sends
    if (_isUploading.value || !_isRecording.value) {
      print('⚠️ Already uploading or not recording');
      return;
    }

    try {
      print('🎤 Sending recording...');
      _recordingTimer?.cancel();
      final path = await _audioRecorder.stop();

      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          final authProvider = Provider.of<AuthProvider>(
            context,
            listen: false,
          );
          final currentUser = authProvider.currentUser;
          if (currentUser == null) return;

          try {
            _isUploading.value = true;
            _isRecording.value = false;

            // Get audio file size
            final fileSize = await file.length();

            // Upload audio using MediaUploadService
            final mediaMessage = await _mediaUploadService.uploadMedia(
              file: file,
              conversationId: widget.instituteId,
              senderId: currentUser.uid,
              senderRole: currentUser.role.toString().split('.').last,
              mediaType: 'message',
            );

            // Send message with attachment
            await FirebaseFirestore.instance
                .collection('staff_rooms')
                .doc(widget.instituteId)
                .collection('messages')
                .add({
                  'text': '',
                  'senderId': currentUser.uid,
                  'senderName': currentUser.name,
                  'senderRole': currentUser.role.toString().split('.').last,
                  'timestamp': FieldValue.serverTimestamp(),
                  'createdAt': DateTime.now().millisecondsSinceEpoch,
                  'attachmentUrl': mediaMessage.r2Url,
                  'attachmentType': 'audio/m4a',
                  'attachmentName': mediaMessage.fileName,
                  'attachmentSize': fileSize,
                  'thumbnailUrl': mediaMessage.thumbnailUrl,
                });

            _isUploading.value = false;
            _isRecording.value = false;
            _recordingPath = null;
            _recordingDuration.value = 0;

            // Scroll to bottom only if user hasn't scrolled away
            if (!_userHasScrolled) {
              Future.delayed(const Duration(milliseconds: 100), () {
                if (scrollController.hasClients) {
                  scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              });
            }

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Audio sent successfully'),
                  duration: Duration(milliseconds: 800),
                ),
              );
            }
          } catch (e) {
            print('❌ Error uploading audio: $e');
            _isUploading.value = false;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to send audio: $e')),
              );
            }
          }
        }
      }

      _isRecording.value = false;
      _recordingPath = null;
      _recordingDuration.value = 0;
    } catch (e) {
      print('❌ Error sending recording: $e');
    }
  }

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF262A30) : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(14),
            border: isDark
                ? null
                : Border.all(color: Colors.grey.shade300, width: 1),
          ),
          child: Text(
            _formatDayLabel(dt),
            style: TextStyle(
              color: isDark ? const Color(0xFF9E9E9E) : Colors.grey.shade700,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Use orange for teachers, teal for principals
    final primaryColor = widget.isTeacher
        ? const Color(0xFFF97316) // Orange
        : const Color(0xFF146D7A); // Teal

    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: ValueListenableBuilder<bool>(
          valueListenable: _isSelectionMode,
          builder: (context, isSelectionMode, _) {
            return IconButton(
              icon: Icon(
                isSelectionMode ? Icons.close : Icons.chevron_left,
                color: textColor,
                size: isSelectionMode ? 24 : 32,
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
                    : Text(
                        widget.isTeacher ? 'Teacher Group Chat' : 'Staff Room',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
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
                            IconButton(
                              icon: Icon(Icons.search, color: textColor),
                              onPressed: () => _openOfflineSearch(
                                context,
                                theme,
                                primaryColor,
                              ),
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
          Expanded(child: _buildNormalMessages(theme, primaryColor)),
          _buildMessageInput(theme, primaryColor),
        ],
      ),
    );
  }

  void _openSearch(
    BuildContext context,
    ThemeData theme,
    Color primaryColor,
  ) async {
    final selectedMessageId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => MessageSearchPage(
          collectionPath: 'staff_rooms/${widget.instituteId}/messages',
          primaryColor: primaryColor,
          onMessageSelected: (messageId, messageData) {
            // Pop the search page and return the message ID
            Navigator.pop(context, messageId);
          },
        ),
      ),
    );

    // If a message was selected, scroll to it
    if (selectedMessageId != null && mounted) {
      // Hide keyboard immediately
      FocusScope.of(context).unfocus();

      setState(() {
        _scrollToMessageId = selectedMessageId;
      });
    }
  }

  // OFFLINE-FIRST SEARCH
  void _openOfflineSearch(
    BuildContext context,
    ThemeData theme,
    Color primaryColor,
  ) async {
    final selectedMessageId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => OfflineMessageSearchPage(
          chatId: widget.instituteId,
          chatType: 'staff_room',
        ),
      ),
    );

    // If a message was selected, scroll to it
    if (selectedMessageId != null && mounted) {
      // Hide keyboard immediately
      FocusScope.of(context).unfocus();

      setState(() {
        _scrollToMessageId = selectedMessageId;
      });
    }
  }

  Widget _buildNormalMessages(ThemeData theme, Color primaryColor) {
    return StreamBuilder<QuerySnapshot>(
      stream: _messagesStream,
      builder: (context, snapshot) {
        print(
          '🔄 StreamBuilder rebuilding - Pending: ${_pendingMessages.length}, Connection: ${snapshot.connectionState}',
        );

        if (snapshot.connectionState == ConnectionState.waiting &&
            _pendingMessages.isEmpty) {
          return Center(child: CircularProgressIndicator(color: primaryColor));
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final firestoreMessages = snapshot.data?.docs ?? [];

        // Merge pending and Firestore messages
        final allMessages = <Map<String, dynamic>>[];
        final pendingIdsToRemove = <String>[];

        print(
          '📋 Merging messages - Pending: ${_pendingMessages.length}, Firestore: ${firestoreMessages.length}',
        );

        // Add pending messages first, but check if they have a Firestore version
        for (final pendingMsg in _pendingMessages) {
          final pendingId = pendingMsg['id'] as String;
          final pendingSenderId = pendingMsg['senderId'];
          final pendingTimestamp = pendingMsg['createdAt'] as int;
          final pendingHasMultipleMedia = pendingMsg['multipleMedia'] != null;

          print('🔍 [MERGE] Checking pending message: $pendingId');
          print('   Sender: $pendingSenderId, Timestamp: $pendingTimestamp');

          // Get pending message attachment metadata for robust matching
          final pendingAttachmentName = pendingMsg['attachmentName'] as String?;
          final pendingAttachmentSize = pendingMsg['attachmentSize'] as int?;
          final pendingAttachmentType = pendingMsg['attachmentType'] as String?;

          // Check if this pending message now exists in Firestore
          final matchingServerDoc = firestoreMessages.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['isDeleted'] == true) return false;

            final serverSenderId = data['senderId'];
            final serverTimestamp = data['createdAt'];
            final serverTimestampMs = serverTimestamp is Timestamp
                ? serverTimestamp.millisecondsSinceEpoch
                : (serverTimestamp as int? ?? 0);

            // Match by sender and timestamp (within reasonable window)
            final senderMatch = serverSenderId == pendingSenderId;
            final timeDiff = serverTimestampMs - pendingTimestamp;
            final timeMatch =
                timeDiff >= 0 &&
                timeDiff < 10000; // 10 seconds window for network delays

            if (!senderMatch || !timeMatch) return false;

            // PERMANENT FIX: Match by attachment metadata for precise identification
            // This prevents false matches with other messages from same sender
            if (pendingAttachmentName != null &&
                pendingAttachmentSize != null) {
              final serverAttachmentName = data['attachmentName'] as String?;
              final serverAttachmentSize = data['attachmentSize'] as int?;

              final attachmentMatch =
                  serverAttachmentName == pendingAttachmentName &&
                  serverAttachmentSize == pendingAttachmentSize;

              if (attachmentMatch) {
                print('   ✅ Exact match found: ${doc.id}');
                print(
                  '      Attachment: $pendingAttachmentName (${pendingAttachmentSize} bytes)',
                );
                print('      Time diff: $timeDiff ms');
              }

              return attachmentMatch;
            }

            // For multi-media messages, match by sender + time + multipleMedia presence
            if (pendingHasMultipleMedia) {
              final serverHasMultipleMedia =
                  data['multipleMedia'] != null &&
                  (data['multipleMedia'] as List).isNotEmpty;
              return serverHasMultipleMedia;
            }

            // For text messages, just sender + time is sufficient
            return true;
          }).firstOrNull;

          if (matchingServerDoc != null) {
            // Found matching server version - remove pending
            print(
              '   ✅ Matched with server message: ${matchingServerDoc.id} - REMOVING pending',
            );
            pendingIdsToRemove.add(pendingId);
          } else {
            // Still uploading - keep in list
            // Use cached instance to maintain widget identity
            print('   ➕ No server match - KEEPING pending message');
            final cachedMsg = _messageCache[pendingId] ??=
                Map<String, dynamic>.from(pendingMsg);
            allMessages.add(cachedMsg);
            print('   ➕ Added pending message to allMessages: $pendingId');
          }
        }

        // Remove completed pending messages after frame to avoid flicker
        if (pendingIdsToRemove.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _pendingMessages.removeWhere(
                (m) => pendingIdsToRemove.contains(m['id']),
              );
              for (final id in pendingIdsToRemove) {
                _uploadingMessageIds.remove(id);
                _pendingUploadProgress.remove(id);
                _localFilePaths.remove(id);
                _progressNotifiers[id]?.dispose();
                _progressNotifiers.remove(id);
                _messageCache.remove(id); // Remove from cache too
              }
            });
          });
        }

        // Add Firestore messages
        for (final doc in firestoreMessages) {
          final data = doc.data() as Map<String, dynamic>;

          // Skip deleted messages
          if (data['isDeleted'] == true) {
            continue;
          }

          final messageId = doc.id;

          // Create a stable cached instance - NEVER MUTATE IT
          // This ensures Flutter recognizes the same object and doesn't rebuild widgets
          if (!_messageCache.containsKey(messageId)) {
            _messageCache[messageId] = {
              ...data,
              'id': messageId,
              'isPending': false,
            };
          }

          allMessages.add(_messageCache[messageId]!);
        }

        // Sort by timestamp
        allMessages.sort((a, b) {
          final aTime = a['createdAt'];
          final bTime = b['createdAt'];

          // Handle both Timestamp and int types
          final aMillis = aTime is Timestamp
              ? aTime.millisecondsSinceEpoch
              : (aTime as int? ?? 0);
          final bMillis = bTime is Timestamp
              ? bTime.millisecondsSinceEpoch
              : (bTime as int? ?? 0);

          return bMillis.compareTo(aMillis);
        });

        // Handle pending scroll request from search
        if (_scrollToMessageId != null &&
            !_isScrollingToMessage &&
            !_isProcessingScroll) {
          final messageId = _scrollToMessageId!;
          _scrollToMessageId = null; // Clear pending request
          _isScrollingToMessage = true; // Set flag to prevent auto-scroll
          _userHasScrolled = true; // Mark as user-initiated scroll

          // Schedule scroll after frame is rendered (single callback)
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;

            await scrollToMessage(messageId, allMessages);

            // Wait for scroll animation to complete, then reset scrolling flag
            await Future.delayed(const Duration(seconds: 3));
            if (mounted) {
              setState(() {
                _isScrollingToMessage = false;
                // Keep _userHasScrolled true - user must manually scroll to bottom to reset
              });
            }
          });
        }

        if (allMessages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 64,
                  color: theme.iconTheme.color?.withOpacity(0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'No messages yet',
                  style: TextStyle(
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start the conversation!',
                  style: TextStyle(
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.4),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }

        // Check if item count changed (avoid redundant callbacks)
        final itemCountChanged = allMessages.length != _lastItemCount;

        // Check if should auto-scroll (only when count increases and user is at bottom)
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
          key: const PageStorageKey(
            'staff_room_messages',
          ), // Prevent unnecessary rebuilds
          controller: scrollController, // Use controller from mixin
          reverse: true,
          padding: const EdgeInsets.all(16),
          itemCount: allMessages.length,
          physics: const ClampingScrollPhysics(), // Prevent auto-scroll bounce
          addAutomaticKeepAlives: true, // Keep alive built items
          addRepaintBoundaries: true, // Add repaint boundaries
          cacheExtent: 500, // Cache items beyond viewport
          itemBuilder: (context, index) {
            final message = allMessages[index];
            final messageId = message['id'] as String? ?? '';
            final isPending = message['isPending'] == true;

            // Debug logging for pending messages
            if (isPending && index == 0) {
              print('🔍 [RENDER] Pending message at top:');
              print('   ID: $messageId');
              print('   isPending: $isPending');
              print(
                '   Has multipleMedia: ${message['multipleMedia'] != null}',
              );
              print(
                '   Has attachmentUrl: ${message['attachmentUrl'] != null}',
              );
              print(
                '   isUploading: ${_uploadingMessageIds.contains(messageId)}',
              );

              if (message['multipleMedia'] != null) {
                final multipleMedia = message['multipleMedia'] as List;
                print('   MultipleMedia count: ${multipleMedia.length}');
                for (int i = 0; i < multipleMedia.length; i++) {
                  final media = multipleMedia[i] as Map;
                  final mediaId = media['messageId'];
                  print('     Media $i:');
                  print('       - messageId: $mediaId');
                  print('       - localPath: ${media['localPath']}');
                  print(
                    '       - progress: ${_pendingUploadProgress[mediaId]}',
                  );
                  print(
                    '       - in uploadingIds: ${_uploadingMessageIds.contains(mediaId)}',
                  );
                  print(
                    '       - has local file path: ${_localFilePaths.containsKey(mediaId)}',
                  );
                }
              }

              if (message['attachmentUrl'] != null) {
                print('   Single attachment:');
                print('     - progress: ${_pendingUploadProgress[messageId]}');
                print(
                  '     - localPath from map: ${_localFilePaths[messageId]}',
                );
                print(
                  '     - hasProgressNotifier: ${_progressNotifiers.containsKey(messageId)}',
                );
              }
            }

            final authProvider = Provider.of<AuthProvider>(
              context,
              listen: false,
            );
            final isMe = message['senderId'] == authProvider.currentUser?.uid;

            // Check if this message is highlighted
            final isHighlighted = highlightedMessageId == messageId;

            // Date separator logic
            final createdAt = message['createdAt'];
            final currentMillis = createdAt is Timestamp
                ? createdAt.millisecondsSinceEpoch
                : (createdAt as int? ?? 0);
            final currentDate = DateTime.fromMillisecondsSinceEpoch(
              currentMillis,
            );

            final isOldest = index == allMessages.length - 1;
            DateTime? nextDate;
            if (!isOldest) {
              final nextCreatedAt = allMessages[index + 1]['createdAt'];
              final nextMillis = nextCreatedAt is Timestamp
                  ? nextCreatedAt.millisecondsSinceEpoch
                  : (nextCreatedAt as int? ?? 0);
              nextDate = DateTime.fromMillisecondsSinceEpoch(nextMillis);
            }

            final showDayDivider =
                isOldest ||
                _formatDayLabel(currentDate) != _formatDayLabel(nextDate!);

            // Simplified container without heavy animations for pending messages
            if (isPending) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showDayDivider) _buildDayDivider(currentDate),
                  ValueListenableBuilder<bool>(
                    valueListenable: _isSelectionMode,
                    builder: (context, isSelectionMode, _) {
                      return ValueListenableBuilder<Set<String>>(
                        valueListenable: _selectedMessages,
                        builder: (context, selectedMessages, _) {
                          return HighlightedMessageWrapper(
                            key: getMessageKey(messageId),
                            isHighlighted: isHighlighted,
                            child: _MessageBubble(
                              key: ValueKey('bubble_$messageId'),
                              message: message,
                              isMe: isMe,
                              primaryColor: primaryColor,
                              uploadingMessageIds: _uploadingMessageIds,
                              pendingUploadProgress: _pendingUploadProgress,
                              localFilePaths: _localFilePaths,
                              progressNotifiers: _progressNotifiers,
                              selectionMode: isSelectionMode,
                              isSelected: selectedMessages.contains(messageId),
                              staffRoomId: widget.instituteId,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              );
            }

            // Full featured container with animations for non-pending messages
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showDayDivider) _buildDayDivider(currentDate),
                ValueListenableBuilder<bool>(
                  valueListenable: _isSelectionMode,
                  builder: (context, isSelectionMode, _) {
                    return ValueListenableBuilder<Set<String>>(
                      valueListenable: _selectedMessages,
                      builder: (context, selectedMessages, _) {
                        final isSelected = selectedMessages.contains(messageId);

                        return GestureDetector(
                          onLongPress: isMe
                              ? () {
                                  _isSelectionMode.value = true;
                                  _selectedMessages.value = {
                                    ...selectedMessages,
                                    messageId,
                                  };
                                }
                              : null,
                          onTap: isSelectionMode && isMe
                              ? () {
                                  if (isSelected) {
                                    final newSelection = Set<String>.from(
                                      selectedMessages,
                                    )..remove(messageId);
                                    _selectedMessages.value = newSelection;
                                    if (newSelection.isEmpty) {
                                      _isSelectionMode.value = false;
                                    }
                                  } else {
                                    _selectedMessages.value = {
                                      ...selectedMessages,
                                      messageId,
                                    };
                                  }
                                }
                              : null,
                          child: HighlightedMessageWrapper(
                            key: getMessageKey(messageId),
                            isHighlighted: isHighlighted,
                            child: _MessageBubble(
                              key: ValueKey('bubble_$messageId'),
                              message: message,
                              isMe: isMe,
                              primaryColor: primaryColor,
                              uploadingMessageIds: _uploadingMessageIds,
                              pendingUploadProgress: _pendingUploadProgress,
                              localFilePaths: _localFilePaths,
                              progressNotifiers: _progressNotifiers,
                              selectionMode: isSelectionMode,
                              isSelected: isSelected,
                              staffRoomId: widget.instituteId,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMessageInput(ThemeData theme, Color primaryColor) {
    final isDark = theme.brightness == Brightness.dark;

    // Recording UI
    return ValueListenableBuilder<bool>(
      valueListenable: _isRecording,
      builder: (context, isRecording, _) {
        if (isRecording) {
          return ValueListenableBuilder<int>(
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

                          _isRecording.value = false;
                          _recordingPath = null;
                          _recordingDuration.value = 0;

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
                        decoration: BoxDecoration(
                          color: primaryColor,
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
          );
        }

        // Normal input UI
        final hintColor = isDark ? Colors.white60 : const Color(0xFF94A3B8);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: isDark
                ? null
                : const Border(
                    top: BorderSide(color: Color(0xFFE2E8F0), width: 0.5),
                  ),
            boxShadow: isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, -4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, -2),
                    ),
                  ],
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                // Text Input with emoji button inside
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1F2C34)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.sentiment_satisfied_outlined,
                            color: hintColor,
                            size: 26,
                          ),
                          padding: const EdgeInsets.all(8),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Emoji picker coming soon'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                        ),
                        Expanded(
                          child: ValueListenableBuilder<bool>(
                            valueListenable: _isUploading,
                            builder: (context, isUploading, _) {
                              return TextField(
                                controller: _messageController,
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                  fontSize: 16,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Message',
                                  hintStyle: TextStyle(color: hintColor),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                ),
                                maxLines: null,
                                enabled: !isUploading,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                textInputAction: TextInputAction.send,
                                onChanged: (text) =>
                                    _hasText.value = text.trim().isNotEmpty,
                                onSubmitted: (_) => _sendMessage(),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                ValueListenableBuilder<bool>(
                  valueListenable: _isUploading,
                  builder: (context, isUploading, _) {
                    return IconButton(
                      icon: Icon(Icons.attach_file, color: hintColor, size: 26),
                      padding: const EdgeInsets.all(8),
                      onPressed: isUploading ? null : _showAttachmentPicker,
                    );
                  },
                ),
                const SizedBox(width: 8),
                // Mic/Send button
                ValueListenableBuilder<bool>(
                  valueListenable: _isUploading,
                  builder: (context, isUploading, _) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: _isRecording,
                      builder: (context, isRecording, _) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: _hasText,
                          builder: (context, hasText, _) {
                            return ValueListenableBuilder<int>(
                              valueListenable: _recordingDuration,
                              builder: (context, duration, _) {
                                return GestureDetector(
                                  onTap: isUploading
                                      ? null
                                      : hasText
                                      ? _sendMessage
                                      : isRecording
                                      ? _sendRecording // Stop and send recording
                                      : () async {
                                          try {
                                            // Start recording
                                            final permission =
                                                await _audioRecorder
                                                    .hasPermission();
                                            if (!permission) {
                                              if (mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Microphone permission required',
                                                    ),
                                                  ),
                                                );
                                              }
                                              return;
                                            }

                                            final directory =
                                                Directory.systemTemp;
                                            final timestamp = DateTime.now()
                                                .millisecondsSinceEpoch;
                                            final recordingPath =
                                                '${directory.path}/audio_$timestamp.m4a';

                                            await _audioRecorder.start(
                                              const RecordConfig(
                                                encoder: AudioEncoder.aacLc,
                                                sampleRate: 44100,
                                                numChannels: 2,
                                                bitRate: 128000,
                                              ),
                                              path: recordingPath,
                                            );

                                            _isRecording.value = true;
                                            _recordingPath = recordingPath;
                                            _recordingDuration.value = 0;

                                            _recordingTimer = Timer.periodic(
                                              const Duration(seconds: 1),
                                              (_) {
                                                _recordingDuration.value++;
                                              },
                                            );

                                            print(
                                              '🎤 Recording started: $recordingPath',
                                            );
                                          } catch (e) {
                                            print(
                                              '❌ Error starting recording: $e',
                                            );
                                          }
                                        },
                                  child: Opacity(
                                    opacity: isUploading ? 0.5 : 1.0,
                                    child: Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: isRecording
                                            ? Colors.red
                                            : primaryColor,
                                        shape: BoxShape.circle,
                                      ),
                                      child: isUploading
                                          ? const Center(
                                              child: SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                        Color
                                                      >(Colors.white),
                                                ),
                                              ),
                                            )
                                          : IconButton(
                                              icon: Icon(
                                                hasText
                                                    ? Icons.send_rounded
                                                    : (isRecording
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
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
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

      // First, verify ownership and collect media to delete
      final mediaToDelete = <String>[];
      final validMessages = <String>[];

      final batch = FirebaseFirestore.instance.batch();

      for (final messageId in messagesToDelete) {
        final messageRef = FirebaseFirestore.instance
            .collection('staff_rooms')
            .doc(widget.instituteId)
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

        // Collect ALL media for deletion (comprehensive extraction)
        // Extract from mediaMetadata (primary source)
        final mediaMetadata = data?['mediaMetadata'] as Map<String, dynamic>?;
        if (mediaMetadata != null) {
          final r2Key = mediaMetadata['r2Key'] as String?;
          if (r2Key != null && r2Key.isNotEmpty) {
            mediaToDelete.add(r2Key);
          }
          // Also check for thumbnail
          final thumbnailKey = mediaMetadata['thumbnailR2Key'] as String?;
          if (thumbnailKey != null && thumbnailKey.isNotEmpty) {
            mediaToDelete.add(thumbnailKey);
          }
        }

        // Extract from attachmentUrl (legacy field)
        if (data?['attachmentUrl'] != null) {
          final attachmentUrl = data!['attachmentUrl'] as String;
          if (attachmentUrl.contains(CloudflareConfig.r2Domain)) {
            try {
              final uri = Uri.parse(attachmentUrl);
              // Remove leading slash from path
              final key = uri.path.startsWith('/')
                  ? uri.path.substring(1)
                  : uri.path;
              if (key.isNotEmpty && !mediaToDelete.contains(key)) {
                mediaToDelete.add(key);
              }
            } catch (e) {
              print('⚠️  Failed to parse attachmentUrl: $e');
            }
          }
        }

        // Extract from thumbnailUrl (legacy field)
        if (data?['thumbnailUrl'] != null) {
          final thumbnailUrl = data!['thumbnailUrl'] as String;
          if (thumbnailUrl.contains(CloudflareConfig.r2Domain)) {
            try {
              final uri = Uri.parse(thumbnailUrl);
              final key = uri.path.startsWith('/')
                  ? uri.path.substring(1)
                  : uri.path;
              if (key.isNotEmpty && !mediaToDelete.contains(key)) {
                mediaToDelete.add(key);
              }
            } catch (e) {
              print('⚠️  Failed to parse thumbnailUrl: $e');
            }
          }
        }

        // Add to batch - clear all media references
        batch.update(messageRef, {
          'isDeleted': true,
          'deletedAt': FieldValue.serverTimestamp(),
          'text': 'This message was deleted',
          'attachmentUrl': null,
          'attachmentType': null,
          'attachmentName': null,
          'attachmentSize': null,
          'thumbnailUrl': null,
          'mediaMetadata': null, // Clear new mediaMetadata field
          'multipleMedia': null, // Clear multiple media if exists
        });
      }

      // Execute batch delete - all messages deleted instantly
      if (validMessages.isNotEmpty) {
        await batch.commit();

        // Delete media files in background (don't wait)
        if (mediaToDelete.isNotEmpty) {
          _deleteMediaFiles(mediaToDelete);
        }
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

  /// Delete media files from R2 storage to prevent storage bloat
  /// Runs in background after Firestore deletion
  void _deleteMediaFiles(List<String> keys) async {
    if (keys.isEmpty) return;

    print('🗑️  Deleting ${keys.length} media file(s) from R2...');

    try {
      final r2Service = CloudflareR2Service(
        accountId: CloudflareConfig.accountId,
        bucketName: CloudflareConfig.bucketName,
        accessKeyId: CloudflareConfig.accessKeyId,
        secretAccessKey: CloudflareConfig.secretAccessKey,
        r2Domain: CloudflareConfig.r2Domain,
      );

      int successCount = 0;
      for (final key in keys) {
        try {
          await r2Service.deleteFile(key: key);
          successCount++;
          print('  ✅ Deleted: $key');
        } catch (e) {
          print('  ⚠️  Failed to delete $key: $e');
          // Continue with next file
        }
      }

      print(
        '✅ R2 cleanup complete: $successCount/${keys.length} files deleted',
      );
    } catch (e) {
      print('❌ R2 cleanup failed: $e');
      // Non-critical error - don't show to user
    }
  }
}

class _MessageBubble extends StatefulWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  final Color primaryColor;
  final Set<String> uploadingMessageIds;
  final Map<String, double> pendingUploadProgress;
  final Map<String, String> localFilePaths;
  final Map<String, ValueNotifier<double>> progressNotifiers;
  final bool selectionMode;
  final bool isSelected;
  final String staffRoomId;

  const _MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.primaryColor,
    required this.uploadingMessageIds,
    required this.pendingUploadProgress,
    required this.localFilePaths,
    required this.progressNotifiers,
    this.selectionMode = false,
    this.isSelected = false,
    required this.staffRoomId,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // Must call for AutomaticKeepAliveClientMixin

    final messageId = widget.message['id'] as String? ?? 'unknown';
    final theme = Theme.of(context);
    final senderName = widget.message['senderName'] ?? 'Unknown';
    final senderRole = widget.message['senderRole'] ?? '';
    final text = widget.message['text'] ?? '';
    final createdAt = widget.message['createdAt'];
    final timestamp = createdAt is Timestamp
        ? createdAt.millisecondsSinceEpoch
        : (createdAt as int? ?? 0);
    final attachmentUrl = widget.message['attachmentUrl'] as String?;
    final attachmentType = widget.message['attachmentType'] as String?;
    final attachmentName = widget.message['attachmentName'] as String?;
    final attachmentSize = widget.message['attachmentSize'] as int?;
    final thumbnailUrl = widget.message['thumbnailUrl'] as String?;

    // Handle multipleMedia field - can be List or null
    List<dynamic>? multipleMedia;
    if (widget.message['multipleMedia'] != null) {
      final mediaField = widget.message['multipleMedia'];
      if (mediaField is List) {
        multipleMedia = mediaField;
      }
    }

    final isForwarded = widget.message['isForwarded'] == true;
    final isPending = widget.message['isPending'] == true;

    String timeStr = '';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    timeStr = DateFormat('HH:mm').format(date);

    final roleColor = senderRole == 'principal'
        ? widget.primaryColor
        : const Color(0xFFF97316); // Orange for teachers

    final hasAttachment = attachmentUrl != null && attachmentUrl.isNotEmpty;
    final hasMultipleMedia = multipleMedia != null && multipleMedia.isNotEmpty;
    final isPoll = widget.message['type'] == 'poll';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisAlignment: widget.isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          // Use Flexible for polls, Container with maxWidth for others
          isPoll
              ? Flexible(
                  child: Column(
                    crossAxisAlignment: widget.isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (!widget.isMe) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 12, bottom: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: roleColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  senderRole == 'principal'
                                      ? 'Principal'
                                      : 'Teacher',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: roleColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  senderName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: theme.textTheme.bodyMedium?.color
                                        ?.withOpacity(0.8),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: Align(
                          alignment: widget.isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: PollMessageWidget(
                            poll: PollModel.fromMap(widget.message, messageId),
                            chatId: widget.staffRoomId,
                            chatType: 'staff_room',
                            isOwnMessage: widget.isMe,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  child: Column(
                    crossAxisAlignment: widget.isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (!widget.isMe) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 12, bottom: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: roleColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  senderRole == 'principal'
                                      ? 'Principal'
                                      : 'Teacher',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: roleColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  senderName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: theme.textTheme.bodyMedium?.color
                                        ?.withOpacity(0.8),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // Multi-image bubble (WhatsApp-style grid)
                      if (hasMultipleMedia)
                        Column(
                          crossAxisAlignment: widget.isMe
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            MultiImageMessageBubble(
                              key: ValueKey('${messageId}_multi_image'),
                              imageUrls: multipleMedia.map<String>((media) {
                                // Cast to Map<String, dynamic> first to access fields
                                final mediaMap = media is Map<String, dynamic>
                                    ? media
                                    : (media as Map).cast<String, dynamic>();

                                if (isPending) {
                                  return mediaMap['localPath'] as String? ?? '';
                                } else {
                                  return mediaMap['publicUrl'] as String? ?? '';
                                }
                              }).toList(),
                              isMe: widget.isMe,
                              onImageTap: (index) {
                                // Open full-screen image gallery
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => _ImageGalleryViewer(
                                      mediaList: multipleMedia!,
                                      initialIndex: index,
                                      isPending: isPending,
                                    ),
                                  ),
                                );
                              },
                              uploadProgress: isPending
                                  ? multipleMedia.map<double?>((media) {
                                      final mediaMap =
                                          media is Map<String, dynamic>
                                          ? media
                                          : (media as Map)
                                                .cast<String, dynamic>();
                                      final mediaId =
                                          mediaMap['messageId'] as String?;
                                      return mediaId != null
                                          ? widget
                                                .pendingUploadProgress[mediaId]
                                          : null;
                                    }).toList()
                                  : null,
                            ),
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 12,
                                right: 12,
                              ),
                              child: Text(
                                timeStr,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.textTheme.bodyMedium?.color
                                      ?.withOpacity(0.5),
                                ),
                              ),
                            ),
                          ],
                        )
                      // Single attachment or text message
                      else
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: hasAttachment && text.isEmpty ? 4 : 16,
                            vertical: hasAttachment && text.isEmpty ? 4 : 10,
                          ),
                          decoration: BoxDecoration(
                            color: widget.isMe
                                ? widget.primaryColor
                                : theme.colorScheme.surfaceContainerHighest
                                      .withOpacity(0.7),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(widget.isMe ? 16 : 4),
                              bottomRight: Radius.circular(
                                widget.isMe ? 4 : 16,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isForwarded) ...[
                                Row(
                                  children: [
                                    Icon(
                                      Icons.forward,
                                      size: 14,
                                      color: widget.isMe
                                          ? Colors.white70
                                          : Colors.black54,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Forwarded',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                        color: widget.isMe
                                            ? Colors.white70
                                            : Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                              ],
                              if (hasAttachment) ...[
                                _buildAttachmentWidget(
                                  attachmentUrl,
                                  attachmentType ?? 'application/octet-stream',
                                  attachmentName,
                                  attachmentSize ?? 0,
                                  thumbnailUrl,
                                  isPending,
                                  messageId,
                                ),
                                if (text.isNotEmpty) const SizedBox(height: 8),
                              ],
                              if (text.isNotEmpty)
                                Text(
                                  text,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: widget.isMe
                                        ? Colors.white
                                        : theme.textTheme.bodyLarge?.color,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Text(
                                timeStr,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: widget.isMe
                                      ? Colors.white.withOpacity(0.7)
                                      : theme.textTheme.bodyMedium?.color
                                            ?.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
          if (widget.selectionMode && widget.isMe)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(
                widget.isSelected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: widget.isSelected ? widget.primaryColor : Colors.grey,
                size: 24,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAttachmentWidget(
    String? url,
    String type,
    String? name,
    int fileSize,
    String? thumbnailUrl,
    bool isPending,
    String messageId,
  ) {
    // For pending messages, use local path
    String? localPath;
    String r2Key = '';

    if (isPending) {
      localPath = widget.localFilePaths[messageId];
      r2Key = 'pending/$messageId';
    } else {
      // Extract R2 key from URL
      final uri = Uri.tryParse(url ?? '');
      if (uri == null) return const SizedBox();
      r2Key = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    }

    final isUploading = widget.uploadingMessageIds.contains(messageId);
    final progressNotifier = widget.progressNotifiers[messageId];

    // Use ValueListenableBuilder for smooth progress updates without rebuilding parent
    if (isUploading && progressNotifier != null) {
      return ValueListenableBuilder<double>(
        valueListenable: progressNotifier,
        builder: (context, progress, child) {
          return MediaPreviewCard(
            r2Key: r2Key,
            fileName: name ?? _fileNameFromUrl(url ?? ''),
            mimeType: type,
            fileSize: fileSize,
            thumbnailBase64: thumbnailUrl,
            localPath: localPath,
            isMe: widget.isMe,
            selectionMode: widget.selectionMode,
            uploading: true,
            uploadProgress: progress,
          );
        },
      );
    }

    return MediaPreviewCard(
      r2Key: r2Key,
      fileName: name ?? _fileNameFromUrl(url ?? ''),
      mimeType: type,
      fileSize: fileSize,
      thumbnailBase64: thumbnailUrl,
      localPath: localPath,
      isMe: widget.isMe,
      selectionMode: widget.selectionMode,
      uploading: false,
    );
  }

  String _fileNameFromUrl(String url) {
    try {
      return url.split('/').last.split('?').first;
    } catch (_) {
      return 'file';
    }
  }
}

/// Full-screen image gallery viewer for multi-image messages
class _ImageGalleryViewer extends StatefulWidget {
  final List<dynamic> mediaList;
  final int initialIndex;
  final bool isPending;

  const _ImageGalleryViewer({
    required this.mediaList,
    required this.initialIndex,
    required this.isPending,
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
          final media = widget.mediaList[index];
          final localPath = media['localPath'] as String?;
          final publicUrl = media['publicUrl'] as String?;

          return _buildImageViewer(index, localPath, publicUrl);
        },
      ),
    );
  }

  Widget _buildImageViewer(int index, String? localPath, String? publicUrl) {
    final file = (localPath != null && localPath.isNotEmpty)
        ? File(localPath)
        : null;
    final hasLocalFile = file != null && file.existsSync();
    final hasNetwork = publicUrl != null && publicUrl.isNotEmpty;

    Widget imageWidget;

    if (hasLocalFile) {
      imageWidget = RepaintBoundary(
        child: Image.file(
          file,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          cacheWidth: 1200,
          errorBuilder: (_, __, ___) => _buildFallbackImage(),
        ),
      );
    } else if (hasNetwork) {
      imageWidget = RepaintBoundary(
        child: CachedNetworkImage(
          imageUrl: publicUrl,
          key: ValueKey(publicUrl),
          cacheKey: publicUrl,
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
          errorWidget: (context, url, error) => _buildFallbackImage(),
        ),
      );
    } else {
      imageWidget = _buildFallbackImage();
    }

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

  Widget _buildFallbackImage() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image, size: 64, color: Colors.white54),
          SizedBox(height: 16),
          Text('Image not available', style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}
