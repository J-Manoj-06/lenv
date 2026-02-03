import 'package:flutter/material.dart';

/// Modern, minimal attachment picker bottom sheet
/// Dark-first design with rounded icon buttons
class ModernAttachmentSheet extends StatelessWidget {
  final VoidCallback? onCameraTap;
  final VoidCallback? onImageTap;
  final VoidCallback? onDocumentTap;
  final VoidCallback? onAudioTap;
  final bool cameraEnabled;
  final bool imageEnabled;
  final bool documentEnabled;
  final bool audioEnabled;

  const ModernAttachmentSheet({
    super.key,
    this.onCameraTap,
    this.onImageTap,
    this.onDocumentTap,
    this.onAudioTap,
    this.cameraEnabled = true,
    this.imageEnabled = true,
    this.documentEnabled = true,
    this.audioEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1D1F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade700,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Options row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _AttachmentOption(
                  icon: Icons.camera_alt_outlined,
                  label: 'Camera',
                  enabled: cameraEnabled,
                  onTap: onCameraTap,
                ),
                _AttachmentOption(
                  icon: Icons.image_outlined,
                  label: 'Gallery',
                  enabled: imageEnabled,
                  onTap: onImageTap,
                ),
                _AttachmentOption(
                  icon: Icons.description_outlined,
                  label: 'Document',
                  enabled: documentEnabled,
                  onTap: onDocumentTap,
                ),
                _AttachmentOption(
                  icon: Icons.mic_outlined,
                  label: 'Audio',
                  enabled: audioEnabled,
                  onTap: onAudioTap,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _AttachmentOption extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.enabled,
    this.onTap,
  });

  @override
  State<_AttachmentOption> createState() => _AttachmentOptionState();
}

class _AttachmentOptionState extends State<_AttachmentOption> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.enabled
        ? (_isPressed ? const Color(0xFFF27F0D) : Colors.grey.shade600)
        : Colors.grey.shade800;

    return GestureDetector(
      onTapDown: widget.enabled
          ? (_) => setState(() => _isPressed = true)
          : null,
      onTapUp: widget.enabled
          ? (_) => setState(() => _isPressed = false)
          : null,
      onTapCancel: widget.enabled
          ? () => setState(() => _isPressed = false)
          : null,
      onTap: widget.enabled
          ? () {
              setState(() => _isPressed = false);
              widget.onTap?.call();
            }
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon button
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.2), width: 1),
            ),
            child: Icon(widget.icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          // Label
          Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: widget.enabled
                  ? Colors.grey.shade400
                  : Colors.grey.shade700,
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
  // Legacy support for old parameter names
  @Deprecated('Use onDocumentTap instead') VoidCallback? onPdfTap,
  bool cameraEnabled = true,
  bool imageEnabled = true,
  bool documentEnabled = true,
  bool audioEnabled = true,
  // Legacy support for old parameter names
  @Deprecated('Use documentEnabled instead') bool? pdfEnabled,
}) {
  // Use new parameter if provided, otherwise fall back to legacy
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
      cameraEnabled: cameraEnabled,
      imageEnabled: imageEnabled,
      documentEnabled: effectiveDocumentEnabled,
      audioEnabled: audioEnabled,
    ),
  );
}
