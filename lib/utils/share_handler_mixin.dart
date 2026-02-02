import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../share/share_controller.dart';
import '../share/share_target_screen.dart';

/// Mixin to handle incoming share intents in main navigation widgets
/// Add this to any StatefulWidget's State class to handle share data
mixin ShareHandlerMixin<T extends StatefulWidget> on State<T> {
  bool _isHandlingShare = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForShareData();
    });
  }

  /// Check for share data and navigate to share target screen
  void _checkForShareData() {
    if (_isHandlingShare) return;

    try {
      final shareController = Provider.of<ShareController>(
        context,
        listen: false,
      );

      if (shareController.hasShareData && !shareController.isProcessing) {
        _isHandlingShare = true;

        // Navigate to share target screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ShareTargetScreen(shareData: shareController.shareData!),
          ),
        ).then((_) {
          // Reset flag when returning from share screen
          _isHandlingShare = false;
        });
      }
    } catch (e) {
      debugPrint('Error handling share data: $e');
      _isHandlingShare = false;
    }
  }

  /// Call this method when the app resumes to check for new share data
  void handleAppResume() {
    _checkForShareData();
  }
}
