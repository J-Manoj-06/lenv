import 'package:flutter/material.dart';
import '../models/status_model.dart';

/// Widget showing a circular status preview with gradient ring (WhatsApp-style)
class StatusPreviewWidget extends StatelessWidget {
  final StatusModel status;
  final VoidCallback onTap;
  final bool hasUnseenStatus;
  final double size;

  const StatusPreviewWidget({
    Key? key,
    required this.status,
    required this.onTap,
    this.hasUnseenStatus = false,
    this.size = 64,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status circle with gradient ring
          Stack(
            children: [
              // Gradient ring (for unseen status)
              if (hasUnseenStatus)
                Container(
                  width: size + 4,
                  height: size + 4,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFA78BFA), Color(0xFF7B61FF)],
                    ),
                  ),
                )
              else
                // Gray ring for seen status
                Container(
                  width: size + 4,
                  height: size + 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade400, width: 2),
                  ),
                ),

              // Inner white ring (padding)
              Positioned(
                left: 2,
                top: 2,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.cardColor,
                    border: Border.all(color: theme.cardColor, width: 3),
                  ),
                ),
              ),

              // Content (image or text preview)
              Positioned(
                left: 5,
                top: 5,
                child: Container(
                  width: size - 6,
                  height: size - 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: status.hasImage
                        ? null
                        : (isDark
                              ? const Color(0xFF1F2937)
                              : const Color(0xFFE8E9EB)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: status.hasImage
                      ? Image.network(
                          status.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) =>
                              _buildTextPreview(isDark),
                        )
                      : _buildTextPreview(isDark),
                ),
              ),

              // Purple notification dot (top-right for new status)
              if (hasUnseenStatus)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B61FF),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.scaffoldBackgroundColor,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 6),

          // Caption
          SizedBox(
            width: size + 8,
            child: Text(
              _getCaption(),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? theme.colorScheme.onSurface.withOpacity(0.8)
                    : theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextPreview(bool isDark) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Text(
        status.text.length > 20
            ? '${status.text.substring(0, 20)}...'
            : status.text,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          color: isDark ? Colors.white : const Color(0xFF111827),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _getCaption() {
    if (status.hasImage && status.hasText) {
      return status.text.length > 15
          ? '${status.text.substring(0, 15)}...'
          : status.text;
    } else if (status.hasText) {
      return 'Text';
    } else {
      return 'Photo';
    }
  }
}

/// Widget for the "Add Status" button
class AddStatusButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;

  const AddStatusButton({Key? key, required this.onTap, this.size = 64})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size + 4,
            height: size + 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFF27F0D), width: 2),
            ),
            child: Center(
              child: Icon(
                Icons.add,
                color: const Color(0xFFF27F0D),
                size: size * 0.45,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Add',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
