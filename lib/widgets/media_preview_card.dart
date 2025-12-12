import 'package:flutter/material.dart';
import '../services/media_repository.dart';
import '../screens/pdf_viewer_screen.dart';
import '../screens/audio_player_screen.dart';
import 'package:photo_view/photo_view.dart';
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
  final bool isMe;

  const MediaPreviewCard({
    super.key,
    required this.r2Key,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    this.thumbnailBase64,
    this.isMe = false,
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
    final downloaded = await _repository.isDownloaded(widget.r2Key);
    final path = await _repository.getLocalFilePath(widget.r2Key);

    if (mounted) {
      setState(() {
        _isDownloaded = downloaded;
        _localPath = path;
      });
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
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _isDownloaded ? _open : null,
      onLongPress: _isDownloaded ? _delete : null,
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: widget.isMe
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _accentColor.withOpacity(0.35)),
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatSize(widget.fileSize),
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Thumbnail for images (if available)
            if (_isImage && widget.thumbnailBase64 != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  base64Decode(widget.thumbnailBase64!),
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Action button (Download/Open/Progress)
            if (_isDownloading)
              Column(
                children: [
                  LinearProgressIndicator(
                    value: _downloadProgress,
                    backgroundColor: Colors.white24,
                    valueColor: AlwaysStoppedAnimation<Color>(_accentColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Downloading... ${(_downloadProgress * 100).toInt()}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              )
            else if (_isDownloaded)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _open,
                  icon: Icon(
                    _isPdf
                        ? Icons.open_in_new
                        : _isAudio
                        ? Icons.play_arrow
                        : Icons.open_in_new,
                  ),
                  label: Text(
                    _isPdf
                        ? 'View PDF'
                        : _isAudio
                        ? 'Play Audio'
                        : _isImage
                        ? 'View Image'
                        : 'Open',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _download,
                  icon: const Icon(Icons.download),
                  label: Text('Download ${_formatSize(widget.fileSize)}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentColor.withOpacity(0.3),
                    foregroundColor: Colors.white,
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
