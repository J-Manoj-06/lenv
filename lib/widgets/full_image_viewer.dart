import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import '../models/media_metadata.dart';
import '../services/local_media_storage_service.dart';
import '../services/media_download_service.dart';

/// Full-screen image viewer with WhatsApp-style behavior
class FullImageViewer extends StatefulWidget {
  final MediaMetadata metadata;

  const FullImageViewer({super.key, required this.metadata});

  @override
  State<FullImageViewer> createState() => _FullImageViewerState();
}

class _FullImageViewerState extends State<FullImageViewer> {
  final LocalMediaStorageService _storageService = LocalMediaStorageService();
  final MediaDownloadService _downloadService = MediaDownloadService();

  File? _imageFile;
  bool _isLoading = true;
  String? _errorMessage;
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Step 1: Check if exists locally
      final localFile = await _storageService.loadImage(
        widget.metadata.messageId,
      );

      if (localFile != null) {
        setState(() {
          _imageFile = localFile;
          _isLoading = false;
        });
        return;
      }

      // Step 2: Download if not local
      if (!widget.metadata.deletedLocally && widget.metadata.isAvailable) {
        final result = await _downloadService.downloadImage(
          metadata: widget.metadata,
          onProgress: (progress) {
            setState(() {
              _downloadProgress = progress;
            });
          },
        );

        if (result.success && result.metadata.hasLocalFile) {
          final file = await _storageService.loadImage(
            widget.metadata.messageId,
          );
          setState(() {
            _imageFile = file;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = result.error?.message ?? 'Failed to load image';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Image not available';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_imageFile != null)
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onPressed: _showOptions,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFA929)),
            ),
            const SizedBox(height: 16),
            Text(
              '${(_downloadProgress * 100).toInt()}%',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Downloading...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 64),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadImage,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFA929),
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      );
    }

    if (_imageFile == null) {
      return const Center(
        child: Text(
          'Image not available',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      );
    }

    return PhotoView(
      imageProvider: FileImage(_imageFile!),
      initialScale: PhotoViewComputedScale.contained,
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 3,
      basePosition: Alignment.center,
      enablePanAlways: false,
      tightMode: true,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      loadingBuilder: (context, event) => Center(
        child: CircularProgressIndicator(
          value: event == null
              ? 0
              : event.cumulativeBytesLoaded / event.expectedTotalBytes!,
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFA929)),
        ),
      ),
    );
  }

  void _showOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1C20),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Delete from device',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _storageService.deleteImage(widget.metadata.messageId);
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Image deleted from device')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
