import 'package:flutter/material.dart';

/// Modern, colorful attachment picker bottom sheet
/// Teacher theme with violet/purple color palette
class ModernAttachmentSheet extends StatelessWidget {
  final VoidCallback? onCameraTap;
  final VoidCallback? onImageTap;
  final VoidCallback? onDocumentTap;
  final VoidCallback? onAudioTap;
  final VoidCallback? onPollTap;
  final bool cameraEnabled;
  final bool imageEnabled;
  final bool documentEnabled;
  final bool audioEnabled;
  final bool pollEnabled;

  const ModernAttachmentSheet({
    super.key,
    this.onCameraTap,
    this.onImageTap,
    this.onDocumentTap,
    this.onAudioTap,
    this.onPollTap,
    this.cameraEnabled = true,
    this.imageEnabled = true,
    this.documentEnabled = true,
    this.audioEnabled = true,
    this.pollEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          
          // Title
          const Text(
            'Send Attachment',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),

          // Options row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AttachmentOption(
                icon: Icons.camera_alt,
                label: 'Camera',
                color: const Color(0xFF7C3AED),
                enabled: cameraEnabled,
                onTap: onCameraTap,
              ),
              _AttachmentOption(
                icon: Icons.image,
                label: 'Gallery',
                color: const Color(0xFF7C3AED),
                enabled: imageEnabled,
                onTap: onImageTap,
              ),
              _AttachmentOption(
                icon: Icons.picture_as_pdf,
                label: 'Document',
                color: const Color(0xFF7C3AED),
                enabled: documentEnabled,
                onTap: onDocumentTap,
              ),
              _AttachmentOption(
                icon: Icons.audiotrack,
                label: 'Audio',
                color: const Color(0xFF7C3AED),
                enabled: audioEnabled,
                onTap: onAudioTap,
              ),
              _AttachmentOption(
                icon: Icons.poll,
                label: 'Poll',
                color: const Color(0xFF7C3AED),
                enabled: pollEnabled,
                onTap: onPollTap,
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _AttachmentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback? onTap;

  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: enabled ? color.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: enabled ? color : Colors.grey,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: enabled ? null : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper function to show the attachment sheet
Future<void> showModernAttachmentSheet(
  BuildContext context, {
  VoidCallback? onCameraTap,
  VoidCallback? onImageTap,
  VoidCallback? onDocumentTap,
  VoidCallback? onAudioTap,
  VoidCallback? onPollTap,
  @Deprecated('Use onDocumentTap instead') VoidCallback? onPdfTap,
  bool cameraEnabled = true,
  bool imageEnabled = true,
  bool documentEnabled = true,
  bool audioEnabled = true,
  bool pollEnabled = true,
  @Deprecated('Use documentEnabled instead') bool? pdfEnabled,
}) {
  final effectiveDocumentTap = onDocumentTap ?? onPdfTap;
  final effectiveDocumentEnabled = documentEnabled && (pdfEnabled ?? true);

  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: false,
    isDismissible: true,
    enableDrag: true,
    builder: (context) => ModernAttachmentSheet(
      onCameraTap: onCameraTap != null
          ? () {
              Navigator.pop(context);
              onCameraTap();
            }
          : null,
      onImageTap: onImageTap != null
          ? () {
              Navigator.pop(context);
              onImageTap();
            }
          : null,
      onDocumentTap: effectiveDocumentTap != null
          ? () {
              Navigator.pop(context);
              effectiveDocumentTap();
            }
          : null,
      onAudioTap: onAudioTap != null
          ? () {
              Navigator.pop(context);
              onAudioTap();
            }
          : null,
      onPollTap: onPollTap != null
          ? () {
              Navigator.pop(context);
              onPollTap();
            }
          : null,
      cameraEnabled: cameraEnabled,
      imageEnabled: imageEnabled,
      documentEnabled: effectiveDocumentEnabled,
      audioEnabled: audioEnabled,
      pollEnabled: pollEnabled,
    ),
  );
}
