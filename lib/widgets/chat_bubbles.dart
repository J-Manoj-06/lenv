import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../models/media_message.dart';
import 'media_preview_widgets.dart';

/// WhatsApp-style chat bubble for text messages
class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isOwn;
  final VoidCallback? onLongPress;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isOwn,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: EdgeInsets.symmetric(vertical: 3, horizontal: 12),
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: isOwn
                ? Color(0xFF232629) // Subtle dark for sent
                : Color(0xFF1A1D21), // Slightly darker for received
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(isOwn ? 16 : 4),
              bottomRight: Radius.circular(isOwn ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.text,
                style: TextStyle(
                  color: Color(0xFFE8E8E8),
                  fontSize: 15,
                  height: 1.45,
                  letterSpacing: 0.15,
                ),
              ),
              SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(message.createdAt),
                    style: TextStyle(fontSize: 11, color: Color(0xFF6B7075)),
                  ),
                  if (isOwn) ...[
                    SizedBox(width: 5),
                    Icon(
                      (message.readByParent && message.readByTeacher)
                          ? Icons.done_all
                          : Icons.done,
                      size: 13,
                      color: Color(0xFF6B7075),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

/// WhatsApp-style chat bubble for media messages
class MediaChatBubble extends StatelessWidget {
  final MediaMessage media;
  final bool isOwn;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDownload;

  const MediaChatBubble({
    super.key,
    required this.media,
    required this.isOwn,
    this.onTap,
    this.onLongPress,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: EdgeInsets.symmetric(vertical: 3, horizontal: 12),
          constraints: BoxConstraints(maxWidth: 260),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(isOwn ? 16 : 4),
              bottomRight: Radius.circular(isOwn ? 4 : 16),
            ),
            color: isOwn ? Color(0xFF232629) : Color(0xFF1A1D21),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Media preview
              if (media.isImage)
                ClipRRect(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  child: MediaImagePreview(
                    media: media,
                    maxWidth: 260,
                    onTap: onTap,
                    showSenderInfo: false,
                  ),
                )
              else if (media.isPdf)
                Padding(
                  padding: EdgeInsets.all(12),
                  child: MediaPdfPreview(
                    media: media,
                    maxWidth: 236,
                    onTap: onTap,
                    onDownload: onDownload,
                  ),
                ),

              // Time + status
              Padding(
                padding: EdgeInsets.fromLTRB(14, 8, 14, 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Upload status
                    if (media.isPending)
                      SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF6B7075),
                          ),
                        ),
                      )
                    else if (media.uploadFailed)
                      Icon(Icons.error, size: 13, color: Color(0xFFE57373)),

                    SizedBox(width: 5),
                    Text(
                      _formatTime(media.createdAt),
                      style: TextStyle(fontSize: 11, color: Color(0xFF6B7075)),
                    ),
                    if (isOwn) ...[
                      SizedBox(width: 5),
                      Icon(Icons.done_all, size: 12, color: Color(0xFF6B7075)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

/// Unified chat message widget (text or media)
class UnifiedChatMessage extends StatelessWidget {
  final dynamic message; // ChatMessage or MediaMessage
  final bool isOwn;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDownload;

  const UnifiedChatMessage({
    super.key,
    required this.message,
    required this.isOwn,
    this.onTap,
    this.onLongPress,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    if (message is ChatMessage) {
      return ChatBubble(
        message: message as ChatMessage,
        isOwn: isOwn,
        onLongPress: onLongPress,
      );
    } else if (message is MediaMessage) {
      return MediaChatBubble(
        media: message as MediaMessage,
        isOwn: isOwn,
        onTap: onTap,
        onLongPress: onLongPress,
        onDownload: onDownload,
      );
    }
    return SizedBox.shrink();
  }
}

/// Media upload progress indicator
class MediaUploadProgress extends StatelessWidget {
  final String fileName;
  final int progress; // 0-100
  final VoidCallback? onCancel;

  const MediaUploadProgress({
    super.key,
    required this.fileName,
    required this.progress,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          // Progress indicator
          SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              children: [
                CircularProgressIndicator(
                  value: progress / 100,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF25A55E)),
                ),
                Center(
                  child: Text(
                    '$progress%',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          // File info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                ),
                SizedBox(height: 4),
                Text(
                  progress == 100 ? 'Saving...' : 'Uploading...',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          // Cancel button
          if (onCancel != null)
            IconButton(icon: Icon(Icons.close, size: 20), onPressed: onCancel),
        ],
      ),
    );
  }
}
