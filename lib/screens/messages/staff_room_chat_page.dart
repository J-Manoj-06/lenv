import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'dart:async';
import 'dart:io';
import '../../providers/auth_provider.dart';
import '../../services/cloudflare_r2_service.dart';
import '../../config/cloudflare_config.dart';
import '../../services/media_upload_service.dart';
import '../../services/local_cache_service.dart';
import '../../widgets/media_preview_card.dart';
import '../create_poll_screen.dart';
import '../../widgets/poll_message_widget.dart';
import '../../models/poll_model.dart';
import 'message_search_page.dart';
import '../../utils/message_scroll_highlight_mixin.dart';
// OFFLINE-FIRST IMPORTS
import '../../repositories/local_message_repository.dart';
import '../../services/firebase_message_sync_service.dart';
import 'offline_message_search_page.dart';

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

  @override
  void initState() {
    super.initState();
    _initMediaService();
    _initOfflineFirst();

    // Listen to scroll events to detect user scrolling
    scrollController.addListener(_onScroll);
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
    _messageController.dispose();
    disposeScrollController(); // Use mixin's disposal method
    _audioRecorder.dispose();
    _recordingTimer?.cancel();
    _recordingDuration.dispose();
    // Dispose all progress notifiers
    for (final notifier in _progressNotifiers.values) {
      notifier.dispose();
    }
    _progressNotifiers.clear();

    // Dispose selection notifiers
    _selectedMessages.dispose();
    _isSelectionMode.dispose();

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
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      await _uploadFile(File(pickedFile.path));
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

    // Create progress notifier
    final progressNotifier = ValueNotifier<double>(0.0);
    _progressNotifiers[messageId] = progressNotifier;

    setState(() {
      _pendingMessages.insert(0, pendingMessage);
      _uploadingMessageIds.add(messageId);
      _pendingUploadProgress[messageId] = 0.0;
      _localFilePaths[messageId] = file.path;
    });

    try {
      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: file,
        conversationId: widget.instituteId,
        senderId: currentUser.uid,
        senderRole: currentUser.role.toString(),
        mediaType: 'staff_room',
        onProgress: (progress) {
          // Convert progress from 0-100 to 0.0-1.0 for MediaPreviewCard
          final normalizedProgress = progress / 100.0;
          progressNotifier.value = normalizedProgress;
          _pendingUploadProgress[messageId] = normalizedProgress;
        },
      );

      // Create actual message with attachment
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
            'attachmentType': mediaMessage.fileType,
            'attachmentName': mediaMessage.fileName,
            'attachmentSize': fileSize,
            'thumbnailUrl': mediaMessage.thumbnailUrl,
          });

      // Don't remove pending message here - let StreamBuilder handle it automatically
      // This prevents flickering by avoiding double rebuild

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
      setState(() {
        _pendingMessages.removeWhere((m) => m['id'] == messageId);
        _uploadingMessageIds.remove(messageId);
        _pendingUploadProgress.remove(messageId);
        _localFilePaths.remove(messageId);
      });

      // Dispose and remove progress notifier
      _progressNotifiers[messageId]?.dispose();
      _progressNotifiers.remove(messageId);

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
                  label: 'Gallery',
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
                            // Toggle button to switch between Firebase and offline
                            if (_useOfflineFirst)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.green,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.offline_bolt,
                                      size: 14,
                                      color: Colors.green,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Offline',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            IconButton(
                              icon: Icon(Icons.search, color: textColor),
                              onPressed: () => _useOfflineFirst
                                  ? _openOfflineSearch(
                                      context,
                                      theme,
                                      primaryColor,
                                    )
                                  : _openSearch(context, theme, primaryColor),
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
      stream: FirebaseFirestore.instance
          .collection('staff_rooms')
          .doc(widget.instituteId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(300)
          .snapshots(),
      builder: (context, snapshot) {
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

        // Add pending messages first, but check if they have a Firestore version
        for (final pendingMsg in _pendingMessages) {
          final pendingId = pendingMsg['id'] as String;
          final pendingSenderId = pendingMsg['senderId'];
          final pendingTimestamp = pendingMsg['createdAt'] as int;

          // Check if this pending message now exists in Firestore
          final hasServerVersion = firestoreMessages.any((doc) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['isDeleted'] == true) return false;

            final serverSenderId = data['senderId'];
            final serverTimestamp = data['createdAt'];
            final serverTimestampMs = serverTimestamp is Timestamp
                ? serverTimestamp.millisecondsSinceEpoch
                : (serverTimestamp as int? ?? 0);

            // Match by sender and timestamp (within 30 seconds)
            final senderMatch = serverSenderId == pendingSenderId;
            final timeDiff = (serverTimestampMs - pendingTimestamp).abs();
            final timeMatch = timeDiff < 30000; // 30 seconds

            return senderMatch && timeMatch;
          });

          if (hasServerVersion) {
            // Mark for removal but don't remove yet
            pendingIdsToRemove.add(pendingId);
            // Save local path for sender to reuse
            final localPath = _localFilePaths[pendingId];
            if (localPath != null && localPath.isNotEmpty) {
              // Keep local path for a short time for display
            }
          } else {
            // Still uploading or not saved yet, keep in list
            allMessages.add(pendingMsg);
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

          data['id'] = doc.id;
          data['isPending'] = false;
          allMessages.add(data);
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
          itemBuilder: (context, index) {
            final message = allMessages[index];
            final messageId = message['id'] as String? ?? '';
            final isPending = message['isPending'] == true;

            final authProvider = Provider.of<AuthProvider>(
              context,
              listen: false,
            );
            final isMe = message['senderId'] == authProvider.currentUser?.uid;

            // Check if this message is highlighted
            final isHighlighted = highlightedMessageId == messageId;

            // Create stable key for all items (pending and non-pending)
            final itemKey = ValueKey(messageId);

            // Simplified container without heavy animations for pending messages
            if (isPending) {
              return ValueListenableBuilder<bool>(
                valueListenable: _isSelectionMode,
                builder: (context, isSelectionMode, _) {
                  return ValueListenableBuilder<Set<String>>(
                    valueListenable: _selectedMessages,
                    builder: (context, selectedMessages, _) {
                      return HighlightedMessageWrapper(
                        key: getMessageKey(messageId),
                        isHighlighted: isHighlighted,
                        child: _MessageBubble(
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
              );
            }

            // Full featured container with animations for non-pending messages
            return ValueListenableBuilder<bool>(
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

        // Collect media for deletion
        if (data?['attachmentUrl'] != null &&
            data!['attachmentUrl'].toString().contains(
              'r2.cloudflarestorage.com',
            )) {
          try {
            final url = data['attachmentUrl'] as String;
            final uri = Uri.parse(url);
            final key = uri.pathSegments.last;
            mediaToDelete.add(key);
          } catch (e) {
            // Ignore parsing errors
          }
        }

        // Add to batch
        batch.update(messageRef, {
          'isDeleted': true,
          'text': '',
          'attachmentUrl': null,
          'attachmentType': null,
          'attachmentName': null,
          'attachmentSize': null,
          'thumbnailUrl': null,
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

  void _deleteMediaFiles(List<String> keys) async {
    try {
      final r2Service = CloudflareR2Service(
        accountId: CloudflareConfig.accountId,
        bucketName: CloudflareConfig.bucketName,
        accessKeyId: CloudflareConfig.accessKeyId,
        secretAccessKey: CloudflareConfig.secretAccessKey,
        r2Domain: CloudflareConfig.r2Domain,
      );

      for (final key in keys) {
        try {
          await r2Service.deleteFile(key: key);
        } catch (e) {
          // Ignore individual file deletion errors
        }
      }
    } catch (e) {
      // Ignore media deletion errors
    }
  }
}

class _MessageBubble extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final senderName = message['senderName'] ?? 'Unknown';
    final senderRole = message['senderRole'] ?? '';
    final text = message['text'] ?? '';
    final createdAt = message['createdAt'];
    final timestamp = createdAt is Timestamp
        ? createdAt.millisecondsSinceEpoch
        : (createdAt as int? ?? 0);
    final attachmentUrl = message['attachmentUrl'] as String?;
    final attachmentType = message['attachmentType'] as String?;
    final attachmentName = message['attachmentName'] as String?;
    final attachmentSize = message['attachmentSize'] as int?;
    final thumbnailUrl = message['thumbnailUrl'] as String?;
    final isForwarded = message['isForwarded'] == true;
    final isPending = message['isPending'] == true;
    final messageId = message['id'] as String? ?? '';

    String timeStr = '';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    timeStr = DateFormat('HH:mm').format(date);

    final roleColor = senderRole == 'principal'
        ? primaryColor
        : const Color(0xFFF97316); // Orange for teachers

    final hasAttachment = attachmentUrl != null && attachmentUrl.isNotEmpty;
    final isPoll = message['type'] == 'poll';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          // Use Flexible for polls, Container with maxWidth for others
          isPoll
              ? Flexible(
                  child: Column(
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (!isMe) ...[
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
                          alignment: isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: PollMessageWidget(
                            poll: PollModel.fromMap(message, messageId),
                            chatId: staffRoomId,
                            chatType: 'staff_room',
                            isOwnMessage: isMe,
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
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (!isMe) ...[
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
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: hasAttachment && text.isEmpty ? 4 : 16,
                          vertical: hasAttachment && text.isEmpty ? 4 : 10,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? primaryColor
                              : theme.colorScheme.surfaceContainerHighest
                                    .withOpacity(0.7),
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
                            if (isForwarded) ...[
                              Row(
                                children: [
                                  Icon(
                                    Icons.forward,
                                    size: 14,
                                    color: isMe
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Forwarded',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                      color: isMe
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
                                  color: isMe
                                      ? Colors.white
                                      : theme.textTheme.bodyLarge?.color,
                                ),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: isMe
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
          if (selectionMode && isMe)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(
                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isSelected ? primaryColor : Colors.grey,
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
      localPath = localFilePaths[messageId];
      r2Key = 'pending/$messageId';
    } else {
      // Extract R2 key from URL
      final uri = Uri.tryParse(url ?? '');
      if (uri == null) return const SizedBox();
      r2Key = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    }

    final isUploading = uploadingMessageIds.contains(messageId);
    final progressNotifier = progressNotifiers[messageId];

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
            isMe: isMe,
            selectionMode: selectionMode,
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
      isMe: isMe,
      selectionMode: selectionMode,
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
