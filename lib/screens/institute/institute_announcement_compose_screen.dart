import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart' as prov;
import '../../providers/auth_provider.dart' as auth;
import '../../models/institute_announcement_model.dart';
import '../../services/cloudflare_r2_service.dart';
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
  Uint8List? _imageBytes;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (xFile != null) {
        final bytes = await xFile.readAsBytes();
        setState(() => _imageBytes = bytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
      }
    }
  }

  Future<void> _postAnnouncement() async {
    if (_posting) return;

    final messageText = _controller.text.trim();
    if (messageText.isEmpty && _imageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a message or add an image')),
      );
      return;
    }

    setState(() => _posting = true);

    try {
      final authProvider = prov.Provider.of<auth.AuthProvider>(
        context,
        listen: false,
      );
      final currentUser = authProvider.currentUser;
      if (currentUser == null) throw 'User not logged in';

      String? imageUrl;
      if (_imageBytes != null) {
        print('📤 Starting Cloudflare R2 upload...');

        // Initialize Cloudflare R2 Service with working credentials
        final r2Service = CloudflareR2Service(
          accountId: CloudflareConfig.accountId,
          bucketName: CloudflareConfig.bucketName,
          accessKeyId: CloudflareConfig.accessKeyId,
          secretAccessKey: CloudflareConfig.secretAccessKey,
          r2Domain: CloudflareConfig.r2Domain,
        );

        final fileName =
            'announcement_${currentUser.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';

        print('📂 Uploading to: announcements/$fileName');

        // Generate signed URL
        final signedData = await r2Service.generateSignedUploadUrl(
          fileName: 'announcements/$fileName',
          fileType: 'image/jpeg',
        );

        // Upload file
        imageUrl = await r2Service.uploadFileWithSignedUrl(
          fileBytes: _imageBytes!,
          signedUrl: signedData['url'],
          contentType: 'image/jpeg',
        );

        print('✅ Upload successful! URL: $imageUrl');
      }

      final now = DateTime.now();
      final expiresAt = now.add(const Duration(hours: 24));

      final announcement = InstituteAnnouncementModel(
        id: '',
        principalId: currentUser.uid,
        principalName: currentUser.name,
        principalEmail: currentUser.email,
        instituteId: currentUser.instituteId ?? '',
        text: messageText,
        imageUrl: imageUrl,
        createdAt: now,
        expiresAt: expiresAt,
        audienceType: widget.audienceType,
        standards: widget.standards,
      );

      // Add document to Firestore
      final docRef = await FirebaseFirestore.instance
          .collection('institute_announcements')
          .add(announcement.toFirestore());

      // Initialize empty views subcollection (will be populated when users view)
      await docRef.collection('views').doc('_placeholder').set({
        'placeholder': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      // Delete the placeholder immediately
      await docRef.collection('views').doc('_placeholder').delete();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Announcement posted successfully')),
        );
      }
    } catch (e, stackTrace) {
      print('❌ Storage upload error: $e');
      print('Stack trace: $stackTrace');

      if (mounted) {
        String errorMsg = 'Error posting announcement';
        if (e.toString().contains('object-not-found') ||
            e.toString().contains('404')) {
          errorMsg =
              'Storage bucket not initialized. Please enable Firebase Storage in console.';
        } else if (e.toString().contains('permission-denied') ||
            e.toString().contains('403')) {
          errorMsg =
              'Permission denied. Check Storage rules in Firebase Console.';
        } else if (e.toString().contains('unauthorized')) {
          errorMsg =
              'User not authorized. Please check your account permissions.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$errorMsg\n\nDetails: $e'),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Copy Error',
              onPressed: () {
                // Copy error to clipboard for debugging
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _posting = false);
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
                      'Write a clear message and optionally attach an image.',
                      style: TextStyle(color: _muted, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    _MessageField(controller: _controller),
                    const SizedBox(height: 20),
                    if (_imageBytes != null)
                      _ImagePreview(
                        onRemove: () => setState(() => _imageBytes = null),
                      )
                    else
                      _AddImageButton(onTap: _pickImage),
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

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.onRemove});

  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _muted.withOpacity(0.4)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: onRemove,
          ),
          const SizedBox(height: 8),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.image, color: _teal, size: 48),
          ),
        ],
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
