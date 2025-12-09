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
    Key? key,
    required this.message,
    required this.isOwn,
    this.onLongPress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isOwn
                ? Color(0xFFDCF8C6) // WhatsApp green
                : Color(0xFFEBEBEB), // Gray
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
              bottomLeft: Radius.circular(isOwn ? 12 : 2),
              bottomRight: Radius.circular(isOwn ? 2 : 12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                message.text,
                style: TextStyle(color: Colors.black87, fontSize: 15),
              ),
              SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(message.createdAt),
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  if (isOwn) ...[
                    SizedBox(width: 4),
                    Icon(
                      (message.readByParent && message.readByTeacher)
                          ? Icons.done_all
                          : Icons.done,
                      size: 14,
                      color: Colors.black54,
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
    Key? key,
    required this.media,
    required this.isOwn,
    this.onTap,
    this.onLongPress,
    this.onDownload,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
              bottomLeft: Radius.circular(isOwn ? 12 : 2),
              bottomRight: Radius.circular(isOwn ? 2 : 12),
            ),
            color: isOwn ? Color(0xFFDCF8C6) : Color(0xFFEBEBEB),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Media preview
              if (media.isImage)
                MediaImagePreview(
                  media: media,
                  maxWidth: 250,
                  onTap: onTap,
                  showSenderInfo: false,
                )
              else if (media.isPdf)
                Padding(
                  padding: EdgeInsets.all(8),
                  child: MediaPdfPreview(
                    media: media,
                    maxWidth: 230,
                    onTap: onTap,
                    onDownload: onDownload,
                  ),
                ),

              // Time + status
              Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Upload status
                    if (media.isPending)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.orange,
                          ),
                        ),
                      )
                    else if (media.uploadFailed)
                      Icon(Icons.error, size: 14, color: Colors.red),

                    SizedBox(width: 4),
                    Text(
                      _formatTime(media.createdAt),
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                    if (isOwn) ...[
                      SizedBox(width: 4),
                      Icon(Icons.done_all, size: 12, color: Colors.black54),
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
    Key? key,
    required this.message,
    required this.isOwn,
    this.onTap,
    this.onLongPress,
    this.onDownload,
  }) : super(key: key);

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
    Key? key,
    required this.fileName,
    required this.progress,
    this.onCancel,
  }) : super(key: key);

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
