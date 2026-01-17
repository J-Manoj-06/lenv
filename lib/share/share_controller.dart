import 'package:flutter/material.dart';
import 'incoming_share_data.dart';
import 'share_receiver_service.dart';

/// Controller to manage shared content state across the app
class ShareController extends ChangeNotifier {
  final ShareReceiverService _shareService = ShareReceiverService();
  IncomingShareData? _shareData;
  bool _isProcessing = false;

  IncomingShareData? get shareData => _shareData;
  bool get hasShareData => _shareData != null && !_shareData!.isEmpty;
  bool get isProcessing => _isProcessing;

  /// Initialize and listen for shared content
  Future<void> initialize() async {
    await _shareService.initialize();

    // Listen to share data stream
    _shareService.shareDataStream.listen((data) {
      _shareData = data;
      notifyListeners();
    });

    // Check for initial share data
    _shareData = _shareService.getCurrentShareData();
    if (_shareData != null) {
      notifyListeners();
    }
  }

  /// Mark share as being processed
  void setProcessing(bool processing) {
    _isProcessing = processing;
    notifyListeners();
  }

  /// Clear current share data after forwarding
  void clearShareData() {
    _shareData = null;
    _isProcessing = false;
    _shareService.clearShareData();
    notifyListeners();
  }

  @override
  void dispose() {
    _shareService.dispose();
    super.dispose();
  }
}
