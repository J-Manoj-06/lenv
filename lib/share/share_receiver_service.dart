import 'dart:async';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'incoming_share_data.dart';

/// Service to receive and handle shared content from other apps
class ShareReceiverService {
  static final ShareReceiverService _instance =
      ShareReceiverService._internal();
  factory ShareReceiverService() => _instance;
  ShareReceiverService._internal();

  final _shareDataController = StreamController<IncomingShareData?>.broadcast();
  Stream<IncomingShareData?> get shareDataStream => _shareDataController.stream;

  IncomingShareData? _currentShareData;
  StreamSubscription? _mediaStreamSubscription;
  StreamSubscription? _textStreamSubscription;
  final _receiveSharingIntent = ReceiveSharingIntent.instance;

  /// Initialize the service and start listening for shared content
  Future<void> initialize() async {
    // Listen for shared media (images, files, audio) while app is running
    _mediaStreamSubscription = _receiveSharingIntent.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          final shareData = _processSharedMedia(value);
          _currentShareData = shareData;
          _shareDataController.add(shareData);
        }
      },
      onError: (error) {
        print('❌ Error receiving shared media: $error');
      },
    );

    // Check for initial shared media (when app was closed)
    final initialMedia = await _receiveSharingIntent.getInitialMedia();
    if (initialMedia.isNotEmpty) {
      final shareData = _processSharedMedia(initialMedia);
      _currentShareData = shareData;
      _shareDataController.add(shareData);
    }
  }

  /// Process shared media files and determine content type
  IncomingShareData _processSharedMedia(List<SharedMediaFile> mediaFiles) {
    final files = mediaFiles.map((m) => m.path).toList();
    final mimeTypes = mediaFiles.map((m) => m.type.name).toList();

    // Determine content type based on mime types
    ShareContentType type = ShareContentType.file;

    if (mediaFiles.length == 1) {
      final mimeType = mediaFiles.first.type;
      if (mimeType == SharedMediaType.image) {
        type = ShareContentType.image;
      } else if (mimeType == SharedMediaType.video) {
        // Not supported - treat as file
        type = ShareContentType.file;
      } else if (mimeType == SharedMediaType.file) {
        // Check if it's audio or PDF
        final path = mediaFiles.first.path.toLowerCase();
        if (path.endsWith('.mp3') ||
            path.endsWith('.m4a') ||
            path.endsWith('.wav') ||
            path.endsWith('.aac')) {
          type = ShareContentType.audio;
        } else {
          type = ShareContentType.file;
        }
      }
    } else {
      // Multiple files
      final hasImages = mediaFiles.any((m) => m.type == SharedMediaType.image);
      final hasAudio = mediaFiles.any((m) {
        final path = m.path.toLowerCase();
        return path.endsWith('.mp3') ||
            path.endsWith('.m4a') ||
            path.endsWith('.wav') ||
            path.endsWith('.aac');
      });

      if (hasImages && !hasAudio) {
        type = ShareContentType.image;
      } else if (hasAudio && !hasImages) {
        type = ShareContentType.audio;
      } else {
        type = ShareContentType.mixed;
      }
    }

    return IncomingShareData(type: type, files: files, mimeTypes: mimeTypes);
  }

  /// Get current share data without clearing it
  IncomingShareData? getCurrentShareData() {
    return _currentShareData;
  }

  /// Clear current share data after it's been processed
  void clearShareData() {
    _currentShareData = null;
    _shareDataController.add(null);

    // Reset the intent to prevent re-processing
    ReceiveSharingIntent.instance.reset();
  }

  /// Dispose the service and clean up streams
  void dispose() {
    _mediaStreamSubscription?.cancel();
    _textStreamSubscription?.cancel();
    _shareDataController.close();
  }
}
