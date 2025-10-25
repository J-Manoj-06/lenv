import 'package:flutter/foundation.dart';
import '../models/reward_model.dart';
import '../services/firestore_service.dart';

class RewardProvider with ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();
  
  List<RewardModel> _rewards = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<RewardModel> get rewards => _rewards;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Create reward
  Future<bool> createReward(RewardModel reward) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _firestoreService.createReward(reward);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Load rewards for student
  void loadRewardsByStudent(String studentId) {
    _isLoading = true;
    notifyListeners();

    _firestoreService.getRewardsByStudent(studentId).listen(
      (rewards) {
        _rewards = rewards;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = error.toString();
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  // Accept reward
  Future<bool> acceptReward(String rewardId) async {
    try {
      await _firestoreService.updateReward(rewardId, {
        'status': RewardStatus.accepted.toString().split('.').last,
        'acceptedAt': DateTime.now(),
      });
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  // Reject reward
  Future<bool> rejectReward(String rewardId) async {
    try {
      await _firestoreService.updateReward(rewardId, {
        'status': RewardStatus.rejected.toString().split('.').last,
      });
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  // Get pending rewards count
  int get pendingRewardsCount {
    return _rewards.where((r) => r.status == RewardStatus.pending).length;
  }

  // Get total points
  int get totalPoints {
    return _rewards
        .where((r) => r.status == RewardStatus.accepted && r.points != null)
        .fold(0, (sum, reward) => sum + reward.points!);
  }

  // Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
