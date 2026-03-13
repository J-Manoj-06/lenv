import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/profile_dp_provider.dart';
import '../services/profile_dp_service.dart';
import '../screens/common/full_screen_dp_viewer.dart';
import '../screens/common/image_crop_screen.dart';

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
  final bool isStaffRoomDP;
  final String? staffRoomId;

  const DPOptionsBottomSheet({
    super.key,
    required this.userId,
    required this.userName,
    this.currentImageUrl,
    this.isGroupDP = false,
    this.groupId,
    this.isStaffRoomDP = false,
    this.staffRoomId,
  });

  /// Show the bottom sheet and return when dismissed.
  static Future<void> show({
    required BuildContext context,
    required String userId,
    required String userName,
    String? currentImageUrl,
    bool isGroupDP = false,
    String? groupId,
    bool isStaffRoomDP = false,
    String? staffRoomId,
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
        isStaffRoomDP: isStaffRoomDP,
        staffRoomId: staffRoomId,
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
              isStaffRoomDP
                  ? 'Staff Room Photo'
                  : (isGroupDP ? 'Group Photo' : 'Profile Photo'),
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
              label: isStaffRoomDP
                  ? 'View Staff Room Photo'
                  : (isGroupDP ? 'View Group Photo' : 'View Photo'),
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
            label: isStaffRoomDP
                ? 'Change Staff Room Photo'
                : (isGroupDP ? 'Change Group Photo' : 'Change Photo'),
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
              label: isStaffRoomDP
                  ? 'Remove Staff Room Photo'
                  : (isGroupDP ? 'Remove Group Photo' : 'Remove Photo'),
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
    // Capture all context-dependent refs BEFORE popping the sheet
    final dpProvider = context.read<ProfileDPProvider>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    navigator.pop(); // close bottom sheet

    // 1. Pick image from gallery / camera
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 95,
    );

    if (picked == null) return;

    // 2. Open custom square crop screen (pure Flutter — works with hot reload)
    final File? croppedFile = await navigator.push<File?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageCropScreen(imageFile: File(picked.path)),
      ),
    );

    if (croppedFile == null) return; // user cancelled crop

    // 3. Validate
    final validationError = ProfileDPService.validateImageFile(croppedFile);
    if (validationError != null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(validationError), backgroundColor: Colors.red),
      );
      return;
    }

    // 4. Upload
    bool success;
    if (isStaffRoomDP && staffRoomId != null) {
      success = await dpProvider.uploadStaffRoomImage(
        roomId: staffRoomId!,
        imageFile: croppedFile,
      );
    } else if (isGroupDP && groupId != null) {
      success = await dpProvider.uploadGroupImage(
        groupId: groupId!,
        imageFile: croppedFile,
      );
    } else {
      success = await dpProvider.uploadProfileImage(
        userId: userId,
        imageFile: croppedFile,
      );
    }

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Photo updated successfully!'
              : (dpProvider.uploadError ?? 'Failed to upload photo.'),
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
          isStaffRoomDP
              ? 'Remove Staff Room Photo?'
              : (isGroupDP ? 'Remove Group Photo?' : 'Remove Profile Photo?'),
        ),
        content: Text(
          isStaffRoomDP
              ? 'The staff room photo will be removed.'
              : (isGroupDP
                    ? 'The group photo will be removed.'
                    : 'Your profile photo will be removed.'),
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
    if (isStaffRoomDP && staffRoomId != null) {
      success = await dpProvider.removeStaffRoomImage(roomId: staffRoomId!);
    } else if (isGroupDP && groupId != null) {
      success = await dpProvider.removeGroupImage(groupId: groupId!);
    } else {
      success = await dpProvider.removeProfileImage(userId: userId);
    }

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Photo removed.'
              : (dpProvider.uploadError ?? 'Failed to remove photo.'),
        ),
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
