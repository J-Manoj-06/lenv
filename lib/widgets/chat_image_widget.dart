import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/media_metadata.dart';
import '../services/media_download_service.dart';
import '../services/local_media_storage_service.dart';
import 'full_image_viewer.dart';

/// WhatsApp-style chat image widget
/// Shows thumbnail, loads full image on tap, handles all states
class ChatImageWidget extends StatefulWidget {
  final MediaMetadata metadata;
  final double width;
  final double height;
  final bool isMe;

  const ChatImageWidget({
    super.key,
    required this.metadata,
    this.width = 250,
    this.height = 250,
    this.isMe = false,
  });

  @override
  State<ChatImageWidget> createState() => _ChatImageWidgetState();
}

class _ChatImageWidgetState extends State<ChatImageWidget> {
  final MediaDownloadService _downloadService = MediaDownloadService();
  final LocalMediaStorageService _storageService = LocalMediaStorageService();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _handleTap(context),
      onLongPress: () => _showOptions(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: widget.width,
          height: widget.height,
          color: Colors.black12,
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    // Deleted locally
    if (widget.metadata.deletedLocally) {
      return _buildPlaceholder(
        icon: Icons.image_not_supported,
        message: 'Image is no longer\non your device',
        canRetry: false,
      );
    }

    // Expired
    if (widget.metadata.isExpired) {
      return _buildPlaceholder(
        icon: Icons.access_time,
        message: 'Image expired on server',
        subtitle: 'Expired on ${_formatDate(widget.metadata.expiresAt)}',
        canRetry: false,
      );
    }

    // Missing
    if (widget.metadata.isMissing) {
      return _buildPlaceholder(
        icon: Icons.cloud_off,
        message: 'Image not found on server',
        canRetry: false,
      );
    }

    // Loading
    if (_isLoading) {
      return _buildLoadingState();
    }

    // Error
    if (_errorMessage != null) {
      return _buildPlaceholder(
        icon: Icons.error_outline,
        message: _errorMessage!,
        canRetry: true,
      );
    }

    // Show thumbnail (always available)
    return _buildThumbnail();
  }

  Widget _buildThumbnail() {
    try {
      // Decode base64 thumbnail
      final bytes = base64Decode(widget.metadata.thumbnail);
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(bytes, fit: BoxFit.cover),
          // Overlay to indicate it's a preview
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [
                  Colors.black.withValues(alpha: 0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Tap to view indicator
          const Align(
            alignment: Alignment.center,
            child: Icon(Icons.zoom_out_map, color: Colors.white70, size: 32),
          ),
        ],
      );
    } catch (e) {
      return _buildPlaceholder(
        icon: Icons.broken_image,
        message: 'Failed to load thumbnail',
        canRetry: false,
      );
    }
  }

  Widget _buildLoadingState() {
    return Container(
      color: Colors.black12,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFA929)),
            ),
            SizedBox(height: 8),
            Text(
              'Downloading...',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder({
    required IconData icon,
    required String message,
    String? subtitle,
    required bool canRetry,
  }) {
    return Container(
      color: Colors.black12,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white38, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ],
            if (canRetry) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => _handleTap(context),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFFA929),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _handleTap(BuildContext context) async {
    // Check if can download
    if (!widget.metadata.isAvailable || widget.metadata.deletedLocally) {
      return;
    }

    // Check if already exists locally
    final exists = await _storageService.imageExists(widget.metadata.messageId);
    if (exists) {
      _openFullScreen(context);
      return;
    }

    // Download first
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _downloadService.downloadImage(
      metadata: widget.metadata,
    );

    setState(() {
      _isLoading = false;
    });

    if (result.success) {
      _openFullScreen(context);
    } else {
      setState(() {
        _errorMessage = result.error?.message ?? 'Download failed';
      });
    }
  }

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullImageViewer(metadata: widget.metadata),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1C20),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.metadata.deletedLocally) ...[
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Delete from device',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteLocally();
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.white70),
              title: const Text(
                'Image info',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _showInfo(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteLocally() async {
    final deleted = await _storageService.deleteImage(
      widget.metadata.messageId,
    );
    if (deleted) {
      // Update metadata in Firestore
      // This should be handled by the parent widget
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image deleted from device')),
      );
    }
  }

  void _showInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1C20),
        title: const Text('Image Info', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('Uploaded', _formatDate(widget.metadata.uploadedAt)),
            _infoRow('Expires', _formatDate(widget.metadata.expiresAt)),
            _infoRow('Size', _formatBytes(widget.metadata.fileSize ?? 0)),
            _infoRow('Status', widget.metadata.serverStatus.toString()),
            _infoRow('Local', widget.metadata.hasLocalFile ? 'Yes' : 'No'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
