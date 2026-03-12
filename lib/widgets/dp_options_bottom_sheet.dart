import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/profile_dp_provider.dart';
import '../services/profile_dp_service.dart';
import '../screens/common/full_screen_dp_viewer.dart';

/// Bottom sheet for DP management actions.
///
/// Provides:
/// - View Photo
/// - Change Photo (Gallery / Camera)
/// - Remove Photo
class DPOptionsBottomSheet extends StatelessWidget {
  final String userId;
  final String userName;
  final String? currentImageUrl;
  final bool isGroupDP;
  final String? groupId;

  const DPOptionsBottomSheet({
    super.key,
    required this.userId,
    required this.userName,
    this.currentImageUrl,
    this.isGroupDP = false,
    this.groupId,
  });

  /// Show the bottom sheet and return when dismissed.
  static Future<void> show({
    required BuildContext context,
    required String userId,
    required String userName,
    String? currentImageUrl,
    bool isGroupDP = false,
    String? groupId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DPOptionsBottomSheet(
        userId: userId,
        userName: userName,
        currentImageUrl: currentImageUrl,
        isGroupDP: isGroupDP,
        groupId: groupId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasImage = currentImageUrl != null && currentImageUrl!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              isGroupDP ? 'Group Photo' : 'Profile Photo',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          // View Photo
          if (hasImage)
            _OptionTile(
              icon: Icons.visibility_outlined,
              label: isGroupDP ? 'View Group Photo' : 'View Photo',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  FullScreenDPViewer.route(
                    imageUrl: currentImageUrl!,
                    userName: userName,
                  ),
                );
              },
            ),
          // Change Photo
          _OptionTile(
            icon: Icons.camera_alt_outlined,
            label: isGroupDP ? 'Change Group Photo' : 'Change Photo',
            onTap: () => _pickAndUpload(context, fromCamera: false),
          ),
          _OptionTile(
            icon: Icons.photo_camera,
            label: 'Take a Photo',
            onTap: () => _pickAndUpload(context, fromCamera: true),
          ),
          // Remove Photo
          if (hasImage) ...[
            const Divider(height: 1),
            _OptionTile(
              icon: Icons.delete_outline,
              label: isGroupDP ? 'Remove Group Photo' : 'Remove Photo',
              labelColor: Colors.red,
              iconColor: Colors.red,
              onTap: () => _confirmRemove(context),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _pickAndUpload(
    BuildContext context, {
    required bool fromCamera,
  }) async {
    // Capture references BEFORE popping (context becomes unmounted after pop)
    final dpProvider = context.read<ProfileDPProvider>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(); // close bottom sheet

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 90,
    );

    if (picked == null) return;

    // Crop to square
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Photo',
          toolbarColor: const Color(0xFF1A1A1A),
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFFF2800D),
          backgroundColor: const Color(0xFF1A1A1A),
          lockAspectRatio: true,
          cropStyle: CropStyle.circle,
          hideBottomControls: false,
          showCropGrid: false,
        ),
        IOSUiSettings(
          title: 'Crop Photo',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          cropStyle: CropStyle.circle,
        ),
      ],
    );

    if (croppedFile == null) return; // user cancelled crop

    final file = File(croppedFile.path);
    final validationError = ProfileDPService.validateImageFile(file);
    if (validationError != null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(validationError), backgroundColor: Colors.red),
      );
      return;
    }

    bool success;
    if (isGroupDP && groupId != null) {
      success = await dpProvider.uploadGroupImage(
        groupId: groupId!,
        imageFile: file,
      );
    } else {
      success = await dpProvider.uploadProfileImage(
        userId: userId,
        imageFile: file,
      );
    }

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Photo updated successfully!' : 'Failed to upload photo.',
        ),
        backgroundColor: success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    // Capture references BEFORE popping
    final dpProvider = context.read<ProfileDPProvider>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(); // close bottom sheet

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isGroupDP ? 'Remove Group Photo?' : 'Remove Profile Photo?',
        ),
        content: Text(
          isGroupDP
              ? 'The group photo will be removed.'
              : 'Your profile photo will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    bool success;
    if (isGroupDP && groupId != null) {
      success = await dpProvider.removeGroupImage(groupId: groupId!);
    } else {
      success = await dpProvider.removeProfileImage(userId: userId);
    }

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(success ? 'Photo removed.' : 'Failed to remove photo.'),
        backgroundColor: success ? null : Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? labelColor;
  final Color? iconColor;

  const _OptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.labelColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultColor = isDark ? Colors.white70 : Colors.black87;

    return ListTile(
      leading: Icon(icon, color: iconColor ?? defaultColor),
      title: Text(
        label,
        style: TextStyle(color: labelColor ?? defaultColor, fontSize: 15),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
    );
  }
}
