import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../models/media_message.dart';
import '../services/media_upload_service.dart';
import '../services/cloudflare_r2_service.dart';
import '../services/cloudflare_worker_upload_service.dart';
import '../services/local_cache_service.dart';
import '../config/cloudflare_config.dart';

/// Provider for managing chat with media support
/// Usage:
/// - Upload media
/// - Stream messages (text + media)
/// - Manage cache
/// - Handle unread counts
class MediaChatProvider extends ChangeNotifier {
  final String conversationId;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _imagePicker = ImagePicker();

  late MediaUploadService _mediaService;
  late CloudflareWorkerUploadService _workerUploadService;
  late LocalCacheService _cacheService;

  // State
  List<MediaMessage> _mediaMessages = [];
  final Map<String, int> _uploadProgress = {}; // mediaId -> progress%
  String? _currentError;
  bool _isLoadingMore = false;
  DocumentSnapshot? _lastDocumentSnapshot;

  MediaChatProvider({required this.conversationId}) {
    _initializeServices();
  }

  void _initializeServices() {
    _cacheService = LocalCacheService();

    final r2Service = CloudflareR2Service(
      accountId: CloudflareConfig.accountId,
      bucketName: CloudflareConfig.bucketName,
      accessKeyId: CloudflareConfig.accessKeyId,
      secretAccessKey: CloudflareConfig.secretAccessKey,
      r2Domain: CloudflareConfig.r2Domain,
    );

    _mediaService = MediaUploadService(
      r2Service: r2Service,
      firestore: _firestore,
      cacheService: _cacheService,
    );

    // Initialize Cloudflare Worker upload service (no Firebase dependency needed)
    _workerUploadService = CloudflareWorkerUploadService(
      workerUrl: 'https://whatsapp-media-worker.giridharannj.workers.dev',
      auth: _auth,
    );
  }

  // Getters
  List<MediaMessage> get mediaMessages => _mediaMessages;
  Map<String, int> get uploadProgress => _uploadProgress;
  String? get currentError => _currentError;
  bool get isLoadingMore => _isLoadingMore;

  /// Pick image from device
  Future<void> pickAndUploadImage() async {
    try {
      _currentError = null;
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );

      if (pickedFile == null) return;

      await _uploadMedia(File(pickedFile.path));
    } catch (e) {
      _setError('Failed to pick image: $e');
    }
  }

  /// Pick image from camera
  Future<void> captureAndUploadImage() async {
    try {
      _currentError = null;
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );

      if (pickedFile == null) return;

      await _uploadMedia(File(pickedFile.path));
    } catch (e) {
      _setError('Failed to capture image: $e');
    }
  }

  /// Pick PDF from device
  Future<void> pickAndUploadPdf() async {
    try {
      _currentError = null;
      // Note: Use file_picker package for file selection
      // This is a simplified example
      print('Implement file picker for PDF');
    } catch (e) {
      _setError('Failed to pick PDF: $e');
    }
  }

  /// Upload media to R2 + Firestore
  Future<void> _uploadMedia(File file) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Get user role from Firestore or provider
      final userRole = 'teacher'; // TODO: Get from auth provider

      final mediaId = DateTime.now().millisecondsSinceEpoch.toString();

      // Show progress
      _uploadProgress[mediaId] = 0;
      notifyListeners();

      // Upload with mediaType (permanent for messages/communities)
      final media = await _mediaService.uploadMedia(
        file: file,
        conversationId: conversationId,
        senderId: currentUser.uid,
        senderRole: userRole,
        mediaType: 'message', // Permanent storage for regular chat messages
        onProgress: (progress) {
          _uploadProgress[mediaId] = progress;
          notifyListeners();
        },
      );

      // Update list
      _mediaMessages.insert(0, media);
      _uploadProgress.remove(mediaId);
      _currentError = null;
      notifyListeners();

      print('✅ Media uploaded: ${media.fileName}');
    } catch (e) {
      _setError('Upload failed: $e');
      print('❌ Upload error: $e');
    }
  }

  /// Upload media via Cloud Function (NEW - Server-side approach)
  /// This method uploads to R2 through Firebase Cloud Function
  /// Benefits: No client-side R2 credentials, automatic folder organization
  Future<void> uploadMediaViaCloudFunction({
    required File file,
    required String schoolId,
    required String communityId,
    required String groupId,
    required String messageId,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      _currentError = null;
      _uploadProgress[messageId] = 0;
      notifyListeners();

      // Get file name
      final fileName = file.path.split('/').last;

      print('📤 Starting Cloudflare Worker upload');
      print('   File: $fileName');
      print('   Message ID: $messageId');

      // Upload via Cloudflare Worker (no Firebase dependency)
      final result = await _workerUploadService.uploadFile(
        file: file,
        fileName: fileName,
        schoolId: schoolId,
        communityId: communityId,
        groupId: groupId,
        messageId: messageId,
        onProgress: (progress) {
          _uploadProgress[messageId] = progress;
          notifyListeners();
        },
      );

      print('✅ Cloudflare Worker upload complete');
      print('   Public URL: ${result['publicUrl']}');

      // Create MediaMessage with the returned URL
      final media = MediaMessage(
        id: messageId,
        fileName: result['fileName'] as String,
        fileType: result['key']
            .toString()
            .split('.')
            .last, // Extract extension from key
        r2Url: result['publicUrl'] as String,
        fileSize: result['fileSize'] as int,
        thumbnailUrl: null,
        senderId: currentUser.uid,
        senderRole: 'teacher',
        conversationId: conversationId,
        createdAt: DateTime.now(),
        readByTeacher: false,
        readByParent: false,
        readByStudent: false,
      );

      // Update list
      _mediaMessages.insert(0, media);
      _uploadProgress.remove(messageId);
      notifyListeners();

      print('✅ Media message created and added to list');
    } catch (e) {
      _setError('Cloud Function upload failed: $e');
      _uploadProgress.remove(messageId);
      print('❌ Cloud Function upload error: $e');
      notifyListeners();
      rethrow;
    }
  }

  /// Stream media messages with pagination
  Stream<List<dynamic>> getUnifiedMessagesStream() {
    return _mediaService
        .getMediaStream(conversationId: conversationId, limit: 50)
        .asyncMap((mediaList) async {
          // Combine with text messages if needed
          // For now, just return media
          return mediaList;
        });
  }

  /// Load more media (pagination)
  Future<void> loadMoreMedia() async {
    if (_isLoadingMore) return;

    try {
      _isLoadingMore = true;
      notifyListeners();

      final moreMedia = await _mediaService.getMediaPaginated(
        conversationId: conversationId,
        limit: 20,
        startAfter: _lastDocumentSnapshot,
      );

      if (moreMedia.isNotEmpty) {
        _lastDocumentSnapshot = null; // Update with real last doc
        _mediaMessages.addAll(moreMedia);
      }

      _isLoadingMore = false;
      notifyListeners();
    } catch (e) {
      _setError('Failed to load more: $e');
    }
  }

  /// Mark media as read
  Future<void> markMediaAsRead(MediaMessage media) async {
    try {
      final userRole = 'teacher'; // TODO: Get from auth provider

      await _mediaService.markMediaAsRead(
        conversationId: conversationId,
        mediaId: media.id,
        userRole: userRole,
      );

      // Update local list
      final index = _mediaMessages.indexWhere((m) => m.id == media.id);
      if (index != -1) {
        final updatedMedia = media.copyWith(readByTeacher: true);
        _mediaMessages[index] = updatedMedia;
        notifyListeners();
      }
    } catch (e) {
      _setError('Failed to mark as read: $e');
    }
  }

  /// Delete media (soft delete)
  Future<void> deleteMedia(MediaMessage media) async {
    try {
      await _mediaService.deleteMedia(
        conversationId: conversationId,
        mediaId: media.id,
      );

      _mediaMessages.removeWhere((m) => m.id == media.id);
      _currentError = null;
      notifyListeners();
    } catch (e) {
      _setError('Failed to delete media: $e');
    }
  }

  /// Download media (future implementation)
  Future<void> downloadMedia(MediaMessage media) async {
    try {
      // TODO: Implement download using dio or path_provider
      print('Downloading: ${media.fileName}');
    } catch (e) {
      _setError('Failed to download: $e');
    }
  }

  /// Clear error message
  void clearError() {
    _currentError = null;
    notifyListeners();
  }

  /// Set error
  void _setError(String message) {
    _currentError = message;
    notifyListeners();
  }

  /// Clear upload progress for a media
  void clearUploadProgress(String mediaId) {
    _uploadProgress.remove(mediaId);
    notifyListeners();
  }

  /// Get cache statistics
  Future<Map<String, dynamic>> getCacheStats() async {
    return await _cacheService.getCacheStats();
  }

  /// Refresh cache from Firestore
  Future<void> refreshMedia() async {
    try {
      _mediaMessages.clear();
      _lastDocumentSnapshot = null;
      _currentError = null;
      notifyListeners();

      final messages = await _mediaService.getMediaPaginated(
        conversationId: conversationId,
        limit: 50,
      );

      _mediaMessages = messages;
      notifyListeners();
    } catch (e) {
      _setError('Failed to refresh: $e');
    }
  }

  @override
  void dispose() {
    _uploadProgress.clear();
    super.dispose();
  }
}

/// Example usage in a Chat Screen widget
class MediaChatExample extends StatefulWidget {
  final String conversationId;

  const MediaChatExample({super.key, required this.conversationId});

  @override
  State<MediaChatExample> createState() => _MediaChatExampleState();
}

class _MediaChatExampleState extends State<MediaChatExample> {
  late MediaChatProvider _provider;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _provider = MediaChatProvider(conversationId: widget.conversationId);

    _scrollController.addListener(() {
      if (_scrollController.position.pixels ==
          _scrollController.position.maxScrollExtent) {
        _provider.loadMoreMedia();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Media Chat'),
        backgroundColor: Color(0xFF128C7E),
      ),
      body: ListenableBuilder(
        listenable: _provider,
        builder: (context, child) {
          return Column(
            children: [
              // Error message
              if (_provider.currentError != null)
                Container(
                  padding: EdgeInsets.all(12),
                  color: Colors.red[100],
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _provider.currentError!,
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, size: 20),
                        onPressed: _provider.clearError,
                      ),
                    ],
                  ),
                ),

              // Upload progress indicators
              ..._provider.uploadProgress.entries.map((entry) {
                return Container(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(
                    value: entry.value / 100,
                    minHeight: 4,
                  ),
                );
              }),

              // Media list
              Expanded(
                child: StreamBuilder<List<dynamic>>(
                  stream: _provider.getUnifiedMessagesStream(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Center(child: CircularProgressIndicator());
                    }

                    final messages = snapshot.data!;
                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        if (message is MediaMessage) {
                          return Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: GestureDetector(
                              onLongPress: () {
                                _showMediaOptions(context, message);
                              },
                              child: Container(
                                alignment:
                                    message.senderId ==
                                        FirebaseAuth.instance.currentUser?.uid
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: Container(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width * 0.8,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        message.senderId ==
                                            FirebaseAuth
                                                .instance
                                                .currentUser
                                                ?.uid
                                        ? Color(0xFFDCF8C6)
                                        : Color(0xFFE8E8E8),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: EdgeInsets.all(8),
                                  child: _buildMediaContent(message),
                                ),
                              ),
                            ),
                          );
                        }
                        return SizedBox.shrink();
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
        ),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.photo, color: Color(0xFF128C7E)),
              onPressed: _provider.pickAndUploadImage,
            ),
            IconButton(
              icon: Icon(Icons.camera_alt, color: Color(0xFF128C7E)),
              onPressed: _provider.captureAndUploadImage,
            ),
            IconButton(
              icon: Icon(Icons.description, color: Color(0xFF128C7E)),
              onPressed: _provider.pickAndUploadPdf,
            ),
            Spacer(),
            IconButton(
              icon: Icon(Icons.refresh, color: Color(0xFF128C7E)),
              onPressed: _provider.refreshMedia,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaContent(MediaMessage media) {
    if (media.isImage) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              media.r2Url,
              width: 200,
              height: 200,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 200,
                  height: 200,
                  color: Colors.grey,
                  child: Icon(Icons.broken_image),
                );
              },
            ),
          ),
          SizedBox(height: 4),
          Text(
            media.fileName,
            style: TextStyle(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    } else if (media.isPdf) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.picture_as_pdf, color: Colors.red),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  media.fileName,
                  style: TextStyle(fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  media.formattedSize,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.download, size: 20),
            onPressed: () => _provider.downloadMedia(media),
          ),
        ],
      );
    }

    return SizedBox.shrink();
  }

  void _showMediaOptions(BuildContext context, MediaMessage media) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.download),
                title: Text('Download'),
                onTap: () {
                  _provider.downloadMedia(media);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.share),
                title: Text('Share'),
                onTap: () {
                  // Implement share
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete, color: Colors.red),
                title: Text('Delete'),
                onTap: () {
                  _provider.deleteMedia(media);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
