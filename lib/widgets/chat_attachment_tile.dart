import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/pdf_viewer_screen.dart';
import '../screens/audio_player_screen.dart';

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
        ? const Color(0xFFE57373)
        : _isAudio
        ? const Color(0xFF64B5F6)
        : const Color(0xFFBA68C8);

    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1D21),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2D31), width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _isPdf
                    ? Icons.picture_as_pdf_outlined
                    : _isAudio
                    ? Icons.audio_file_outlined
                    : Icons.insert_drive_file_outlined,
                color: accent,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
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
                      color: Color(0xFFE8E8E8),
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isPdf
                        ? 'PDF Document'
                        : _isAudio
                        ? 'Audio'
                        : 'File',
                    style: const TextStyle(
                      color: Color(0xFF6B7075),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF6B7075)),
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

    if (_isAudio) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AudioPlayerScreen(audioUrl: url, fileName: fileName),
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
