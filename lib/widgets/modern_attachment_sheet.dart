import 'package:flutter/material.dart';

/// Modern, minimal attachment picker bottom sheet
/// Dark-first design with rounded icon buttons
class ModernAttachmentSheet extends StatelessWidget {
  final VoidCallback? onImageTap;
  final VoidCallback? onPdfTap;
  final VoidCallback? onAudioTap;
  final bool imageEnabled;
  final bool pdfEnabled;
  final bool audioEnabled;

  const ModernAttachmentSheet({
    super.key,
    this.onImageTap,
    this.onPdfTap,
    this.onAudioTap,
    this.imageEnabled = true,
    this.pdfEnabled = true,
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
                  icon: Icons.image_outlined,
                  label: 'Image',
                  enabled: imageEnabled,
                  onTap: onImageTap,
                ),
                _AttachmentOption(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'PDF',
                  enabled: pdfEnabled,
                  onTap: onPdfTap,
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
  VoidCallback? onImageTap,
  VoidCallback? onPdfTap,
  VoidCallback? onAudioTap,
  bool imageEnabled = true,
  bool pdfEnabled = true,
  bool audioEnabled = true,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: false,
    isDismissible: true,
    enableDrag: true,
    builder: (context) => ModernAttachmentSheet(
      onImageTap: onImageTap != null
          ? () {
              Navigator.pop(context);
              onImageTap();
            }
          : null,
      onPdfTap: onPdfTap != null
          ? () {
              Navigator.pop(context);
              onPdfTap();
            }
          : null,
      onAudioTap: onAudioTap != null
          ? () {
              Navigator.pop(context);
              onAudioTap();
            }
          : null,
      imageEnabled: imageEnabled,
      pdfEnabled: pdfEnabled,
      audioEnabled: audioEnabled,
    ),
  );
}
