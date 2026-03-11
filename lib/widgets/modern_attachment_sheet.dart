import 'package:flutter/material.dart';

/// Modern, colorful attachment picker bottom sheet
/// Supports custom color themes (violet for teachers, orange for students)
class ModernAttachmentSheet extends StatelessWidget {
  final VoidCallback? onCameraTap;
  final VoidCallback? onImageTap;
  final VoidCallback? onDocumentTap;
  final VoidCallback? onAudioTap;
  final VoidCallback? onPollTap;
  final VoidCallback? onMindmapTap;
  final bool cameraEnabled;
  final bool imageEnabled;
  final bool documentEnabled;
  final bool audioEnabled;
  final bool pollEnabled;
  final bool mindmapEnabled;
  final Color color;

  const ModernAttachmentSheet({
    super.key,
    this.onCameraTap,
    this.onImageTap,
    this.onDocumentTap,
    this.onAudioTap,
    this.onPollTap,
    this.onMindmapTap,
    this.cameraEnabled = true,
    this.imageEnabled = true,
    this.documentEnabled = true,
    this.audioEnabled = true,
    this.pollEnabled = true,
    this.mindmapEnabled = true,
    this.color = const Color(0xFF7C3AED),
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

          // Options grid
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 18,
            runSpacing: 14,
            children: [
              _AttachmentOption(
                icon: Icons.camera_alt,
                label: 'Camera',
                color: color,
                enabled: cameraEnabled,
                onTap: onCameraTap,
              ),
              _AttachmentOption(
                icon: Icons.image,
                label: 'Gallery',
                color: color,
                enabled: imageEnabled,
                onTap: onImageTap,
              ),
              _AttachmentOption(
                icon: Icons.picture_as_pdf,
                label: 'Document',
                color: color,
                enabled: documentEnabled,
                onTap: onDocumentTap,
              ),
              _AttachmentOption(
                icon: Icons.audiotrack,
                label: 'Audio',
                color: color,
                enabled: audioEnabled,
                onTap: onAudioTap,
              ),
              _AttachmentOption(
                icon: Icons.poll,
                label: 'Poll',
                color: color,
                enabled: pollEnabled,
                onTap: onPollTap,
              ),
              if (mindmapEnabled)
                _AttachmentOption(
                  icon: Icons.account_tree_outlined,
                  label: 'Mindmap',
                  color: color,
                  enabled: mindmapEnabled,
                  onTap: onMindmapTap,
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
              color: enabled
                  ? color.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: enabled ? color : Colors.grey, size: 28),
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
  VoidCallback? onMindmapTap,
  @Deprecated('Use onDocumentTap instead') VoidCallback? onPdfTap,
  bool cameraEnabled = true,
  bool imageEnabled = true,
  bool documentEnabled = true,
  bool audioEnabled = true,
  bool pollEnabled = true,
  bool mindmapEnabled = true,
  @Deprecated('Use documentEnabled instead') bool? pdfEnabled,
  Color color = const Color(0xFF7C3AED),
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
              Future.delayed(const Duration(milliseconds: 300), onCameraTap);
            }
          : null,
      onImageTap: onImageTap != null
          ? () {
              Navigator.pop(context);
              Future.delayed(const Duration(milliseconds: 300), onImageTap);
            }
          : null,
      onDocumentTap: effectiveDocumentTap != null
          ? () {
              Navigator.pop(context);
              Future.delayed(
                const Duration(milliseconds: 300),
                effectiveDocumentTap,
              );
            }
          : null,
      onAudioTap: onAudioTap != null
          ? () {
              Navigator.pop(context);
              Future.delayed(const Duration(milliseconds: 300), onAudioTap);
            }
          : null,
      onPollTap: onPollTap != null
          ? () {
              Navigator.pop(context);
              Future.delayed(const Duration(milliseconds: 300), onPollTap);
            }
          : null,
      onMindmapTap: onMindmapTap != null
          ? () {
              Navigator.pop(context);
              Future.delayed(const Duration(milliseconds: 300), onMindmapTap);
            }
          : null,
      cameraEnabled: cameraEnabled,
      imageEnabled: imageEnabled,
      documentEnabled: effectiveDocumentEnabled,
      audioEnabled: audioEnabled,
      pollEnabled: pollEnabled,
      mindmapEnabled: mindmapEnabled,
      color: color,
    ),
  );
}
