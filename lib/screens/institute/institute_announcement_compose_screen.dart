import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart' as prov;
import '../../providers/auth_provider.dart' as auth;
import '../../models/institute_announcement_model.dart';
import '../../services/cloudflare_r2_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/pending_announcement_service.dart';
import '../../config/cloudflare_config.dart';

const _bg = Color(0xFF0F1416);
const _surface = Color(0xFF1D1F24);
const _muted = Color(0xFF9AA0A6);
const _teal = Color(0xFF146D7A);

class InstituteAnnouncementComposeScreen extends StatefulWidget {
  final String audienceType;
  final List<String> standards;

  const InstituteAnnouncementComposeScreen({
    super.key,
    required this.audienceType,
    required this.standards,
  });

  @override
  State<InstituteAnnouncementComposeScreen> createState() =>
      _InstituteAnnouncementComposeScreenState();
}

class _InstituteAnnouncementComposeScreenState
    extends State<InstituteAnnouncementComposeScreen> {
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
      final xFiles = await picker.pickMultiImage(imageQuality: 85);

      if (xFiles.isNotEmpty) {
        for (var xFile in xFiles) {
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

  /// WhatsApp-style: upload images (if any), queue to local storage,
  /// navigate away immediately, then flush in background.
  Future<void> _postAnnouncement() async {
    if (_posting) return;

    final messageText = _controller.text.trim();
    if (messageText.isEmpty && _imageItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a message or add images')),
      );
      return;
    }

    setState(() => _posting = true);

    try {
      // ── 1. Resolve current user ──────────────────────────────────────────
      final authProvider = prov.Provider.of<auth.AuthProvider>(
        context,
        listen: false,
      );
      await authProvider.forceRefreshUser();
      final currentUser = authProvider.currentUser;
      if (currentUser == null) throw 'Unable to get user. Please try again.';

      // ── 2. Upload images if online ────────────────────────────────────────
      List<Map<String, String>> imageCaptions = [];

      if (_imageItems.isNotEmpty && ConnectivityService().isOnline) {
        final r2Service = CloudflareR2Service(
          accountId: CloudflareConfig.accountId,
          bucketName: CloudflareConfig.bucketName,
          accessKeyId: CloudflareConfig.accessKeyId,
          secretAccessKey: CloudflareConfig.secretAccessKey,
          r2Domain: CloudflareConfig.r2Domain,
        );

        for (int i = 0; i < _imageItems.length; i++) {
          final item = _imageItems[i];
          final imageBytes = item['imageBytes'] as Uint8List;
          final caption = (item['captionController'] as TextEditingController)
              .text
              .trim();

          final fileName =
              'announcement_${currentUser.uid}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';

          final signedData = await r2Service.generateSignedUploadUrl(
            fileName: 'announcements/$fileName',
            fileType: 'image/jpeg',
          );

          final imageUrl = await r2Service.uploadFileWithSignedUrl(
            fileBytes: imageBytes,
            signedUrl: signedData['url'],
            contentType: 'image/jpeg',
          );

          imageCaptions.add({'url': imageUrl, 'caption': caption});
        }
      }

      // ── 3. Build payload ──────────────────────────────────────────────────
      final now = DateTime.now();
      final expiresAt = now.add(const Duration(hours: 24));

      // Build from model to get consistent field names, then patch for queue.
      final model = InstituteAnnouncementModel(
        id: '',
        principalId: currentUser.uid,
        principalName: currentUser.name,
        principalEmail: currentUser.email,
        instituteId: currentUser.instituteId ?? '',
        text: messageText,
        imageCaptions: imageCaptions.isNotEmpty ? imageCaptions : null,
        createdAt: now,
        expiresAt: expiresAt,
        audienceType: widget.audienceType,
        standards: widget.standards,
      );

      final data = model.toFirestore();
      // Replace Timestamp with ISO string (SharedPrefs can't store Timestamps)
      data['expiresAt'] = expiresAt.toIso8601String();
      data.remove('createdAt'); // will be set to serverTimestamp on flush
      data['_collection'] = 'institute_announcements';
      data['_createViewsPlaceholder'] = true;

      // ── 4. Queue locally ─────────────────────────────────────────────────
      await PendingAnnouncementService().enqueue(data);

      // ── 5. Navigate away immediately (WhatsApp-style) ────────────────────
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sending announcement…'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // ── 6. Flush in background ────────────────────────────────────────────
      PendingAnnouncementService().startProcessing();
    } catch (e) {
      if (mounted) {
        setState(() => _posting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error posting announcement: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final targets = widget.audienceType == 'school'
        ? ['Whole School']
        : widget.standards.map((s) => '$s Standard').toList();

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _ComposeTopBar(onBack: () => Navigator.pop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    _RecipientRow(
                      targets: targets,
                      onEdit: () => Navigator.pop(context),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _imageItems.isEmpty
                          ? 'Write a clear message and optionally attach images.'
                          : 'Add captions to your images below.',
                      style: TextStyle(color: _muted, fontSize: 14),
                    ),
                    const SizedBox(height: 12),

                    // Show message field only if no images
                    if (_imageItems.isEmpty) ...[
                      _MessageField(controller: _controller),
                      const SizedBox(height: 20),
                      _AddImageButton(onTap: _pickImages),
                    ] else ...[
                      // Show all images with caption fields
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
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      _AddMoreImagesButton(onTap: _pickImages),
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
      ),
    );
  }
}

class _ComposeTopBar extends StatelessWidget {
  const _ComposeTopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
          ),
          const Expanded(
            child: Text(
              'Create Announcement',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
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
  const _RecipientRow({required this.targets, required this.onEdit});

  final List<String> targets;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'To:',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: targets
                .map(
                  (t) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _teal.withOpacity(0.4)),
                    ),
                    child: Text(
                      t,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        TextButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit, color: _teal, size: 18),
          label: const Text(
            'Edit',
            style: TextStyle(color: _teal, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _MessageField extends StatefulWidget {
  const _MessageField({required this.controller});

  final TextEditingController controller;

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
          minLines: 6,
          maxLength: _maxLength,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Write your announcement...',
            hintStyle: TextStyle(color: _muted),
            filled: true,
            fillColor: _surface,
            counterText: '',
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: _muted.withOpacity(0.4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _teal, width: 1.5),
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
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _AddImageButton extends StatelessWidget {
  const _AddImageButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _muted.withOpacity(0.4)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo, color: _teal, size: 32),
            SizedBox(height: 8),
            Text(
              'Add Image',
              style: TextStyle(
                color: Colors.white,
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
  });

  final Uint8List imageBytes;
  final TextEditingController captionController;
  final VoidCallback onRemove;
  final int imageNumber;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _teal.withOpacity(0.3)),
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
                  color: _teal.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Image $imageNumber',
                  style: const TextStyle(
                    color: _teal,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
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
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Add caption for this image...',
              hintStyle: TextStyle(color: _muted, fontSize: 14),
              filled: true,
              fillColor: _bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(12),
              counterStyle: TextStyle(color: _muted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

// Button to add more images
class _AddMoreImagesButton extends StatelessWidget {
  const _AddMoreImagesButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _teal.withOpacity(0.4), width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate, color: _teal, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Add More Images',
              style: TextStyle(
                color: _teal,
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
  const _BottomActions({required this.onSend, required this.isPosting});

  final VoidCallback onSend;
  final bool isPosting;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: _bg.withOpacity(0.92),
        border: const Border(top: BorderSide(color: Color(0xFF1F2937))),
      ),
      child: ElevatedButton(
        onPressed: isPosting ? null : onSend,
        style: ElevatedButton.styleFrom(
          backgroundColor: _teal,
          disabledBackgroundColor: _teal.withOpacity(0.6),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          isPosting ? 'Sending...' : 'Send Announcement',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
