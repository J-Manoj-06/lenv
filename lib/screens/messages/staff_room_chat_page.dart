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
import '../../models/staff_room_message.dart';

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

class _StaffRoomChatPageState extends State<StaffRoomChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final MediaUploadService _mediaUploadService;
  bool _isUploading = false;
  double _uploadProgress = 0;
  String? _highlightMessageId;
  Timer? _highlightResetTimer;
  final Map<String, GlobalKey> _messageKeys = {};
  List<QueryDocumentSnapshot> _currentMessages =
      []; // Store messages for index lookup

  // Recording variables
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordingPath;
  final ValueNotifier<int> _recordingDuration = ValueNotifier<int>(0);
  Timer? _recordingTimer;

  // Pending uploads tracking (like community chat)
  final List<Map<String, dynamic>> _pendingMessages = [];
  final Set<String> _uploadingMessageIds = {};
  final Map<String, double> _pendingUploadProgress = {};
  final Map<String, String> _localFilePaths = {};
  final Map<String, ValueNotifier<double>> _progressNotifiers = {};
  DateTime? _lastProgressUpdate;

  @override
  void initState() {
    super.initState();
    _initMediaService();
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
    _scrollController.dispose();
    _audioRecorder.dispose();
    _recordingTimer?.cancel();
    _highlightResetTimer?.cancel();
    _recordingDuration.dispose();
    _messageKeys.clear();
    // Dispose all progress notifiers
    for (final notifier in _progressNotifiers.values) {
      notifier.dispose();
    }
    _progressNotifiers.clear();
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
      // Scroll to bottom after sending
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
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
    if (lower.endsWith('.pdf'))
      mimeType = 'application/pdf';
    else if (lower.endsWith('.jpg') || lower.endsWith('.jpeg'))
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
          // Update ValueNotifier instead of setState to avoid rebuilding entire widget
          progressNotifier.value = progress.toDouble();
          _pendingUploadProgress[messageId] = progress.toDouble();
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

      // Remove pending message
      setState(() {
        _pendingMessages.removeWhere((m) => m['id'] == messageId);
        _uploadingMessageIds.remove(messageId);
        _pendingUploadProgress.remove(messageId);
        _localFilePaths.remove(messageId);
      });

      // Dispose and remove progress notifier
      _progressNotifiers[messageId]?.dispose();
      _progressNotifiers.remove(messageId);

      // Scroll to bottom
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send file: $e')));
      }
    }
  }

  void _showAttachmentPicker() {
    final primaryColor = widget.isTeacher
        ? const Color(0xFFF97316)
        : const Color(0xFF146D7A);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
                    Navigator.pop(context);
                    _pickImage();
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  color: primaryColor,
                  onTap: () {
                    Navigator.pop(context);
                    _pickCamera();
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.picture_as_pdf,
                  label: 'Document',
                  color: primaryColor,
                  onTap: () {
                    Navigator.pop(context);
                    _pickDocument();
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.audiotrack,
                  label: 'Audio',
                  color: primaryColor,
                  onTap: () {
                    Navigator.pop(context);
                    _pickAudio();
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
            setState(() => _isUploading = true);

            // Get audio file size
            final fileSize = await file.length();

            // Upload audio using MediaUploadService
            final mediaMessage = await _mediaUploadService.uploadMedia(
              file: file,
              conversationId: widget.instituteId,
              senderId: currentUser.uid,
              senderRole: currentUser.role.toString().split('.').last,
              mediaType: 'message',
              onProgress: (progress) {
                setState(() => _uploadProgress = progress.toDouble());
              },
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

            setState(() {
              _isUploading = false;
              _isRecording = false;
              _recordingPath = null;
              _recordingDuration.value = 0;
              _uploadProgress = 0;
            });

            // Scroll to bottom
            Future.delayed(const Duration(milliseconds: 100), () {
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            });

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
            setState(() => _isUploading = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to send audio: $e')),
              );
            }
          }
        }
      }

      setState(() {
        _isRecording = false;
        _recordingPath = null;
        _recordingDuration.value = 0;
      });
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
        leading: IconButton(
          icon: Icon(Icons.chevron_left, color: textColor, size: 32),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.isTeacher ? 'Teacher Group Chat' : 'Staff Room',
          style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: textColor),
            onPressed: () => _openSearch(context, theme, primaryColor),
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

  void _openSearch(BuildContext context, ThemeData theme, Color primaryColor) {
    Navigator.of(context)
        .push<StaffRoomMessage?>(
          MaterialPageRoute(
            builder: (_) => SearchStaffRoomScreen(
              instituteId: widget.instituteId,
              primaryColor: primaryColor,
              theme: theme,
            ),
          ),
        )
        .then((selectedMessage) {
          if (selectedMessage != null) {
            _locateMessageInList(selectedMessage);
          }
        });
  }

  Future<void> _locateMessageInList(StaffRoomMessage message) async {
    final targetId = message.id;
    if (targetId.isEmpty) return;

    // Find the message index in the current list
    final messageIndex = _currentMessages.indexWhere(
      (doc) => doc.id == targetId,
    );

    if (messageIndex == -1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message not found in current view'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Set highlight
    setState(() {
      _highlightMessageId = targetId;
    });

    // Wait for rebuild
    await Future.delayed(const Duration(milliseconds: 100));

    if (!_scrollController.hasClients || !mounted) return;

    // Calculate approximate scroll position
    // Estimate 100 pixels per message (adjust as needed)
    const estimatedItemHeight = 100.0;
    final scrollPosition = messageIndex * estimatedItemHeight;

    // Scroll to approximate position
    await _scrollController.animateTo(
      scrollPosition.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );

    // Clear highlight after delay
    _highlightResetTimer?.cancel();
    _highlightResetTimer = Timer(const Duration(milliseconds: 2000), () {
      if (mounted && _highlightMessageId == targetId) {
        setState(() => _highlightMessageId = null);
      }
    });
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

        // Add pending messages first
        allMessages.addAll(_pendingMessages);

        // Add Firestore messages
        for (final doc in firestoreMessages) {
          final data = doc.data() as Map<String, dynamic>;
          data['id'] = doc.id;
          data['isPending'] = false;
          allMessages.add(data);
        }

        // Sort by timestamp
        allMessages.sort((a, b) {
          final aTime = a['createdAt'] as int? ?? 0;
          final bTime = b['createdAt'] as int? ?? 0;
          return bTime.compareTo(aTime);
        });

        // Store messages for index-based scrolling
        _currentMessages = firestoreMessages;

        // Track which messages are currently visible - use doc IDs directly
        final currentMessageIds = firestoreMessages
            .map((doc) => doc.id)
            .toSet();

        _messageKeys.removeWhere((key, _) => !currentMessageIds.contains(key));

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

        return ListView.builder(
          controller: _scrollController,
          reverse: true,
          padding: const EdgeInsets.all(16),
          itemCount: allMessages.length,
          itemBuilder: (context, index) {
            final message = allMessages[index];
            final messageId = message['id'] as String? ?? '';
            final isPending = message['isPending'] == true;

            final authProvider = Provider.of<AuthProvider>(
              context,
              listen: false,
            );
            final isMe = message['senderId'] == authProvider.currentUser?.uid;
            final isHighlighted =
                messageId == _highlightMessageId && !isPending;

            // Create stable key for all items (pending and non-pending)
            final itemKey = ValueKey(messageId);

            final isDark = theme.brightness == Brightness.dark;
            final highlightColor = isDark
                ? primaryColor.withOpacity(0.16)
                : primaryColor.withOpacity(0.12);

            // For non-pending messages, create GlobalKey for scroll detection
            if (!isPending && !_messageKeys.containsKey(messageId)) {
              _messageKeys[messageId] = GlobalKey();
            }

            // Simplified container without heavy animations for pending messages
            if (isPending) {
              return Container(
                key: itemKey,
                child: _MessageBubble(
                  key: itemKey,
                  message: message,
                  isMe: isMe,
                  primaryColor: primaryColor,
                  uploadingMessageIds: _uploadingMessageIds,
                  pendingUploadProgress: _pendingUploadProgress,
                  localFilePaths: _localFilePaths,
                  progressNotifiers: _progressNotifiers,
                ),
              );
            }

            // Full featured container with animations for non-pending messages
            return Container(
              key: _messageKeys[messageId],
              child: isHighlighted
                  ? AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        color: highlightColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _MessageBubble(
                        message: message,
                        isMe: isMe,
                        primaryColor: primaryColor,
                        uploadingMessageIds: _uploadingMessageIds,
                        pendingUploadProgress: _pendingUploadProgress,
                        localFilePaths: _localFilePaths,
                        progressNotifiers: _progressNotifiers,
                      ),
                    )
                  : _MessageBubble(
                      message: message,
                      isMe: isMe,
                      primaryColor: primaryColor,
                      uploadingMessageIds: _uploadingMessageIds,
                      pendingUploadProgress: _pendingUploadProgress,
                      localFilePaths: _localFilePaths,
                      progressNotifiers: _progressNotifiers,
                    ),
            );
          },
        );
      },
    );
  }

  Widget _buildMessageInput(ThemeData theme, Color primaryColor) {
    final isDark = theme.brightness == Brightness.dark;

    // Recording UI
    if (_isRecording) {
      return ValueListenableBuilder<int>(
        valueListenable: _recordingDuration,
        builder: (context, duration, _) {
          final minutes = duration ~/ 60;
          final seconds = duration % 60;
          final timeStr =
              '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (_isUploading)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(
                  value: _uploadProgress / 100,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                ),
              ),
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.attach_file, color: primaryColor),
                  onPressed: _isUploading ? null : _showAttachmentPicker,
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest
                          .withOpacity(0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    maxLines: null,
                    enabled: !_isUploading,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _sendMessage(),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                // Show send button when text is typed, otherwise mic button
                GestureDetector(
                  onTap: _isUploading
                      ? null
                      : _messageController.text.trim().isNotEmpty
                      ? _sendMessage
                      : () async {
                          try {
                            if (!_isRecording) {
                              // Start recording
                              final permission = await _audioRecorder
                                  .hasPermission();
                              if (!permission) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Microphone permission required',
                                      ),
                                    ),
                                  );
                                }
                                return;
                              }

                              final directory = Directory.systemTemp;
                              final timestamp =
                                  DateTime.now().millisecondsSinceEpoch;
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

                              setState(() {
                                _isRecording = true;
                                _recordingPath = recordingPath;
                                _recordingDuration.value = 0;
                              });

                              _recordingTimer = Timer.periodic(
                                const Duration(seconds: 1),
                                (_) {
                                  _recordingDuration.value++;
                                },
                              );

                              print('🎤 Recording started: $recordingPath');
                            }
                          } catch (e) {
                            print('❌ Error starting recording: $e');
                          }
                        },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _isUploading ? Colors.grey : primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _messageController.text.trim().isNotEmpty
                          ? Icons.send
                          : Icons.mic,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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

  const _MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.primaryColor,
    required this.uploadingMessageIds,
    required this.pendingUploadProgress,
    required this.localFilePaths,
    required this.progressNotifiers,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final senderName = message['senderName'] ?? 'Unknown';
    final senderRole = message['senderRole'] ?? '';
    final text = message['text'] ?? '';
    final timestamp = message['createdAt'] as int?;
    final attachmentUrl = message['attachmentUrl'] as String?;
    final attachmentType = message['attachmentType'] as String?;
    final attachmentName = message['attachmentName'] as String?;
    final attachmentSize = message['attachmentSize'] as int?;
    final thumbnailUrl = message['thumbnailUrl'] as String?;
    final isForwarded = message['isForwarded'] == true;
    final isPending = message['isPending'] == true;
    final messageId = message['id'] as String? ?? '';

    String timeStr = '';
    if (timestamp != null) {
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      timeStr = DateFormat('HH:mm').format(date);
    }

    final roleColor = senderRole == 'principal'
        ? primaryColor
        : const Color(0xFFF97316); // Orange for teachers

    final hasAttachment = attachmentUrl != null && attachmentUrl.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
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
                        senderRole == 'principal' ? 'Principal' : 'Teacher',
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
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(
                            0.8,
                          ),
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
                    : theme.colorScheme.surfaceContainerHighest.withOpacity(
                        0.7,
                      ),
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
                          color: isMe ? Colors.white70 : Colors.black54,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Forwarded',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: isMe ? Colors.white70 : Colors.black54,
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
                          : theme.textTheme.bodyMedium?.color?.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
            selectionMode: false,
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
      selectionMode: false,
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

class SearchStaffRoomScreen extends StatefulWidget {
  final String instituteId;
  final Color primaryColor;
  final ThemeData theme;

  const SearchStaffRoomScreen({
    super.key,
    required this.instituteId,
    required this.primaryColor,
    required this.theme,
  });

  @override
  State<SearchStaffRoomScreen> createState() => _SearchStaffRoomScreenState();
}

class _SearchStaffRoomScreenState extends State<SearchStaffRoomScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<StaffRoomMessage> _searchResults = [];
  bool _isLoading = false;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searchQuery = '';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _searchQuery = query.toLowerCase();
    });

    try {
      // Get messages and search through them
      final messagesSnapshot = await FirebaseFirestore.instance
          .collection('staff_rooms')
          .doc(widget.instituteId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(500) // Search in recent messages
          .get();

      final results = <StaffRoomMessage>[];

      for (final doc in messagesSnapshot.docs) {
        try {
          final message = StaffRoomMessage.fromFirestore(doc.data(), doc.id);

          // Search in message text
          if (message.text.toLowerCase().contains(_searchQuery)) {
            results.add(message);
            if (results.length >= 25) break;
            continue;
          }

          // Search in sender name
          if (message.senderName.toLowerCase().contains(_searchQuery)) {
            results.add(message);
            if (results.length >= 25) break;
          }

          // Search in PDF file names
          if (message.mediaMetadata != null) {
            final fileName =
                message.mediaMetadata?.originalFileName?.toLowerCase() ?? '';
            if (fileName.contains(_searchQuery)) {
              results.add(message);
              if (results.length >= 25) break;
            }
          }
        } catch (e) {
          continue;
        }
      }

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final hintColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: theme.iconTheme.color,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Search Messages',
            style: TextStyle(
              color: theme.textTheme.bodyLarge?.color,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0F1419)
                    : theme.colorScheme.surfaceContainerHighest.withOpacity(
                        0.8,
                      ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: widget.primaryColor.withOpacity(0.15),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.primaryColor.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _performSearch,
                      autofocus: true,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search staff room messages...',
                        hintStyle: TextStyle(
                          color: hintColor?.withOpacity(0.7),
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: IconButton(
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: hintColor?.withOpacity(0.6),
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  splashRadius: 16,
                                  onPressed: () {
                                    _searchController.clear();
                                    _performSearch('');
                                  },
                                ),
                              )
                            : null,
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) =>
                          _performSearch(_searchController.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: _buildSearchResultsList(),
    );
  }

  Widget _buildSearchResultsList() {
    if (_searchQuery.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.primaryColor.withOpacity(0.1),
              ),
              child: Icon(
                Icons.search_rounded,
                size: 50,
                color: widget.primaryColor.withOpacity(0.3),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Search Messages',
              style: TextStyle(
                color: widget.theme.textTheme.bodyLarge?.color,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Find messages from staff members',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: widget.theme.textTheme.bodyMedium?.color?.withOpacity(
                    0.6,
                  ),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: widget.primaryColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.primaryColor.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: Text(
                'Type to search messages',
                style: TextStyle(
                  color: widget.primaryColor.withOpacity(0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: widget.primaryColor),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withOpacity(0.1),
              ),
              child: Icon(
                Icons.search_off_rounded,
                size: 40,
                color: Colors.red.withOpacity(0.3),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No matches found',
              style: TextStyle(
                color: widget.theme.textTheme.bodyLarge?.color,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try searching with different keywords',
              style: TextStyle(
                color: widget.theme.textTheme.bodyMedium?.color?.withOpacity(
                  0.6,
                ),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final message = _searchResults[index];
        final senderName = message.senderName;
        final text = message.text;
        final timestamp = message.createdAt;

        String timeStr = '';
        final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
        timeStr = DateFormat('HH:mm').format(date);

        // Determine display text and icon
        String displayText = text;
        IconData icon = Icons.chat_bubble_outline;

        if (text.isEmpty && message.mediaMetadata != null) {
          displayText =
              message.mediaMetadata?.originalFileName ?? 'Media message';
          final mime = message.mediaMetadata?.mimeType ?? '';
          if (mime == 'application/pdf') {
            icon = Icons.picture_as_pdf_outlined;
          } else if (mime.startsWith('audio/')) {
            icon = Icons.audiotrack;
          } else if (mime.startsWith('image/')) {
            icon = Icons.image_outlined;
          }
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.pop(context, message),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.theme.brightness == Brightness.dark
                        ? Colors.white.withOpacity(0.05)
                        : widget.theme.dividerColor.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: widget.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: widget.primaryColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayText.isNotEmpty
                                ? displayText
                                : 'Media message',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.theme.textTheme.bodyLarge?.color,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$senderName • $timeStr',
                            style: TextStyle(
                              color: widget.theme.textTheme.bodySmall?.color
                                  ?.withOpacity(0.6),
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
