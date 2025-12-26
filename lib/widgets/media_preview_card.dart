import 'package:flutter/material.dart';
import '../services/media_repository.dart';
import '../screens/pdf_viewer_screen.dart';
import '../screens/audio_player_screen.dart';
import 'package:photo_view/photo_view.dart';
import 'dart:ui';
import 'dart:convert';
import 'dart:io';

/// Generic media preview card for chat messages
/// Shows a preview with download/open buttons based on download status
///
/// This widget is the CORE of the optimized media system:
/// - NO auto-download when message arrives
/// - Shows preview card with file info
/// - "Download" button if not downloaded
/// - "Open" button if already downloaded
/// - Progress indicator during download
/// - Checks local storage before any network request
class MediaPreviewCard extends StatefulWidget {
  final String r2Key; // e.g., "media/1234567/file.pdf"
  final String fileName;
  final String mimeType;
  final int fileSize;
  final String? thumbnailBase64; // For images
  final String? localPath; // Already saved path (for WhatsApp uploads)
  final bool isMe;
  // Uploading state (for optimistic pending messages)
  final bool uploading;
  final double? uploadProgress; // 0.0 - 1.0

  const MediaPreviewCard({
    super.key,
    required this.r2Key,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    this.thumbnailBase64,
    this.localPath,
    this.isMe = false,
    this.uploading = false,
    this.uploadProgress,
  });

  @override
  State<MediaPreviewCard> createState() => _MediaPreviewCardState();
}

class _MediaPreviewCardState extends State<MediaPreviewCard> {
  final MediaRepository _repository = MediaRepository();
  bool _isDownloaded = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _checkDownloadStatus();
  }

  Future<void> _checkDownloadStatus() async {
    // If localPath provided (WhatsApp upload), use it directly
    if (widget.localPath != null && widget.localPath!.isNotEmpty) {
      final file = File(widget.localPath!);
      
      // Validate that the file extension matches the media type
      final filePath = widget.localPath!.toLowerCase();
      final isAudioFile = filePath.endsWith('.m4a') || 
                          filePath.endsWith('.mp3') || 
                          filePath.endsWith('.aac') ||
                          filePath.endsWith('.wav');
      
      // If this is supposed to be an image but localPath points to audio, ignore it
      if (_isImage && isAudioFile) {
        print('⚠️ Skipping invalid localPath: audio file for image type: ${widget.localPath}');
        if (mounted) {
          setState(() {
            _isDownloaded = false;
            _localPath = null;
          });
        }
        return;
      }
      
      final exists = await file.exists();

      print('📋 Using provided localPath: ${widget.localPath}');
      print('   File exists: $exists');

      if (mounted) {
        setState(() {
          _isDownloaded = exists;
          _localPath = exists ? widget.localPath : null;
        });
      }
      return;
    }

    // Otherwise check repository
    final downloaded = await _repository.isDownloaded(widget.r2Key);
    final path = await _repository.getLocalFilePath(widget.r2Key);

    print('📋 Check status for: ${widget.r2Key}');
    print('   Downloaded: $downloaded');
    print('   Local path: $path');
    print(
      '   File size: ${widget.fileSize} bytes (${_formatSize(widget.fileSize)})',
    );

    if (mounted) {
      setState(() {
        _isDownloaded = downloaded;
        _localPath = path;
      });
    }

    // If sender viewing their own media and it isn't cached, auto-download silently
    if (widget.isMe && !_isDownloaded && !_isDownloading) {
      _download();
    }
  }

  Future<void> _download() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    final result = await _repository.downloadMedia(
      r2Key: widget.r2Key,
      fileName: widget.fileName,
      mimeType: widget.mimeType,
      thumbnailBase64: widget.thumbnailBase64,
      onProgress: (progress) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isDownloading = false;
      });

      if (result.success) {
        setState(() {
          _isDownloaded = true;
          _localPath = result.localPath;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Downloaded successfully')),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ ${result.message}')));
      }
    }
  }

  void _open() {
    if (_localPath == null) return;

    if (_isPdf) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              PDFViewerScreen(path: _localPath!, title: widget.fileName),
        ),
      );
    } else if (_isAudio) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AudioPlayerScreen(
            audioUrl: _localPath!,
            fileName: widget.fileName,
          ),
        ),
      );
    } else if (_isImage) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _FullImageViewer(
            imagePath: _localPath!,
            fileName: widget.fileName,
          ),
        ),
      );
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'Delete from device?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'This will free up ${_formatSize(widget.fileSize)} of storage. You can re-download it later.',
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
      ),
    );

    if (confirm == true) {
      await _repository.deleteMedia(widget.r2Key);
      if (mounted) {
        setState(() {
          _isDownloaded = false;
          _localPath = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🗑️ Deleted from device')),
        );
      }
    }
  }

  bool get _isPdf => widget.mimeType == 'application/pdf';
  bool get _isAudio => widget.mimeType.startsWith('audio/');
  bool get _isImage => widget.mimeType.startsWith('image/');
  bool get _isVideo => widget.mimeType.startsWith('video/');

  IconData get _icon {
    if (_isPdf) return Icons.picture_as_pdf;
    if (_isAudio) return Icons.audio_file;
    if (_isImage) return Icons.image;
    if (_isVideo) return Icons.video_file;
    return Icons.insert_drive_file;
  }

  Color get _accentColor {
    if (_isPdf) return const Color(0xFFE53935);
    if (_isAudio) return const Color(0xFF42A5F5);
    if (_isImage) return const Color(0xFF66BB6A);
    if (_isVideo) return const Color(0xFFAB47BC);
    return const Color(0xFF9E9E9E);
  }

  String _formatSize(int bytes) {
    if (bytes == 0) return 'Unknown size';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    // For IMAGES: Show WhatsApp-style preview (image with tap to expand)
    if (_isImage) {
      return _buildImagePreview();
    }

    // For PDFs, Audio, etc: Show file card with download button
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final card = InkWell(
      onTap: _isDownloaded ? _open : null,
      onLongPress: _isDownloaded ? _delete : null,
      child: Container(
        width: 260,
        constraints: const BoxConstraints(minWidth: 220, minHeight: 140),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (_isPdf || _isAudio)
                ? _accentColor.withOpacity(isDark ? 0.5 : 0.4)
                : (isDark
                    ? _accentColor.withOpacity(0.35)
                    : Colors.grey.withOpacity(0.25)),
            width: (_isPdf || _isAudio) ? 1.4 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: Icon + File info
            Row(
              children: [
                Icon(_icon, color: _accentColor, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1D21),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatSize(widget.fileSize),
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Action button (Download/Open/Progress)
            if (_isDownloading && !widget.isMe)
              Column(
                children: [
                  LinearProgressIndicator(
                    value: _downloadProgress,
                    backgroundColor: isDark ? Colors.white24 : Colors.black12,
                    valueColor: AlwaysStoppedAnimation<Color>(_accentColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Downloading... ${(_downloadProgress * 100).toInt()}%',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 11,
                    ),
                  ),
                ],
              )
            else if (_isDownloaded)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _open,
                  icon: Icon(_isPdf ? Icons.open_in_new : Icons.play_arrow),
                  label: Text(_isPdf ? 'View PDF' : 'Play Audio'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (_isPdf || _isAudio)
                        ? _accentColor
                        : (isDark
                            ? _accentColor
                            : _accentColor.withOpacity(0.12)),
                    foregroundColor: (_isPdf || _isAudio)
                        ? Colors.white
                        : (isDark
                            ? Colors.white
                            : const Color(0xFF1A1D21)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              )
            else if (!widget.isMe)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _download,
                  icon: const Icon(Icons.download),
                  label: Text('Download ${_formatSize(widget.fileSize)}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (_isPdf || _isAudio)
                        ? _accentColor
                        : (isDark
                            ? _accentColor.withOpacity(0.3)
                            : _accentColor.withOpacity(0.12)),
                    foregroundColor: (_isPdf || _isAudio)
                        ? Colors.white
                        : (isDark
                            ? Colors.white
                            : const Color(0xFF1A1D21)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (!widget.uploading) return card;

    return Stack(
      alignment: Alignment.center,
      children: [
        card,
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: CircularProgressIndicator(
                      value: widget.uploadProgress,
                      strokeWidth: 4,
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.uploadProgress == null
                        ? 'Sending...'
                        : '${((widget.uploadProgress ?? 0.0) * 100).toInt()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Build WhatsApp-style image preview
  Widget _buildImagePreview() {
    return GestureDetector(
      onTap: () {
        if (_isDownloaded && _localPath != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _FullImageViewer(
                imagePath: _localPath!,
                fileName: widget.fileName,
              ),
            ),
          );
        } else {
          // Block viewing until download; start download instead
          _download();
        }
      },
      onLongPress: _isDownloaded ? _delete : null,
      child: Container(
        width: 260,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              // Show downloaded image or thumbnail
              if (_isDownloaded && _localPath != null)
                () {
                  // Double-check the file is actually an image before loading
                  final filePath = _localPath!.toLowerCase();
                  final isImageFile = filePath.endsWith('.jpg') || 
                                     filePath.endsWith('.jpeg') || 
                                     filePath.endsWith('.png') ||
                                     filePath.endsWith('.gif') ||
                                     filePath.endsWith('.webp');
                  
                  if (!isImageFile) {
                    print('⚠️ Invalid image file type: $_localPath');
                    return _buildThumbnailFallback();
                  }
                  
                  return Image.file(
                    File(_localPath!),
                    height: 260,
                    width: 260,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      print('❌ Error loading image from: $_localPath');
                      return _buildThumbnailFallback();
                    },
                  );
                }()
              else if (widget.thumbnailBase64 != null &&
                  widget.thumbnailBase64!.isNotEmpty)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                      Colors.black38,
                      BlendMode.darken,
                    ),
                    child: _buildThumbnailFallback(),
                  ),
                )
              else
                Container(
                  height: 260,
                  width: 260,
                  color: Colors.grey[800],
                  child: const Icon(
                    Icons.image,
                    size: 64,
                    color: Colors.white54,
                  ),
                ),

              // Download overlay only for receivers; sender auto-fetches silently
              if (!_isDownloaded && !_isDownloading && !widget.isMe)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.25),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.download,
                              color: Colors.black,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Download to view',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Uploading overlay centered inside the image (for sender pending)
              if (widget.uploading)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.45),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 56,
                            height: 56,
                            child: CircularProgressIndicator(
                              value: widget.uploadProgress,
                              strokeWidth: 4,
                              color: Colors.white,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.uploadProgress == null
                                ? 'Sending...'
                                : '${((widget.uploadProgress ?? 0.0) * 100).toInt()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Download progress overlay
              if (_isDownloading)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.7),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            value: _downloadProgress,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${(_downloadProgress * 100).toInt()}%',
                            style: const TextStyle(color: Colors.white),
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
    );
  }

  Widget _buildThumbnailFallback() {
    if (widget.thumbnailBase64 == null || widget.thumbnailBase64!.isEmpty) {
      return Container(
        height: 260,
        width: 260,
        color: Colors.grey[800],
        child: const Icon(
          Icons.image,
          size: 64,
          color: Colors.white54,
        ),
      );
    }

    return Image.memory(
      base64Decode(widget.thumbnailBase64!),
      height: 260,
      width: 260,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        print('❌ Error loading thumbnail');
        return Container(
          height: 260,
          width: 260,
          color: Colors.grey[800],
          child: const Icon(
            Icons.broken_image,
            size: 64,
            color: Colors.white54,
          ),
        );
      },
    );
  }
}

/// Full screen image viewer for local images
class _FullImageViewer extends StatelessWidget {
  final String imagePath;
  final String fileName;

  const _FullImageViewer({required this.imagePath, required this.fileName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: Text(
          fileName,
          style: const TextStyle(fontSize: 16, color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: PhotoView(
        imageProvider: FileImage(File(imagePath)),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 2,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
      ),
    );
  }
}

/// Thumbnail viewer with download option
class _ThumbnailViewer extends StatelessWidget {
  final String thumbnailBase64;
  final String fileName;
  final VoidCallback onDownload;

  const _ThumbnailViewer({
    required this.thumbnailBase64,
    required this.fileName,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: Text(
          fileName,
          style: const TextStyle(fontSize: 16, color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              onDownload();
            },
            tooltip: 'Download full quality',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: PhotoView(
                imageProvider: MemoryImage(base64Decode(thumbnailBase64)),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 2,
                backgroundDecoration: const BoxDecoration(color: Colors.black),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.black87,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Colors.white70,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'This is a preview. Tap download for full quality.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
