import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';
import '../../services/chat_service.dart';
import '../../services/media_upload_service.dart';
import '../../services/background_upload_service.dart';
import '../../services/cloudflare_r2_service.dart';
import '../../services/local_cache_service.dart';
import '../../config/cloudflare_config.dart';
import '../../widgets/media_preview_card.dart';
import '../../widgets/modern_attachment_sheet.dart';
import '../../repositories/local_message_repository.dart';
import '../../services/firebase_message_sync_service.dart';
import '../../utils/message_scroll_highlight_mixin.dart';
import '../messages/offline_message_search_page.dart';

class TeacherChatScreen extends StatefulWidget {
  final String schoolCode;
  final String teacherId;
  final String parentId;
  final String studentId;
  final String parentName;
  final String className;
  final String? section;
  final String? parentAvatarUrl;

  const TeacherChatScreen({
    super.key,
    required this.schoolCode,
    required this.teacherId,
    required this.parentId,
    required this.studentId,
    required this.parentName,
    required this.className,
    this.section,
    this.parentAvatarUrl,
  });

  @override
  State<TeacherChatScreen> createState() => _TeacherChatScreenState();
}

class _TeacherChatScreenState extends State<TeacherChatScreen>
    with MessageScrollAndHighlightMixin {
  final ChatService _chat = ChatService();
  final TextEditingController _controller = TextEditingController();
  String? _conversationId;
  // Track messages already scheduled for read marking to avoid re-scheduling.
  final Set<String> _scheduledReadIds = <String>{};

  // Track the last known message count to detect new data
  int _lastMessageCount = 0;

  // Offline-first message search
  LocalMessageRepository? _localRepo;
  FirebaseMessageSyncService? _syncService;

  // Media handling
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  late final MediaUploadService _mediaUploadService;
  final bool _isUploading = false;

  // Audio recording
  final ValueNotifier<bool> _isRecording = ValueNotifier<bool>(false);
  final ValueNotifier<int> _recordingDuration = ValueNotifier<int>(0);
  Timer? _recordingTimer;
  String? _recordingPath;

  // Pending uploads tracking - immediate preview
  final List<Map<String, dynamic>> _pendingMessages = [];
  final Map<String, double> _pendingUploadProgress = {};

  // Selection mode for deleting messages
  bool _selectionMode = false;
  final Set<String> _selectedMessages = {};

  Future<void> _batchUpdateIncoming(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (_conversationId == null) return;

    final deliveryBatch = FirebaseFirestore.instance.batch();
    bool deliveryUpdates = false;
    final List<DocumentReference<Map<String, dynamic>>> toMarkRead = [];

    for (final d in docs) {
      final data = d.data();
      final senderRole = (data['senderRole'] ?? '').toString();
      if (senderRole != 'teacher') {
        // Incoming from parent – mark delivered immediately.
        if (data['deliveredToTeacher'] != true) {
          deliveryBatch.update(d.reference, {'deliveredToTeacher': true});
          deliveryUpdates = true;
        }
        // Schedule read marking (delayed) if not already read/scheduled.
        final id = d.id;
        if (data['readByTeacher'] != true && !_scheduledReadIds.contains(id)) {
          _scheduledReadIds.add(id);
          toMarkRead.add(d.reference);
        }
      }
    }

    if (deliveryUpdates) {
      await deliveryBatch.commit();
    }

    if (toMarkRead.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 1200), () async {
        if (!mounted || _conversationId == null) return;
        final readBatch = FirebaseFirestore.instance.batch();
        for (final ref in toMarkRead) {
          readBatch.update(ref, {'readByTeacher': true});
        }
        await readBatch.commit();
        await _chat.markAsRead(
          conversationId: _conversationId!,
          viewerRole: 'teacher',
        );
      });
    }
  }

  @override
  void initState() {
    super.initState();

    // Initialize MediaUploadService with CloudflareConfig
    final r2Service = CloudflareR2Service(
      accountId: CloudflareConfig.accountId,
      bucketName: CloudflareConfig.bucketName,
      accessKeyId: CloudflareConfig.accessKeyId,
      secretAccessKey: CloudflareConfig.secretAccessKey,
      r2Domain: CloudflareConfig.r2Domain,
    );

    _mediaUploadService = MediaUploadService(
      r2Service: r2Service,
      firestore: FirebaseFirestore.instance,
      cacheService: LocalCacheService(),
    );

    _controller.addListener(() => setState(() {}));

    // Listen to background upload progress
    BackgroundUploadService()
        .onUploadProgress = (String messageId, bool isUploading, double progress) {
      if (!mounted) return;
      print(
        '📊 Upload progress: $messageId - isUploading: $isUploading, progress: ${(progress * 100).toInt()}%',
      );

      if (isUploading) {
        // Only setState for upload progress updates
        setState(() {
          _pendingUploadProgress[messageId] = progress;
        });
      } else {
        // Upload complete - remove silently without setState
        // StreamBuilder will rebuild when Firestore syncs
        _pendingUploadProgress.remove(messageId);
        print(
          '✅ Upload complete: $messageId - Removed silently, waiting for Firestore sync',
        );
      }
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureConversation();
      _initOfflineFirst();
    });
  }

  void _initOfflineFirst() async {
    try {
      _localRepo = LocalMessageRepository();
      _syncService = FirebaseMessageSyncService(_localRepo!);

      await _localRepo!.initialize();

      if (_conversationId == null) {
        // Wait for conversation ID to be set
        await Future.delayed(const Duration(milliseconds: 500));
        if (_conversationId == null) return;
      }

      print('💬 Teacher-Parent Chat - Initializing offline-first');
      print('   Conversation ID: $_conversationId');

      // Load from cache first
      final cachedMessages = await _localRepo!.getMessagesForChat(
        _conversationId!,
        limit: 50,
      );

      if (cachedMessages.isEmpty) {
        print('📥 No cache - fetching initial messages from Firebase...');
        await _syncService!.initialSyncForChat(
          chatId: _conversationId!,
          chatType: 'private',
          limit: 50,
        );
        print('✅ Initial sync completed');
      } else {
        print('✅ Loaded ${cachedMessages.length} messages from cache');
        _syncService!.syncNewMessages(
          chatId: _conversationId!,
          chatType: 'private',
          lastTimestamp: cachedMessages.first.timestamp,
        );
      }

      // Start real-time sync
      print('🔄 Starting real-time sync for teacher-parent chat');
      await _syncService!.startSyncForChat(
        chatId: _conversationId!,
        chatType: 'private',
        userId: widget.teacherId,
      );
      print('✅ Real-time sync started successfully');
    } catch (e) {
      print('❌ Error initializing offline-first: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _audioRecorder.dispose();
    _recordingTimer?.cancel();
    _isRecording.dispose();
    _recordingDuration.dispose();

    // Clear upload progress callback
    BackgroundUploadService().onUploadProgress = null;

    super.dispose();
  }

  Future<void> _ensureConversation() async {
    final id = await _chat.ensureConversation(
      schoolCode: widget.schoolCode,
      teacherId: widget.teacherId,
      parentId: widget.parentId,
      studentId: widget.studentId,
      studentName: widget.parentName, // not used by teacher, placeholder
      className: widget.className,
      section: widget.section,
    );

    setState(() => _conversationId = id);
  }

  void _openSearch() {
    if (_conversationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait for chat to load...')),
      );
      return;
    }

    Navigator.of(context)
        .push<String?>(
          MaterialPageRoute(
            builder: (context) => OfflineMessageSearchPage(
              chatId: _conversationId!,
              chatType: 'private',
            ),
          ),
        )
        .then((messageId) async {
          if (messageId != null && _localRepo != null) {
            // Scroll to the message
            final localMsg = await _localRepo!.getMessageById(messageId);
            if (localMsg != null) {
              await scrollToMessage(messageId, [
                {'id': messageId},
              ]);
            }
          }
        });
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        _recordingPath = '${directory.path}/recording_$timestamp.m4a';

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacHe,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: _recordingPath!,
        );

        _isRecording.value = true;
        _recordingDuration.value = 0;
        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          _recordingDuration.value++;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
      }
    } catch (e) {
      print('❌ Error starting recording: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error starting recording: $e')));
    }
  }

  Future<void> _stopAndDeleteRecording() async {
    try {
      await _audioRecorder.stop();
      _recordingTimer?.cancel();
      _isRecording.value = false;
      _recordingDuration.value = 0;

      if (_recordingPath != null) {
        final file = File(_recordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
        _recordingPath = null;
      }
    } catch (e) {
      print('❌ Error deleting recording: $e');
    }
  }

  Future<void> _stopAndSendRecording() async {
    try {
      final path = await _audioRecorder.stop();
      _recordingTimer?.cancel();
      _isRecording.value = false;
      final duration = _recordingDuration.value;
      _recordingDuration.value = 0;

      if (path == null || _conversationId == null) {
        print('❌ Recording path or conversation ID is null');
        return;
      }

      final file = File(path);
      if (!await file.exists()) {
        print('❌ Recording file does not exist');
        return;
      }

      // Create messageId for tracking
      final messageId =
          'upload_${DateTime.now().millisecondsSinceEpoch}_${widget.teacherId.hashCode}';
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // Create pending message immediately
      final pendingMetadata = {
        'messageId': messageId,
        'r2Key': 'pending/$messageId',
        'publicUrl': '',
        'localPath': file.path,
        'thumbnail': '',
        'fileSize': await file.length(),
        'mimeType': 'audio/m4a',
        'originalFileName': fileName,
      };

      final pendingMessage = {
        'messageId': messageId,
        'senderRole': 'teacher',
        'text': '',
        'mediaMetadata': pendingMetadata,
        'createdAt': DateTime.now(),
        'isPending': true,
      };

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        _pendingUploadProgress[messageId] = 0.0;
      });

      // Queue upload in background service
      await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: _conversationId!,
        senderId: widget.teacherId,
        senderRole: 'teacher',
        mediaType: 'message',
        messageId: messageId,
      );

      _recordingPath = null;
    } catch (e) {
      print('❌ Error sending recording: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error sending recording: $e')));
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    print('🎨 TeacherChatScreen build() called - parentId: ${widget.parentId}');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF6F7F8),
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        elevation: 0.5,
        titleSpacing: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close, size: 24),
                onPressed: () {
                  setState(() {
                    _selectionMode = false;
                    _selectedMessages.clear();
                  });
                },
              )
            : IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new,
                  size: 20,
                  color: isDark ? Colors.white : Colors.black,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: _selectionMode
            ? Text(
                '${_selectedMessages.length} selected',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              )
            : Row(
                children: [
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.grey.shade800,
                    backgroundImage:
                        widget.parentAvatarUrl != null &&
                            widget.parentAvatarUrl!.isNotEmpty
                        ? NetworkImage(widget.parentAvatarUrl!)
                        : null,
                    child:
                        widget.parentAvatarUrl == null ||
                            widget.parentAvatarUrl!.isEmpty
                        ? const Icon(Icons.person, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.parentName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        Text(
                          '${widget.className}${widget.section != null ? ' - ${widget.section}' : ''}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          if (_selectionMode)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _selectedMessages.isEmpty
                  ? null
                  : _deleteSelectedMessages,
              tooltip: 'Delete selected',
            )
          else
            IconButton(
              icon: Icon(
                Icons.search,
                color: isDark ? Colors.white : Colors.black,
              ),
              onPressed: _openSearch,
              tooltip: 'Search messages',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _conversationId == null
                ? const SizedBox()
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _chat.messagesStream(_conversationId!),
                    builder: (context, snapshot) {
                      final docs = snapshot.data?.docs ?? [];

                      // Only update batch if message count changed (new messages arrived)
                      if (_conversationId != null &&
                          docs.isNotEmpty &&
                          docs.length != _lastMessageCount) {
                        final oldCount = _lastMessageCount;
                        _lastMessageCount = docs.length;
                        print(
                          '📨 New messages detected: $oldCount -> ${docs.length}',
                        );

                        // Schedule batch update without addPostFrameCallback to avoid flickering
                        Future.microtask(() => _batchUpdateIncoming(docs));

                        // Auto-scroll to bottom only if user is already at or near the bottom
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (scrollController.hasClients) {
                            final currentOffset = scrollController.offset;
                            final isAtBottom = currentOffset < 300;
                            print(
                              '🔍 StreamBuilder scroll check: offset=$currentOffset, isAtBottom=$isAtBottom',
                            );

                            if (isAtBottom) {
                              print(
                                '⬇️ Auto-scrolling to bottom from StreamBuilder',
                              );
                              scrollController.animateTo(
                                0,
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                              );
                            } else {
                              print('⏸️ Not auto-scrolling - user scrolled up');
                            }
                          } else {
                            print('❌ Cannot check scroll - no clients');
                          }
                        });
                      }

                      // Combine pending messages with Firestore messages
                      // Filter out pending messages if a Firestore message with same content exists
                      final firestoreMessages = docs.map((d) {
                        final data = d.data();
                        data['messageId'] =
                            d.id; // Add document ID as messageId
                        return data;
                      }).toList();

                      // Create set of Firestore message IDs for quick lookup
                      final firestoreMessageIds = firestoreMessages
                          .map((m) => m['messageId'] as String)
                          .toSet();

                      // Remove pending messages that have been uploaded or already exist in Firestore
                      final activePending = _pendingMessages.where((pending) {
                        final messageId = pending['messageId'] as String;
                        // Keep only if still uploading AND not yet in Firestore
                        return _pendingUploadProgress.containsKey(messageId) &&
                            !firestoreMessageIds.contains(messageId);
                      }).toList();

                      final combinedMessages = [
                        ...activePending,
                        ...firestoreMessages,
                      ];

                      // Sort by timestamp descending (newest first)
                      // Since ListView has reverse: true, newest first = displayed at bottom (index 0)
                      combinedMessages.sort((a, b) {
                        final aTime = a['timestamp'];
                        final bTime = b['timestamp'];
                        if (aTime == null) {
                          return -1; // pending messages go to beginning (bottom)
                        }
                        if (bTime == null) return 1;
                        return bTime.compareTo(aTime); // descending
                      });

                      print(
                        '📋 Messages: ${activePending.length} pending + ${firestoreMessages.length} firestore = ${combinedMessages.length} total',
                      );

                      return ListView.separated(
                        controller: scrollController,
                        reverse: true, // Show newest messages at bottom
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (context, index) {
                          final msg = combinedMessages[index];
                          final isPending = msg['isPending'] == true;
                          final isTeacher = msg['senderRole'] == 'teacher';
                          final deliveredToParent =
                              (msg['deliveredToParent'] ?? false) as bool;
                          final readByParent =
                              (msg['readByParent'] ?? false) as bool;
                          final messageId = msg['messageId'] as String?;
                          final isDeleted = msg['isDeleted'] == true;

                          // Skip deleted messages - don't show anything
                          if (isDeleted) {
                            return const SizedBox.shrink();
                          }

                          return GestureDetector(
                            onLongPress:
                                isTeacher && !isPending && messageId != null
                                ? () {
                                    print(
                                      '🔍 Long press detected - entering selection mode',
                                    );
                                    setState(() {
                                      _selectionMode = true;
                                      _selectedMessages.add(messageId);
                                    });
                                  }
                                : null,
                            onTap:
                                _selectionMode &&
                                    isTeacher &&
                                    !isPending &&
                                    messageId != null
                                ? () {
                                    setState(() {
                                      if (_selectedMessages.contains(
                                        messageId,
                                      )) {
                                        _selectedMessages.remove(messageId);
                                        if (_selectedMessages.isEmpty) {
                                          _selectionMode = false;
                                        }
                                      } else {
                                        _selectedMessages.add(messageId);
                                      }
                                    });
                                  }
                                : null,
                            child: Row(
                              mainAxisAlignment: isTeacher
                                  ? MainAxisAlignment.end
                                  : MainAxisAlignment.start,
                              children: [
                                if (!isTeacher && _selectionMode)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: CircleAvatar(
                                      radius: 12,
                                      backgroundColor:
                                          _selectedMessages.contains(messageId)
                                          ? const Color(0xFFFFA726)
                                          : Colors.grey.shade700,
                                      child:
                                          _selectedMessages.contains(messageId)
                                          ? const Icon(
                                              Icons.check,
                                              size: 16,
                                              color: Colors.white,
                                            )
                                          : null,
                                    ),
                                  ),
                                Flexible(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 360,
                                    ),
                                    child: Stack(
                                      children: [
                                        // If message has ONLY media (no text), show media without bubble
                                        if (msg['mediaMetadata'] != null &&
                                            (msg['text'] ?? '').isEmpty)
                                          _buildMediaAttachment(
                                            msg['mediaMetadata'],
                                            isTeacher,
                                            isPending: isPending,
                                            messageId: msg['messageId'],
                                          )
                                        else
                                          // Otherwise show message bubble with media/text
                                          DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: isTeacher
                                                  ? const Color(0xFF1362EB)
                                                  : (isDark
                                                        ? const Color(
                                                            0xFF2A2A2A,
                                                          )
                                                        : Colors.grey.shade200),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    12,
                                                  ).copyWith(
                                                    bottomRight: isTeacher
                                                        ? const Radius.circular(
                                                            4,
                                                          )
                                                        : null,
                                                    bottomLeft: !isTeacher
                                                        ? const Radius.circular(
                                                            4,
                                                          )
                                                        : null,
                                                  ),
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 12,
                                                  ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  // Media handling
                                                  if (msg['mediaMetadata'] !=
                                                      null) ...[
                                                    _buildMediaAttachment(
                                                      msg['mediaMetadata'],
                                                      isTeacher,
                                                      isPending: isPending,
                                                      messageId:
                                                          msg['messageId'],
                                                    ),
                                                    if ((msg['text'] ?? '')
                                                        .isNotEmpty)
                                                      const SizedBox(height: 8),
                                                  ],
                                                  if ((msg['text'] ?? '')
                                                      .isNotEmpty)
                                                    Text(
                                                      msg['text'] ?? '',
                                                      style: TextStyle(
                                                        color: isTeacher
                                                            ? Colors.white
                                                            : (isDark
                                                                  ? Colors.white
                                                                  : Colors
                                                                        .black87),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        // Show upload progress overlay for pending messages
                                        if (isPending &&
                                            _pendingUploadProgress.containsKey(
                                              msg['messageId'],
                                            ))
                                          Positioned.fill(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(
                                                  0.5,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Center(
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    SizedBox(
                                                      width: 48,
                                                      height: 48,
                                                      child: CircularProgressIndicator(
                                                        value:
                                                            _pendingUploadProgress[msg['messageId']],
                                                        strokeWidth: 4,
                                                        valueColor:
                                                            const AlwaysStoppedAnimation<
                                                              Color
                                                            >(Colors.white),
                                                        backgroundColor: Colors
                                                            .white
                                                            .withOpacity(0.3),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      '${(_pendingUploadProgress[msg['messageId']]! * 100).toInt()}%',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (isTeacher && _selectionMode)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: CircleAvatar(
                                      radius: 12,
                                      backgroundColor:
                                          _selectedMessages.contains(messageId)
                                          ? const Color(0xFFFFA726)
                                          : Colors.grey.shade700,
                                      child:
                                          _selectedMessages.contains(messageId)
                                          ? const Icon(
                                              Icons.check,
                                              size: 16,
                                              color: Colors.white,
                                            )
                                          : null,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemCount: combinedMessages.length,
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            minimum: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: ValueListenableBuilder<bool>(
                valueListenable: _isRecording,
                builder: (context, isRecording, _) {
                  if (isRecording) {
                    // Recording UI
                    return Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF2A2A2A)
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: _stopAndDeleteRecording,
                            icon: Icon(
                              Icons.delete,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.mic, color: Colors.red),
                          const SizedBox(width: 8),
                          ValueListenableBuilder<int>(
                            valueListenable: _recordingDuration,
                            builder: (context, duration, _) {
                              return Text(
                                _formatDuration(duration),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              );
                            },
                          ),
                          const Spacer(),
                          CircleAvatar(
                            backgroundColor: const Color(0xFF1362EB),
                            child: IconButton(
                              onPressed: _stopAndSendRecording,
                              icon: const Icon(Icons.send, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // Normal input UI
                  return Row(
                    children: [
                      IconButton(
                        onPressed: _isUploading ? null : _showMediaOptions,
                        icon: Icon(
                          Icons.attach_file,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade700,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Type your message...',
                            filled: true,
                            fillColor: isDark
                                ? const Color(0xFF2A2A2A)
                                : Colors.grey.shade200,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(9999),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(9999),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(9999),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: _isUploading
                            ? Colors.grey
                            : const Color(0xFF1362EB),
                        child: IconButton(
                          onPressed: (_isUploading || _conversationId == null)
                              ? null
                              : _controller.text.trim().isNotEmpty
                              ? () => _sendMessage()
                              : () => _startRecording(),
                          icon: Icon(
                            _controller.text.trim().isNotEmpty
                                ? Icons.send
                                : Icons.mic,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(String messageId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B141A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Delete for Everyone',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessageForEveryone(messageId);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteMessageForEveryone(String messageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text(
            'Delete Message?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'This message will be deleted for everyone in this conversation.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirmed != true || _conversationId == null) return;

    try {
      await _chat.deleteMessage(
        conversationId: _conversationId!,
        messageId: messageId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message deleted for everyone'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteSelectedMessages() async {
    if (_selectedMessages.isEmpty || _conversationId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text(
            'Delete Messages?',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'Delete ${_selectedMessages.length} selected message${_selectedMessages.length != 1 ? 's' : ''} for everyone in this conversation?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      final batch = FirebaseFirestore.instance.batch();
      final conversationRef = FirebaseFirestore.instance
          .collection('conversations')
          .doc(_conversationId!);

      for (final messageId in _selectedMessages) {
        batch.update(conversationRef.collection('messages').doc(messageId), {
          'isDeleted': true,
          'text': '',
          'mediaMetadata': FieldValue.delete(),
        });
      }

      await batch.commit();

      if (mounted) {
        final deletedCount = _selectedMessages.length;

        setState(() {
          _selectionMode = false;
          _selectedMessages.clear();
        });

        // Scroll to bottom after deletion
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollController.hasClients) {
            scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$deletedCount message${deletedCount != 1 ? 's' : ''} deleted for everyone',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete messages: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildMediaAttachment(
    Map<String, dynamic> metadata,
    bool isMe, {
    bool isPending = false,
    String? messageId,
  }) {
    // Convert map to MediaMetadata
    final r2Key = metadata['r2Key'] as String? ?? '';
    final fileName = _fileNameFromR2Key(r2Key);
    final mimeType =
        metadata['mimeType'] as String? ?? 'application/octet-stream';
    final fileSize = metadata['fileSize'] as int? ?? 0;
    final thumbnailBase64 = metadata['thumbnail'] as String?;
    final localPath = metadata['localPath'] as String?;

    return MediaPreviewCard(
      r2Key: r2Key,
      fileName: fileName,
      mimeType: mimeType,
      fileSize: fileSize,
      thumbnailBase64: thumbnailBase64,
      localPath: localPath,
      isMe: isMe,
      selectionMode: _selectionMode, // Disable interactions in selection mode
    );
  }

  String _fileNameFromR2Key(String r2Key) {
    // Extract filename from R2 key (format: media/timestamp/filename.ext)
    final parts = r2Key.split('/');
    return parts.isNotEmpty ? parts.last : 'file';
  }

  String _extractR2Key(String url) {
    final uri = Uri.parse(url);
    final path = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    return path;
  }

  void _showMediaOptions() {
    showModernAttachmentSheet(
      context,
      onCameraTap: _pickAndSendCamera,
      onImageTap: _pickAndSendImages, // Changed to multi-image
      onDocumentTap: _pickAndSendPDF,
      onAudioTap: _pickAndSendAudio,
    );
  }

  Future<void> _pickAndSendCamera() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );
      if (image == null) return;

      final file = File(image.path);
      if (!file.existsSync()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Image file not found')));
        return;
      }

      if (_conversationId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Initializing conversation...')),
        );
        return;
      }

      // Create messageId for tracking
      final messageId =
          'upload_${DateTime.now().millisecondsSinceEpoch}_${widget.teacherId.hashCode}';

      // Create pending message immediately
      final pendingMetadata = {
        'messageId': messageId,
        'r2Key': 'pending/$messageId',
        'publicUrl': '',
        'localPath': file.path,
        'thumbnail': file.path,
        'fileSize': await file.length(),
        'mimeType': 'image/jpeg',
        'originalFileName':
            'camera_${DateTime.now().millisecondsSinceEpoch}.jpg',
      };

      final pendingMessage = {
        'messageId': messageId,
        'senderRole': 'teacher',
        'text': '',
        'mediaMetadata': pendingMetadata,
        'createdAt': DateTime.now(),
        'isPending': true,
      };

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        _pendingUploadProgress[messageId] = 0.0;
      });

      // Queue upload in background service
      await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: _conversationId!,
        senderId: widget.teacherId,
        senderRole: 'teacher',
        mediaType: 'message',
        messageId: messageId,
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to queue image: $e')));
    }
  }

  Future<void> _sendMessage({Map<String, dynamic>? mediaMetadata}) async {
    final text = _controller.text.trim();
    if (text.isEmpty && mediaMetadata == null) return;
    if (_conversationId == null) return;

    _controller.clear();

    try {
      await _chat.sendMessage(
        conversationId: _conversationId!,
        text: text,
        senderRole: 'teacher',
        mediaMetadata: mediaMetadata,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );
      if (image == null) return;

      final file = File(image.path);
      if (!file.existsSync()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Image file not found')));
        return;
      }

      if (_conversationId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Initializing conversation...')),
        );
        return;
      }

      // Queue upload in background service
      final uploadId = await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: _conversationId!,
        senderId: widget.teacherId,
        senderRole: 'teacher',
        mediaType: 'message',
      );

      // Show confirmation
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Image queued for upload'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              // Could navigate to uploads page if needed
            },
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to queue image: $e')));
    }
  }

  /// Pick and send multiple images (up to 5)
  Future<void> _pickAndSendImages() async {
    if (_conversationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Initializing conversation...')),
      );
      return;
    }

    try {
      // Pick multiple images (up to 5)
      final List<XFile> pickedFiles = await _imagePicker.pickMultiImage(
        limit: 5,
        imageQuality: 70,
      );

      if (pickedFiles.isEmpty) return;

      print('📸 Picked ${pickedFiles.length} images');

      // Queue each image for upload with a shared group ID
      final baseTimestamp = DateTime.now().millisecondsSinceEpoch;
      final groupMessageId =
          'upload_${baseTimestamp}_${widget.teacherId.hashCode}';

      // Create pending messages for immediate display
      final List<Map<String, dynamic>> pendingMetadataList = [];

      for (int i = 0; i < pickedFiles.length; i++) {
        final xFile = pickedFiles[i];
        final file = File(xFile.path);

        if (!file.existsSync()) {
          print('⚠️ File does not exist: ${xFile.path}');
          continue;
        }

        final messageId = '${groupMessageId}_$i';

        // Create pending metadata
        final pendingMetadata = {
          'messageId': messageId,
          'r2Key': 'pending/$messageId',
          'publicUrl': '',
          'localPath': file.path,
          'thumbnail': file.path, // Use local path as thumbnail
          'fileSize': await file.length(),
          'mimeType': 'image/jpeg',
          'originalFileName': 'image_$i.jpg',
        };

        pendingMetadataList.add(pendingMetadata);

        // Queue upload in background service
        await BackgroundUploadService().queueUpload(
          file: file,
          conversationId: _conversationId!,
          senderId: widget.teacherId,
          senderRole: 'teacher',
          mediaType: 'message',
          messageId: messageId,
          groupId: groupMessageId, // Link all images together
        );
      }

      // Add pending messages to UI immediately
      if (pendingMetadataList.isNotEmpty && mounted) {
        setState(() {
          for (var metadata in pendingMetadataList) {
            final messageId = metadata['messageId'] as String;
            final pendingMessage = {
              'messageId': messageId,
              'senderRole': 'teacher',
              'text': '',
              'mediaMetadata': metadata,
              'createdAt': DateTime.now(),
              'isPending': true,
            };
            _pendingMessages.insert(0, pendingMessage);
            _pendingUploadProgress[messageId] = 0.0;
          }
        });
      }

      print(
        '✅ ${pickedFiles.length} images queued for upload with immediate preview',
      );
    } catch (e) {
      print('❌ Error in _pickAndSendImages: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to pick images: $e')));
      }
    }
  }

  Future<void> _pickAndSendPDF() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'txt',
          'csv',
          'rtf',
          'odt',
          'ods',
          'odp',
        ],
      );
      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      if (!file.existsSync()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document file not found')),
        );
        return;
      }

      if (_conversationId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Initializing conversation...')),
        );
        return;
      }

      // Create messageId for tracking
      final messageId =
          'upload_${DateTime.now().millisecondsSinceEpoch}_${widget.teacherId.hashCode}';
      final fileName = result.files.single.name;

      // Create pending message immediately
      final pendingMetadata = {
        'messageId': messageId,
        'r2Key': 'pending/$messageId',
        'publicUrl': '',
        'localPath': file.path,
        'thumbnail': '',
        'fileSize': await file.length(),
        'mimeType': 'application/${fileName.split('.').last}',
        'originalFileName': fileName,
      };

      final pendingMessage = {
        'messageId': messageId,
        'senderRole': 'teacher',
        'text': '',
        'mediaMetadata': pendingMetadata,
        'createdAt': DateTime.now(),
        'isPending': true,
      };

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        _pendingUploadProgress[messageId] = 0.0;
      });

      // Queue upload in background service
      await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: _conversationId!,
        senderId: widget.teacherId,
        senderRole: 'teacher',
        mediaType: 'message',
        messageId: messageId,
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to queue PDF: $e')));
    }
  }

  Future<void> _pickAndSendAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      if (!file.existsSync()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Audio file not found')));
        return;
      }

      if (_conversationId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Initializing conversation...')),
        );
        return;
      }

      // Create messageId for tracking
      final messageId =
          'upload_${DateTime.now().millisecondsSinceEpoch}_${widget.teacherId.hashCode}';
      final fileName = result.files.single.name;

      // Create pending message immediately
      final pendingMetadata = {
        'messageId': messageId,
        'r2Key': 'pending/$messageId',
        'publicUrl': '',
        'localPath': file.path,
        'thumbnail': '',
        'fileSize': await file.length(),
        'mimeType': 'audio/${fileName.split('.').last}',
        'originalFileName': fileName,
      };

      final pendingMessage = {
        'messageId': messageId,
        'senderRole': 'teacher',
        'text': '',
        'mediaMetadata': pendingMetadata,
        'createdAt': DateTime.now(),
        'isPending': true,
      };

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        _pendingUploadProgress[messageId] = 0.0;
      });

      // Queue upload in background service
      await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: _conversationId!,
        senderId: widget.teacherId,
        senderRole: 'teacher',
        mediaType: 'message',
        messageId: messageId,
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to queue audio: $e')));
    }
  }
}
