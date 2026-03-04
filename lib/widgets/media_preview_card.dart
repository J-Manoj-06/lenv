import 'package:flutter/material.dart';
import '../services/media_repository.dart';
import '../services/media_availability_service.dart';
import '../screens/audio_player_screen.dart';
import 'package:photo_view/photo_view.dart';
import 'package:open_filex/open_filex.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  final bool selectionMode; // Disable gestures when in selection mode
  final Color? themeColor; // Optional theme color for border and buttons
  final String? userRole; // User role to determine default theme color

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
    this.selectionMode = false,
    this.themeColor,
    this.userRole,
  });

  @override
  State<MediaPreviewCard> createState() => _MediaPreviewCardState();
}

class _MediaPreviewCardState extends State<MediaPreviewCard> {
  final MediaRepository _repository = MediaRepository();
  final MediaAvailabilityService _availabilityService =
      MediaAvailabilityService();
  bool _isDownloaded = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _checkDownloadStatus();
  }

  @override
  void didUpdateWidget(MediaPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-check download status if r2Key changes (pending -> uploaded)
    if (oldWidget.r2Key != widget.r2Key) {
      _checkDownloadStatus();
    }
  }

  Future<void> _checkDownloadStatus() async {
    // For sender's own uploaded media, check if local file still exists
    if (widget.localPath != null &&
        widget.localPath!.isNotEmpty &&
        widget.isMe) {
      final file = File(widget.localPath!);
      if (await file.exists()) {
        if (mounted) {
          setState(() {
            _isDownloaded = true;
            _localPath = widget.localPath;
          });
        }
        return;
      }
      // Local file doesn't exist anymore (temp cache cleaned up)
      // Need to download from R2 if upload completed
      print('⚠️ Local file deleted: ${widget.localPath}');
    }

    // Use MediaAvailabilityService to check if media is cached
    final availability = await _availabilityService.checkMediaAvailability(
      widget.r2Key,
    );

    if (mounted) {
      setState(() {
        _isDownloaded = availability.isCached;
        if (_isDownloaded) {
          // Get the cached local path
          _availabilityService.getCachedFilePath(widget.r2Key).then((path) {
            if (mounted && path != null) {
              setState(() {
                _localPath = path;
              });
            }
          });
        }
      });
    }

    // DO NOT auto-download - user must explicitly tap download button
    // This saves bandwidth and gives users control over downloads
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
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ ${result.message}')));
      }
    }
  }

  void _open() {
    print(
      '🎯 _open() called: localPath=$_localPath, isDownloaded=$_isDownloaded, isAudio=$_isAudio, uploading=${widget.uploading}',
    );

    // Block playback if still uploading
    if (widget.uploading) {
      print('⏳ File is still uploading, cannot play yet');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait, audio is still uploading...'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_localPath == null) return;

    // Verify file still exists before trying to open
    final file = File(_localPath!);
    print('🔍 Checking if file exists: ${file.path}');
    final fileExists = file.existsSync();
    print('🔍 File exists: $fileExists');

    if (!fileExists) {
      print('❌ File does NOT exist, triggering re-download');
      // File was deleted, need to re-download
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File no longer available, downloading...'),
          duration: Duration(seconds: 2),
        ),
      );
      _download(); // Re-download the file
      return;
    }

    print('✅ File exists, opening...');

    if (_isDocument) {
      print('📄 Opening document with system app');
      // Open documents with system app picker
      OpenFilex.open(_localPath!, type: widget.mimeType);
    } else if (_isAudio) {
      print('🎵 Opening audio player screen with path: $_localPath');
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

  /// Open PDF/Document/Audio - checks if downloaded first, otherwise downloads
  Future<void> _openFromR2() async {
    if (!_isDocument && !_isAudio) return;

    print(
      '📂 Opening from R2: r2Key=${widget.r2Key}, localPath=$_localPath, isDownloaded=$_isDownloaded',
    );

    // Check if already downloaded locally and file still exists
    if (_isDownloaded && _localPath != null) {
      final file = File(_localPath!);
      final fileExists = await file.exists();

      print('📂 Checking local file: path=$_localPath, exists=$fileExists');

      if (fileExists) {
        print('✅ Playing from local file: $_localPath');
        // Open immediately without downloading
        if (_isDocument) {
          await OpenFilex.open(_localPath!, type: widget.mimeType);
        } else if (_isAudio) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AudioPlayerScreen(
                audioUrl: _localPath!,
                fileName: widget.fileName,
              ),
            ),
          );
        }
        return;
      }
      // File doesn't exist anymore, fall through to download
      print('⚠️ Local file missing, will download from R2');
    }

    // Check if r2Key still shows as pending (not uploaded yet)
    if (widget.r2Key.startsWith('pending/')) {
      print('❌ Cannot play - file not uploaded to R2 yet: ${widget.r2Key}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please wait, file is still uploading...'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Not downloaded yet or file deleted - download first then open
    try {
      print('📥 Downloading from R2: ${widget.r2Key}');

      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isAudio ? 'Downloading audio...' : 'Preparing document...',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // Download to cache
      final result = await MediaRepository().downloadMedia(
        r2Key: widget.r2Key,
        fileName: widget.fileName,
        mimeType: widget.mimeType,
        onProgress: (progress) {
          print(
            '📥 Download progress: ${(progress * 100).toStringAsFixed(0)}%',
          );
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      print(
        '📥 Download result: success=${result.success}, path=${result.localPath}, message=${result.message}',
      );

      // Check if download succeeded
      if (result.success && result.localPath != null) {
        // Verify file exists before opening
        final file = File(result.localPath!);
        final fileExists = await file.exists();

        if (!fileExists) {
          throw Exception('Downloaded file not found: ${result.localPath}');
        }

        print('✅ Download complete, file exists: ${result.localPath}');

        // Update state
        setState(() {
          _isDownloaded = true;
          _localPath = result.localPath;
        });

        // Open with appropriate viewer
        if (_isDocument) {
          await OpenFilex.open(result.localPath!, type: widget.mimeType);
        } else if (_isAudio) {
          print('🎵 Opening audio player with: ${result.localPath}');
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AudioPlayerScreen(
                audioUrl: result.localPath!,
                fileName: widget.fileName,
              ),
            ),
          );
        }
      } else {
        throw Exception(result.message);
      }
    } catch (e) {
      print('❌ Error downloading/opening file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Note: This method is kept for future implementation but currently unused
  /// To use: uncomment and call from UI delete button handler
  /*
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
  */

  bool get _isPdf => widget.mimeType == 'application/pdf';
  bool get _isAudio => widget.mimeType.startsWith('audio/');
  bool get _isImage => widget.mimeType.startsWith('image/');
  bool get _isVideo => widget.mimeType.startsWith('video/');

  // Check if it's a document (PDF or Office files)
  bool get _isDocument =>
      widget.mimeType == 'application/pdf' ||
      widget.mimeType == 'application/msword' || // .doc
      widget.mimeType ==
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document' || // .docx
      widget.mimeType == 'application/vnd.ms-excel' || // .xls
      widget.mimeType ==
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' || // .xlsx
      widget.mimeType == 'application/vnd.ms-powerpoint' || // .ppt
      widget.mimeType ==
          'application/vnd.openxmlformats-officedocument.presentationml.presentation' || // .pptx
      widget.mimeType == 'text/plain' || // .txt
      widget.mimeType == 'text/csv' || // .csv
      widget.mimeType == 'application/rtf' || // .rtf
      widget.mimeType == 'application/vnd.oasis.opendocument.text' || // .odt
      widget.mimeType ==
          'application/vnd.oasis.opendocument.spreadsheet' || // .ods
      widget.mimeType ==
          'application/vnd.oasis.opendocument.presentation'; // .odp

  bool get _isWord =>
      widget.mimeType == 'application/msword' ||
      widget.mimeType ==
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
      widget.mimeType == 'application/vnd.oasis.opendocument.text';

  bool get _isExcel =>
      widget.mimeType == 'application/vnd.ms-excel' ||
      widget.mimeType ==
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ||
      widget.mimeType == 'application/vnd.oasis.opendocument.spreadsheet';

  bool get _isPowerPoint =>
      widget.mimeType == 'application/vnd.ms-powerpoint' ||
      widget.mimeType ==
          'application/vnd.openxmlformats-officedocument.presentationml.presentation' ||
      widget.mimeType == 'application/vnd.oasis.opendocument.presentation';

  IconData get _icon {
    if (_isPdf) return Icons.picture_as_pdf;
    if (_isWord) return Icons.description;
    if (_isExcel) return Icons.table_chart;
    if (_isPowerPoint) return Icons.slideshow;
    if (_isAudio) return Icons.audio_file;
    if (_isImage) return Icons.image;
    if (_isVideo) return Icons.video_file;
    return Icons.insert_drive_file;
  }

  Color get _accentColor {
    if (_isPdf) return const Color(0xFFE53935); // Red
    if (_isWord) return const Color(0xFF1976D2); // Blue
    if (_isExcel) return const Color(0xFF388E3C); // Green
    if (_isPowerPoint) return const Color(0xFFD84315); // Orange
    if (_isAudio) return const Color(0xFF42A5F5); // Light Blue
    if (_isImage) return const Color(0xFF66BB6A); // Light Green
    if (_isVideo) return const Color(0xFFAB47BC); // Purple
    return const Color(0xFF9E9E9E); // Gray
  }

  String _formatSize(int bytes) {
    if (bytes == 0) return 'Unknown size';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    print('📱 MediaPreviewCard.build() called');
    print('   - r2Key: ${widget.r2Key}');
    print('   - mimeType: ${widget.mimeType}');
    print('   - fileName: ${widget.fileName}');

    // For IMAGES: Show WhatsApp-style preview (image with tap to expand)
    if (_isImage) {
      print('✅ _isImage=true, calling _buildImagePreview()');
      return _buildImagePreview();
    }

    // For PDFs, Audio, etc: Show file card with download button
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final card = GestureDetector(
      // Disable tap if still uploading, in selection mode, or not downloaded
      onTap: widget.selectionMode || widget.uploading
          ? null
          : (_isDownloaded ? _open : null),
      onLongPress: null, // Let parent GestureDetector handle selection
      child: Builder(
        builder: (context) {
          final bgColor = isDark
              ? const Color(0xFF2C2C2E)
              : const Color(0xFFFFFFFF);
          final borderColor =
              widget.themeColor ??
              (isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0));
          print('🎨 MEDIAPREVIEWCARD DECORATION:');
          print(
            '   - backgroundColor: ${isDark ? "0xFF2C2C2E (dark gray)" : "0xFFFFFFFF (white)"}',
          );
          print('   - borderRadius: 12');
          print('   - border: 2.5px theme color');
          return Container(
            width: 260,
            constraints: const BoxConstraints(minWidth: 220, minHeight: 140),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 2.5),
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
                        backgroundColor: isDark
                            ? Colors.white24
                            : Colors.black12,
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
                      onPressed: widget.selectionMode ? null : _open,
                      icon: Icon(
                        _isDocument
                            ? Icons.open_in_new
                            : _isAudio
                            ? Icons.play_arrow
                            : _isImage
                            ? Icons.image
                            : Icons.play_arrow,
                      ),
                      label: Text(
                        _isDocument
                            ? 'View Document'
                            : _isAudio
                            ? 'Play Audio'
                            : _isImage
                            ? 'View Image'
                            : 'View',
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
                  // Not downloaded yet - show Download button for both sender and receiver
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: widget.selectionMode ? null : _download,
                      icon: const Icon(Icons.download),
                      label: Text('Download ${_formatSize(widget.fileSize)}'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );

    // Show overlay when uploading - parent will remove pending message when complete
    if (!widget.uploading) return card;

    return Stack(
      alignment: Alignment.center,
      children: [
        card,
        Positioned.fill(
          child: AbsorbPointer(
            absorbing: true,
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
        ),
      ],
    );
  }

  /// Build WhatsApp-style image preview
  Widget _buildImagePreview() {
    print('🖼️ _buildImagePreview() called');
    print('   - isImage: $_isImage');
    print('   - isDownloaded: $_isDownloaded');
    print('   - localPath: $_localPath');
    print(
      '   - thumbnailBase64: ${widget.thumbnailBase64?.substring(0, 50)}...',
    );

    return GestureDetector(
      onTap: widget.selectionMode
          ? null
          : () {
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
      onLongPress: null, // Let parent GestureDetector handle selection
      child: SizedBox(
        width: 250,
        height: 250,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.themeColor ?? const Color(0xFF9E9E9E),
              width: 3.0,
            ),
          ),
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.grey[800],
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Show downloaded image or thumbnail
                if (_isDownloaded &&
                    _localPath != null &&
                    _localPath!.isNotEmpty)
                  () {
                    print('🖼️ Rendering downloaded image from: $_localPath');
                    // Double-check the file is actually an image before loading
                    final filePath = _localPath!.toLowerCase();
                    final isImageFile =
                        filePath.endsWith('.jpg') ||
                        filePath.endsWith('.jpeg') ||
                        filePath.endsWith('.png') ||
                        filePath.endsWith('.gif') ||
                        filePath.endsWith('.webp');

                    if (!isImageFile) {
                      print('❌ File is not a valid image format: $filePath');
                      return Container(
                        color: Colors.grey[800],
                        child: const Icon(
                          Icons.broken_image,
                          size: 64,
                          color: Colors.white54,
                        ),
                      );
                    }

                    print('✅ Loading Image.file with BoxFit.cover');
                    return Image.file(
                      File(_localPath!),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (context, error, stackTrace) {
                        print('❌ Error loading image: $error');
                        return Container(
                          color: Colors.grey[800],
                          child: const Icon(
                            Icons.broken_image,
                            size: 64,
                            color: Colors.white54,
                          ),
                        );
                      },
                    );
                  }()
                else if (widget.thumbnailBase64 != null &&
                    widget.thumbnailBase64!.isNotEmpty)
                  () {
                    print('🖼️ Rendering thumbnail');
                    // Check if it's a file path, URL, or base64 data
                    if (widget.thumbnailBase64!.startsWith('/') &&
                        widget.thumbnailBase64!.length > 1) {
                      print('   - Loading from file path');
                      // It's a file path, use Image.file (NO BLUR for better UX)
                      return Image.file(
                        File(widget.thumbnailBase64!),
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey[800],
                          child: const Icon(
                            Icons.image,
                            size: 64,
                            color: Colors.white54,
                          ),
                        ),
                      );
                    } else if (widget.thumbnailBase64!.startsWith('http')) {
                      print(
                        '   - Network URL detected, loading with CachedNetworkImage',
                      );
                      // Load from R2 URL using CachedNetworkImage
                      return CachedNetworkImage(
                        imageUrl: widget.thumbnailBase64!,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                        placeholder: (context, url) => Container(
                          color: Colors.grey[800],
                          child: const Icon(
                            Icons.image,
                            size: 64,
                            color: Colors.white54,
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey[800],
                          child: const Icon(
                            Icons.broken_image,
                            size: 64,
                            color: Colors.white54,
                          ),
                        ),
                      );
                    } else {
                      print('   - Loading from base64 data');
                      // It's base64 data (NO BLUR for better UX)
                      try {
                        return Image.memory(
                          base64Decode(widget.thumbnailBase64!),
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey[800],
                            child: const Icon(
                              Icons.image,
                              size: 64,
                              color: Colors.white54,
                            ),
                          ),
                        );
                      } catch (e) {
                        print('❌ Error decoding base64: $e');
                        // Invalid base64, show error icon
                        return Container(
                          color: Colors.grey[800],
                          child: const Icon(
                            Icons.broken_image,
                            size: 64,
                            color: Colors.white54,
                          ),
                        );
                      }
                    }
                  }()
                else if (widget.localPath != null &&
                    widget.localPath!.isNotEmpty &&
                    !_isDownloaded)
                  () {
                    print(
                      '🖼️ Showing placeholder, local file will be visible after download',
                    );
                    return Container(
                      color: Colors.grey[800],
                      child: const Icon(
                        Icons.image,
                        size: 64,
                        color: Colors.white54,
                      ),
                    );
                  }()
                else
                  () {
                    print('⚠️ No image data available, showing placeholder');
                    return Container(
                      color: Colors.grey[800],
                      child: const Icon(
                        Icons.image,
                        size: 64,
                        color: Colors.white54,
                      ),
                    );
                  }(),

                // Download overlay only for receivers; sender auto-fetches silently
                // Don't show if uploading or if already downloaded
                if (!_isDownloaded &&
                    !_isDownloading &&
                    !widget.uploading &&
                    !widget.isMe)
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
                // Only show if actually uploading (pending message with progress)
                if (widget.uploading)
                  Positioned.fill(
                    child: AbsorbPointer(
                      absorbing: true,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          color: Colors.black.withOpacity(0.65),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 70,
                                  height: 70,
                                  child: CircularProgressIndicator(
                                    value: widget.uploadProgress,
                                    strokeWidth: 5,
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                          Color(0xFFFFA929),
                                        ),
                                    backgroundColor: Colors.white24,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  widget.uploadProgress == null
                                      ? 'Sending...'
                                      : '${((widget.uploadProgress ?? 0.0) * 100).toInt()}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Download progress overlay - only show when explicitly downloading
                if (_isDownloading && !widget.uploading)
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
      body: imagePath.isNotEmpty
          ? PhotoView(
              imageProvider: FileImage(File(imagePath)),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 2,
              backgroundDecoration: const BoxDecoration(color: Colors.black),
            )
          : Center(
              child: Icon(Icons.broken_image, size: 64, color: Colors.white54),
            ),
    );
  }
}

/// Note: This class is kept for future implementation but currently unused
/// To use: uncomment and integrate into file preview flow
/*
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
*/

/// Cache entry for download status to prevent redundant file checks
class _CachedStatus {
  final bool isDownloaded;
  final String? localPath;
  final double? imgW;
  final double? imgH;
  final DateTime timestamp;

  _CachedStatus({required this.isDownloaded})
    : localPath = null,
      imgW = null,
      imgH = null,
      timestamp = DateTime.now();

  bool get isStale {
    // Cache is valid for 30 seconds
    return DateTime.now().difference(timestamp).inSeconds > 30;
  }
}
