import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/cloudflare_r2_service.dart';
import '../../config/cloudflare_config.dart';

const _bg = Color(0xFF120F23);
const _surface = Color(0xFF1A1730);
const _muted = Color(0xFF8E8BA3);
const _primary = Color(0xFF7961FF);

class TeacherAnnouncementComposeScreen extends StatefulWidget {
  final String audienceType;
  final List<String> standards;
  final List<String> sections;
  final Map<String, dynamic>? teacherData;

  const TeacherAnnouncementComposeScreen({
    super.key,
    required this.audienceType,
    required this.standards,
    required this.sections,
    this.teacherData,
  });

  @override
  State<TeacherAnnouncementComposeScreen> createState() =>
      _TeacherAnnouncementComposeScreenState();
}

class _TeacherAnnouncementComposeScreenState
    extends State<TeacherAnnouncementComposeScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _posting = false;

  // Multiple images with captions
  final List<Map<String, dynamic>> _imageItems = [];
  // _imageItems structure: [{imageBytes: Uint8List, captionController: TextEditingController}]

  @override
  void dispose() {
    _controller.dispose();
    // Dispose all caption controllers
    for (var item in _imageItems) {
      (item['captionController'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      final picker = ImagePicker();
      List<XFile> xFiles = [];

      try {
        xFiles = await picker.pickMultiImage(imageQuality: 85, limit: 5);
      } catch (e) {
        // Fallback to single image
        final xFile = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
        );
        if (xFile != null) xFiles = [xFile];
      }

      if (xFiles.isNotEmpty) {
        for (var xFile in xFiles) {
          if (_imageItems.length >= 5) break; // Max 5 images
          final bytes = await xFile.readAsBytes();
          setState(() {
            _imageItems.add({
              'imageBytes': bytes,
              'captionController': TextEditingController(),
            });
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking images: $e')));
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      (_imageItems[index]['captionController'] as TextEditingController)
          .dispose();
      _imageItems.removeAt(index);
    });
  }

  Future<void> _postAnnouncement() async {
    if (_posting) return;

    final messageText = _controller.text.trim();

    // Validate text length
    if (messageText.length > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Announcement text cannot exceed 1000 characters'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (messageText.isEmpty && _imageItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a message or add images')),
      );
      return;
    }

    setState(() => _posting = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser == null) throw 'User not logged in';

      // Initialize Cloudflare R2 Service
      final r2Service = CloudflareR2Service(
        accountId: CloudflareConfig.accountId,
        bucketName: CloudflareConfig.bucketName,
        accessKeyId: CloudflareConfig.accessKeyId,
        secretAccessKey: CloudflareConfig.secretAccessKey,
        r2Domain: CloudflareConfig.r2Domain,
      );

      // Upload all images with captions
      List<Map<String, String>> imageCaptions = [];

      for (int i = 0; i < _imageItems.length; i++) {
        final item = _imageItems[i];
        final imageBytes = item['imageBytes'] as Uint8List;
        final captionController =
            item['captionController'] as TextEditingController;
        final caption = captionController.text.trim();

        final fileName =
            'highlight_${currentUser.uid}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';

        // Generate signed URL
        final signedData = await r2Service.generateSignedUploadUrl(
          fileName: 'class_highlights/$fileName',
          fileType: 'image/jpeg',
        );

        // Upload file
        final imageUrl = await r2Service.uploadFileWithSignedUrl(
          fileBytes: imageBytes,
          signedUrl: signedData['url'],
          contentType: 'image/jpeg',
        );

        imageCaptions.add({'url': imageUrl, 'caption': caption});
      }

      final now = DateTime.now();
      final expiresAt = now.add(const Duration(hours: 24));
      final instituteId =
          currentUser.instituteId ?? widget.teacherData?['schoolCode'] ?? '';

      final data = <String, dynamic>{
        'teacherId': currentUser.uid,
        'teacherName':
            widget.teacherData?['teacherName'] ?? currentUser.name ?? 'Teacher',
        'teacherEmail': currentUser.email,
        'instituteId': instituteId,
        'className': 'School-wide', // Can be more specific if needed
        'text': messageText,
        'imageUrl': imageCaptions.isNotEmpty
            ? imageCaptions[0]['url']
            : '', // Legacy support
        'imageCaptions': imageCaptions, // New multi-image support
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
        // Audience targeting
        'audienceType': widget.audienceType,
        'standards': widget.standards,
        'sections': widget.sections,
        // Viewing tracking
        'viewedBy': [], // Initialize empty array
      };

      // Debug: Check what's being stored
      print('📝 Posting announcement:');
      print('   Text length: ${messageText.length}');
      print(
        '   Text content: ${messageText.substring(0, messageText.length > 50 ? 50 : messageText.length)}...',
      );

      await FirebaseFirestore.instance.collection('class_highlights').add(data);

      if (mounted) {
        Navigator.pop(context); // Close compose screen
        Navigator.pop(context); // Close target screen
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Announcement posted for 24 hours.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error posting announcement: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? _bg : Colors.white;
    final surfaceColor = isDark ? _surface : const Color(0xFFF5F5F5);
    final textColor = isDark ? Colors.white : Colors.black87;
    final mutedColor = isDark ? _muted : const Color(0xFF757575);

    String targetText = '';
    if (widget.audienceType == 'school') {
      targetText = 'Whole School';
    } else if (widget.audienceType == 'standard') {
      targetText = widget.standards.map((s) => 'Grade $s').join(', ');
    } else if (widget.audienceType == 'section') {
      targetText = widget.sections.join(', ');
    }

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _ComposeTopBar(
              onBack: () => Navigator.pop(context),
              textColor: textColor,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    _RecipientRow(
                      targetText: targetText,
                      onEdit: () => Navigator.pop(context),
                      surfaceColor: surfaceColor,
                      textColor: textColor,
                      mutedColor: mutedColor,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _imageItems.isEmpty
                          ? 'Write your announcement and optionally add images (max 5).'
                          : 'Add captions to your images below. Captions will be displayed to all viewers.',
                      style: TextStyle(color: mutedColor, fontSize: 14),
                    ),
                    const SizedBox(height: 16),

                    // Show message field only if no images
                    if (_imageItems.isEmpty) ...[
                      // Message field
                      _MessageField(
                        controller: _controller,
                        surfaceColor: surfaceColor,
                        textColor: textColor,
                        mutedColor: mutedColor,
                      ),
                      const SizedBox(height: 16),

                      // Add images button
                      _AddImageButton(
                        onTap: _pickImages,
                        hasImages: false,
                        surfaceColor: surfaceColor,
                        mutedColor: mutedColor,
                      ),
                    ] else ...[
                      // Show all images with caption fields (like principal)
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _imageItems.length,
                        itemBuilder: (context, index) {
                          final item = _imageItems[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _ImageWithCaptionEditor(
                              imageBytes: item['imageBytes'] as Uint8List,
                              captionController:
                                  item['captionController']
                                      as TextEditingController,
                              onRemove: () => _removeImage(index),
                              imageNumber: index + 1,
                              surfaceColor: surfaceColor,
                              textColor: textColor,
                              mutedColor: mutedColor,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      _AddMoreImagesButton(
                        onTap: _pickImages,
                        currentCount: _imageItems.length,
                        surfaceColor: surfaceColor,
                        mutedColor: mutedColor,
                      ),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BottomActions(
        onSend: _postAnnouncement,
        isPosting: _posting,
        bgColor: bgColor,
      ),
    );
  }
}

class _ComposeTopBar extends StatelessWidget {
  const _ComposeTopBar({required this.onBack, required this.textColor});

  final VoidCallback onBack;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: Icon(Icons.arrow_back, color: textColor, size: 26),
          ),
          Expanded(
            child: Text(
              'Create Announcement',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _RecipientRow extends StatelessWidget {
  const _RecipientRow({
    required this.targetText,
    required this.onEdit,
    required this.surfaceColor,
    required this.textColor,
    required this.mutedColor,
  });

  final String targetText;
  final VoidCallback onEdit;
  final Color surfaceColor;
  final Color textColor;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'To:',
          style: TextStyle(
            color: mutedColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _primary.withOpacity(0.4)),
            ),
            child: Text(
              targetText,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit, color: _primary, size: 18),
          label: const Text(
            'Edit',
            style: TextStyle(color: _primary, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _MessageField extends StatefulWidget {
  const _MessageField({
    required this.controller,
    required this.surfaceColor,
    required this.textColor,
    required this.mutedColor,
  });

  final TextEditingController controller;
  final Color surfaceColor;
  final Color textColor;
  final Color mutedColor;

  @override
  State<_MessageField> createState() => _MessageFieldState();
}

class _MessageFieldState extends State<_MessageField> {
  static const int _maxLength = 1000;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        TextField(
          controller: widget.controller,
          maxLines: null,
          minLines: 5,
          maxLength: null,
          style: TextStyle(color: widget.textColor, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Write your announcement...',
            hintStyle: TextStyle(color: widget.mutedColor),
            filled: true,
            fillColor: widget.surfaceColor,
            counterText: '',
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: widget.mutedColor.withOpacity(0.4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _primary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
          onChanged: (_) => setState(() {}),
        ),
        Positioned(
          right: 12,
          bottom: 8,
          child: Text(
            '${widget.controller.text.length}/$_maxLength',
            style: TextStyle(
              color: widget.controller.text.length > _maxLength
                  ? Colors.red
                  : widget.mutedColor,
              fontSize: 12,
              fontWeight: widget.controller.text.length > _maxLength
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}

class _AddImageButton extends StatelessWidget {
  const _AddImageButton({
    required this.onTap,
    required this.hasImages,
    required this.surfaceColor,
    required this.mutedColor,
  });

  final VoidCallback onTap;
  final bool hasImages;
  final Color surfaceColor;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _primary.withOpacity(0.4), width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasImages ? Icons.add_photo_alternate : Icons.image_outlined,
              color: _primary,
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              hasImages ? 'Add More Images' : 'Add Images',
              style: const TextStyle(
                color: _primary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// New widget for editing image with caption
class _ImageWithCaptionEditor extends StatelessWidget {
  const _ImageWithCaptionEditor({
    required this.imageBytes,
    required this.captionController,
    required this.onRemove,
    required this.imageNumber,
    required this.surfaceColor,
    required this.textColor,
    required this.mutedColor,
  });

  final Uint8List imageBytes;
  final TextEditingController captionController;
  final VoidCallback onRemove;
  final int imageNumber;
  final Color surfaceColor;
  final Color textColor;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primary.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with image number and remove button
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Image $imageNumber',
                  style: const TextStyle(
                    color: _primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close, color: mutedColor, size: 20),
                onPressed: onRemove,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Image preview
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              imageBytes,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 12),
          // Caption input field
          TextField(
            controller: captionController,
            maxLines: 3,
            maxLength: 200,
            style: TextStyle(color: textColor, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Add caption for this image...',
              hintStyle: TextStyle(color: mutedColor, fontSize: 14),
              filled: true,
              fillColor: _bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(12),
              counterStyle: TextStyle(color: mutedColor, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

// Button to add more images
class _AddMoreImagesButton extends StatelessWidget {
  const _AddMoreImagesButton({
    required this.onTap,
    required this.currentCount,
    required this.surfaceColor,
    required this.mutedColor,
  });

  final VoidCallback onTap;
  final int currentCount;
  final Color surfaceColor;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    if (currentCount >= 5) {
      return const SizedBox.shrink(); // Hide if max reached
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _primary.withOpacity(0.4), width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_photo_alternate, color: _primary, size: 20),
            const SizedBox(width: 8),
            Text(
              'Add More Images ($currentCount/5)',
              style: const TextStyle(
                color: _primary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.onSend,
    required this.isPosting,
    required this.bgColor,
  });

  final VoidCallback onSend;
  final bool isPosting;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            offset: const Offset(0, -2),
            blurRadius: 8,
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isPosting ? null : onSend,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          disabledBackgroundColor: _primary.withOpacity(0.6),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          isPosting ? 'Posting...' : 'Post Announcement',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
