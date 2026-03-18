import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import '../models/local_message.dart';
import '../repositories/local_message_repository.dart';
import '../services/firebase_message_sync_service.dart';

/// Initialize offline-first architecture
/// WHY: Must be called on app startup before any chat operations
/// Call this in main.dart BEFORE runApp()
Future<void> initializeOfflineFirst() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Hive
  await Hive.initFlutter();

  // 2. Register Hive adapters
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(LocalMessageAdapter());
  }

  // 3. Initialize local repository
  final localRepo = LocalMessageRepository();
  await localRepo.initialize();
}

/// Provider for offline message services
/// WHY: Makes services available throughout the app
class OfflineMessageProvider extends ChangeNotifier {
  final LocalMessageRepository localRepo = LocalMessageRepository();
  FirebaseMessageSyncService? _syncService;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Initialize services
  Future<void> initialize() async {
    if (_isInitialized) return;

    await localRepo.initialize();
    _syncService = FirebaseMessageSyncService(localRepo);
    _isInitialized = true;

    notifyListeners();
  }

  /// Get sync service
  FirebaseMessageSyncService get syncService {
    if (_syncService == null) {
      throw Exception('OfflineMessageProvider not initialized');
    }
    return _syncService!;
  }

  /// Cleanup on logout
  /// WHY: Stop sync listeners but KEEP cached messages for next login
  Future<void> cleanupOnLogout() async {
    // Only stop sync listeners - don't delete cached messages
    await _syncService?.stopAllSyncs();

    notifyListeners();
  }

  @override
  void dispose() {
    localRepo.close();
    _syncService?.stopAllSyncs();
    super.dispose();
  }
}

/// Extension to access offline services in widgets
extension OfflineServiceExtension on BuildContext {
  OfflineMessageProvider get offlineMessages =>
      Provider.of<OfflineMessageProvider>(this, listen: false);
}
