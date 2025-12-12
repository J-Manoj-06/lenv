import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/pdf_viewer_screen.dart';

/// Compact attachment pill for non-image media (e.g., PDFs)
class ChatAttachmentTile extends StatelessWidget {
  final String fileName;
  final String url;
  final String? mimeType;
  final bool isMe;

  const ChatAttachmentTile({
    super.key,
    required this.fileName,
    required this.url,
    this.mimeType,
    this.isMe = false,
  });

  bool get _isPdf {
    final type = mimeType?.toLowerCase() ?? '';
    return type == 'application/pdf' || fileName.toLowerCase().endsWith('.pdf');
  }

  bool get _isAudio {
    final type = mimeType?.toLowerCase() ?? '';
    return type.startsWith('audio/') ||
        fileName.toLowerCase().endsWith('.m4a') ||
        fileName.toLowerCase().endsWith('.mp3') ||
        fileName.toLowerCase().endsWith('.wav') ||
        fileName.toLowerCase().endsWith('.aac');
  }

  @override
  Widget build(BuildContext context) {
    final accent = _isPdf
        ? const Color(0xFFE53935)
        : _isAudio
        ? const Color(0xFF42A5F5)
        : const Color(0xFFAB47BC);

    return InkWell(
      onTap: () => _open(context),
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withOpacity(0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              _isPdf
                  ? Icons.picture_as_pdf
                  : _isAudio
                  ? Icons.audio_file
                  : Icons.insert_drive_file,
              color: accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isPdf
                        ? 'Tap to view PDF'
                        : _isAudio
                        ? 'Tap to play'
                        : 'Tap to open file',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.open_in_new, size: 16, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    if (_isPdf) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PDFViewerScreen(path: url, title: fileName),
        ),
      );
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showError(context, 'Invalid file URL');
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      _showError(context, 'Unable to open file');
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
