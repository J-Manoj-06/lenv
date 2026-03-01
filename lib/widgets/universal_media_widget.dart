import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:just_audio/just_audio.dart';
import '../models/cached_media_message.dart';
import '../services/media_cache_service.dart';
import 'package:http/http.dart' as http;

/// Universal Media Widget Component
/// Handles display and interaction for all media types: image, audio, pdf, documents
/// Implements smart caching: check local first, show download button if not available
class UniversalMediaWidget extends StatefulWidget {
  final CachedMediaMessage message;
  final bool isMe;
  final Function(CachedMediaMessage)? onMediaUpdated;
  final double maxWidth;

  const UniversalMediaWidget({
    super.key,
    required this.message,
    this.isMe = false,
    this.onMediaUpdated,
    this.maxWidth = 250,
  });

  @override
  State<UniversalMediaWidget> createState() => _UniversalMediaWidgetState();
}

class _UniversalMediaWidgetState extends State<UniversalMediaWidget> {
  final MediaCacheService _cacheService = MediaCacheService();

  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _errorMessage;
  bool _isDownloaded = false;
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _checkLocalAvailability();
  }

  /// STEP 3: Check if media exists locally when widget initializes
  Future<void> _checkLocalAvailability() async {
    try {
      // Generate expected local path
      final mediaType = _getMediaType();
      final extension = _getFileExtension();

      final expectedPath = await _cacheService.getLocalFilePath(
        messageId: widget.message.messageId,
        mediaType: mediaType,
        extension: extension,
      );

      // Check if file exists
      final exists = await _cacheService.checkIfMediaExists(expectedPath);

      if (mounted) {
        setState(() {
          _isDownloaded = exists;
          _localPath = exists ? expectedPath : null;
        });

        // Update parent if callback provided
        if (exists && widget.onMediaUpdated != null) {
          widget.onMediaUpdated!(
            widget.message.copyWith(
              isDownloaded: true,
              localPath: expectedPath,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error checking local availability: $e');
    }
  }

  MediaType _getMediaType() {
    switch (widget.message.mediaType) {
      case MediaTypeCategory.image:
        return MediaType.image;
      case MediaTypeCategory.audio:
        return MediaType.audio;
      case MediaTypeCategory.pdf:
        return MediaType.pdf;
      case MediaTypeCategory.document:
        return MediaType.document;
    }
  }

  String _getFileExtension() {
    if (widget.message.fileName.contains('.')) {
      return '.${widget.message.fileName.split('.').last}';
    }

    // Fallback based on media type
    switch (widget.message.mediaType) {
      case MediaTypeCategory.image:
        return '.jpg';
      case MediaTypeCategory.audio:
        return '.mp3';
      case MediaTypeCategory.pdf:
        return '.pdf';
      case MediaTypeCategory.document:
        return '.dat';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    // STEP 4: Show appropriate UI based on download status
    if (_isDownloaded && _localPath != null) {
      return _buildDownloadedView();
    } else {
      return _buildNotDownloadedView();
    }
  }

  /// Build view when media is downloaded locally
  Widget _buildDownloadedView() {
    switch (widget.message.mediaType) {
      case MediaTypeCategory.image:
        return _buildImageView();
      case MediaTypeCategory.audio:
        return _buildAudioView();
      case MediaTypeCategory.pdf:
      case MediaTypeCategory.document:
        return _buildDocumentView();
    }
  }

  /// Build view when media is NOT downloaded
  Widget _buildNotDownloadedView() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.isMe ? Colors.blue[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(_getMediaIcon(), size: 32, color: Colors.grey[600]),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.message.fileName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.message.formattedSize,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isDownloading) ...[
            LinearProgressIndicator(
              value: _downloadProgress,
              backgroundColor: Colors.grey[300],
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
            const SizedBox(height: 8),
            Text(
              'Downloading ${(_downloadProgress * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ] else if (_errorMessage != null) ...[
            Text(
              _errorMessage!,
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _downloadMedia,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry Download'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 40),
              ),
            ),
          ] else ...[
            ElevatedButton.icon(
              onPressed: _downloadMedia,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Download'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 40),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Build image view (downloaded)
  Widget _buildImageView() {
    return GestureDetector(
      onTap: () => _openMedia(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(_localPath!),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildErrorView('Failed to load image');
          },
        ),
      ),
    );
  }

  /// Build audio view (downloaded)
  Widget _buildAudioView() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.isMe ? Colors.blue[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _playAudio(),
            icon: const Icon(Icons.play_circle_filled),
            iconSize: 40,
            color: Colors.blue,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.message.fileName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.message.formattedSize,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build document/PDF view (downloaded)
  Widget _buildDocumentView() {
    return GestureDetector(
      onTap: () => _openMedia(),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: widget.isMe ? Colors.blue[50] : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(_getMediaIcon(), size: 32, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.message.fileName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.message.formattedSize,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const Icon(Icons.open_in_new, color: Colors.blue),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  IconData _getMediaIcon() {
    switch (widget.message.mediaType) {
      case MediaTypeCategory.image:
        return Icons.image;
      case MediaTypeCategory.audio:
        return Icons.audiotrack;
      case MediaTypeCategory.pdf:
        return Icons.picture_as_pdf;
      case MediaTypeCategory.document:
        return Icons.description;
    }
  }

  /// STEP 5: Download media from cloud
  Future<void> _downloadMedia() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _errorMessage = null;
    });

    try {
      // Download from cloud URL
      final response = await http.get(Uri.parse(widget.message.cloudUrl));

      if (response.statusCode == 200) {
        // Save to local storage
        final mediaType = _getMediaType();
        final extension = _getFileExtension();

        final localPath = await _cacheService.saveMediaFile(
          messageId: widget.message.messageId,
          mediaType: mediaType,
          fileBytes: response.bodyBytes,
          extension: extension,
        );

        if (mounted) {
          setState(() {
            _isDownloading = false;
            _isDownloaded = true;
            _localPath = localPath;
            _downloadProgress = 1.0;
          });

          // Update parent
          if (widget.onMediaUpdated != null) {
            widget.onMediaUpdated!(
              widget.message.copyWith(
                isDownloaded: true,
                localPath: localPath,
                downloadedAt: DateTime.now(),
              ),
            );
          }

          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Download complete'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        throw Exception('Failed to download: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Download failed: ${e.toString()}';
        });
      }
    }
  }

  /// Open media using appropriate app
  Future<void> _openMedia() async {
    if (_localPath == null) return;

    try {
      final result = await OpenFilex.open(_localPath!);

      if (result.type != ResultType.done) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(result.message)));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error opening file: $e')));
      }
    }
  }

  /// Play audio file
  Future<void> _playAudio() async {
    if (_localPath == null) return;

    try {
      final player = AudioPlayer();
      await player.setFilePath(_localPath!);
      await player.play();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error playing audio: $e')));
      }
    }
  }
}
