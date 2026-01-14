import 'package:cloud_firestore/cloud_firestore.dart';
import 'product_model.dart';

/// Status enum for reward requests
enum RewardRequestStatus {
  pendingParentApproval,
  approvedPurchaseInProgress,
  awaitingDeliveryConfirmation,
  completed,
  expiredOrAutoResolved,
  cancelled;

  String get value {
    return toString().split('.').last;
  }

  String get displayName {
    switch (this) {
      case RewardRequestStatus.pendingParentApproval:
        return 'Pending Parent Approval';
      case RewardRequestStatus.approvedPurchaseInProgress:
        return 'Order in Progress';
      case RewardRequestStatus.awaitingDeliveryConfirmation:
        return 'Awaiting Delivery';
      case RewardRequestStatus.completed:
        return 'Completed';
      case RewardRequestStatus.expiredOrAutoResolved:
        return 'Expired';
      case RewardRequestStatus.cancelled:
        return 'Cancelled';
    }
  }

  static RewardRequestStatus fromString(String value) {
    return RewardRequestStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => RewardRequestStatus.pendingParentApproval,
    );
  }
}

/// Reward request model
class RewardRequestModel {
  final String requestId;
  final String studentId;
  final String parentId;
  final ProductModel productSnapshot;
  final PointsData pointsData;
  final RewardRequestStatus status;
  final String? purchaseMode; // 'amazon', 'manual', null
  final double? manualPrice; // Price for manual purchases
  final ConfirmationData? confirmation;
  final TimestampsData timestamps;
  final List<AuditEntry> audit;
  final DateTime? lastReminderSentAt; // For 3-day reminder system

  RewardRequestModel({
    required this.requestId,
    required this.studentId,
    required this.parentId,
    required this.productSnapshot,
    required this.pointsData,
    required this.status,
    this.purchaseMode,
    this.manualPrice,
    this.confirmation,
    required this.timestamps,
    required this.audit,
    this.lastReminderSentAt,
  });

  /// Check if request can transition to next status
  bool canTransitionTo(RewardRequestStatus nextStatus) {
    switch (status) {
      case RewardRequestStatus.pendingParentApproval:
        return nextStatus == RewardRequestStatus.approvedPurchaseInProgress ||
            nextStatus == RewardRequestStatus.cancelled ||
            nextStatus == RewardRequestStatus.expiredOrAutoResolved;
      case RewardRequestStatus.approvedPurchaseInProgress:
        return nextStatus == RewardRequestStatus.awaitingDeliveryConfirmation ||
            nextStatus == RewardRequestStatus.cancelled ||
            nextStatus == RewardRequestStatus.expiredOrAutoResolved;
      case RewardRequestStatus.awaitingDeliveryConfirmation:
        return nextStatus == RewardRequestStatus.completed ||
            nextStatus == RewardRequestStatus.cancelled ||
            nextStatus == RewardRequestStatus.expiredOrAutoResolved;
      default:
        return false;
    }
  }

  /// Check if lock has expired
  bool get isLockExpired {
    return DateTime.now().isAfter(timestamps.lockExpiresAt);
  }

  /// Get remaining days in lock
  int get remainingDays {
    final diff = timestamps.lockExpiresAt.difference(DateTime.now());
    return diff.inDays;
  }

  /// Convert to Firestore document
  Map<String, dynamic> toMap() {
    return {
      'request_id': requestId,
      'student_id': studentId,
      'parent_id': parentId,
      'product_snapshot': productSnapshot.toMap(),
      'points': pointsData.toMap(),
      'status': status.value,
      'purchase_mode': purchaseMode,
      'manual_price': manualPrice,
      'confirmation': confirmation?.toMap(),
      'timestamps': timestamps.toMap(),
      'audit': audit.map((e) => e.toMap()).toList(),
      'last_reminder_sent_at': lastReminderSentAt != null
          ? Timestamp.fromDate(lastReminderSentAt!)
          : null,
    };
  }

  /// Create from Firestore document
  factory RewardRequestModel.fromMap(Map<String, dynamic> map) {
    // Handle both complex structure (from RewardsRepository) and simple structure (from RewardRequestService)

    // Create a minimal ProductModel from simple structure if needed
    ProductModel getProductModel() {
      if (map['product_snapshot'] != null) {
        return ProductModel.fromMap(map['product_snapshot'] ?? {});
      }
      // Fallback: create minimal product from simple fields
      return ProductModel(
        productId: map['productId'] ?? '',
        source: 'manual',
        title: map['productName'] ?? '',
        price: PriceModel(
          currency: 'INR',
          estimatedPrice: (map['price'] as num?)?.toDouble() ?? 0.0,
        ),
        pointsRule: PointsRuleModel(pointsPerRupee: 2.0, maxPoints: 5000),
        status: 'active',
        createdAt: DateTime.now(),
        description: map['amazonLink'],
        affiliateUrl: map['amazonLink'],
      );
    }

    // Get or create PointsData
    PointsData getPointsData() {
      if (map['points'] != null) {
        return PointsData.fromMap(map['points']);
      }
      // Fallback for simple structure
      return PointsData(
        required: (map['pointsRequired'] as num?)?.toInt() ?? 0,
        locked: (map['pointsRequired'] as num?)?.toInt() ?? 0,
        deducted: 0,
      );
    }

    return RewardRequestModel(
      requestId: map['request_id'] ?? map['id'] ?? '',
      studentId: map['student_id'] ?? map['studentId'] ?? '',
      parentId: map['parent_id'] ?? map['parentId'] ?? '',
      productSnapshot: getProductModel(),
      pointsData: getPointsData(),
      status: RewardRequestStatus.fromString(map['status'] ?? ''),
      purchaseMode: map['purchase_mode'],
      manualPrice: (map['manual_price'] as num?)?.toDouble(),
      confirmation: map['confirmation'] != null
          ? ConfirmationData.fromMap(map['confirmation'])
          : null,
      timestamps: TimestampsData.fromMap(map['timestamps'] ?? {}),
      audit:
          (map['audit'] as List?)?.map((e) => AuditEntry.fromMap(e)).toList() ??
          [],
      lastReminderSentAt: (map['last_reminder_sent_at'] as Timestamp?)
          ?.toDate(),
    );
  }

  /// Create a copy with modified fields
  RewardRequestModel copyWith({
    String? requestId,
    String? studentId,
    String? parentId,
    ProductModel? productSnapshot,
    PointsData? pointsData,
    RewardRequestStatus? status,
    String? purchaseMode,
    double? manualPrice,
    ConfirmationData? confirmation,
    TimestampsData? timestamps,
    List<AuditEntry>? audit,
    DateTime? lastReminderSentAt,
  }) {
    return RewardRequestModel(
      requestId: requestId ?? this.requestId,
      studentId: studentId ?? this.studentId,
      parentId: parentId ?? this.parentId,
      productSnapshot: productSnapshot ?? this.productSnapshot,
      pointsData: pointsData ?? this.pointsData,
      status: status ?? this.status,
      purchaseMode: purchaseMode ?? this.purchaseMode,
      manualPrice: manualPrice ?? this.manualPrice,
      confirmation: confirmation ?? this.confirmation,
      timestamps: timestamps ?? this.timestamps,
      audit: audit ?? this.audit,
      lastReminderSentAt: lastReminderSentAt ?? this.lastReminderSentAt,
    );
  }
}

/// Points data
class PointsData {
  final int required;
  final int locked;
  final int deducted;

  PointsData({
    required this.required,
    required this.locked,
    required this.deducted,
  });

  int get released => locked - deducted;

  Map<String, dynamic> toMap() {
    return {'required': required, 'locked': locked, 'deducted': deducted};
  }

  factory PointsData.fromMap(Map<String, dynamic> map) {
    return PointsData(
      required: (map['required'] as num?)?.toInt() ?? 0,
      locked: (map['locked'] as num?)?.toInt() ?? 0,
      deducted: (map['deducted'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Confirmation data for manual purchases
class ConfirmationData {
  final String type; // 'amazon', 'manual'
  final double? confirmedPrice; // for manual purchases
  final String? confirmedBy; // parentId or adminId
  final DateTime? confirmedAt;

  ConfirmationData({
    required this.type,
    this.confirmedPrice,
    this.confirmedBy,
    this.confirmedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'confirmed_price': confirmedPrice,
      'confirmed_by': confirmedBy,
      'confirmed_at': confirmedAt != null
          ? Timestamp.fromDate(confirmedAt!)
          : null,
    };
  }

  factory ConfirmationData.fromMap(Map<String, dynamic> map) {
    return ConfirmationData(
      type: map['type'] ?? '',
      confirmedPrice: (map['confirmed_price'] as num?)?.toDouble(),
      confirmedBy: map['confirmed_by'],
      confirmedAt: (map['confirmed_at'] as Timestamp?)?.toDate(),
    );
  }
}

/// Timestamps data
class TimestampsData {
  final DateTime requestedAt;
  final DateTime lockExpiresAt;

  TimestampsData({required this.requestedAt, required this.lockExpiresAt});

  Map<String, dynamic> toMap() {
    return {
      'requested_at': Timestamp.fromDate(requestedAt),
      'lock_expires_at': Timestamp.fromDate(lockExpiresAt),
    };
  }

  factory TimestampsData.fromMap(Map<String, dynamic> map) {
    return TimestampsData(
      requestedAt:
          (map['requested_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lockExpiresAt:
          (map['lock_expires_at'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(days: 21)),
    );
  }
}

/// Audit entry for tracking status changes
class AuditEntry {
  final String actor; // userId
  final String
  action; // 'requested', 'approved', 'ordered', 'delivered', 'cancelled'
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  AuditEntry({
    required this.actor,
    required this.action,
    required this.timestamp,
    this.metadata,
  });

  Map<String, dynamic> toMap() {
    return {
      'actor': actor,
      'action': action,
      'timestamp': Timestamp.fromDate(timestamp),
      'metadata': metadata,
    };
  }

  factory AuditEntry.fromMap(Map<String, dynamic> map) {
    return AuditEntry(
      actor: map['actor'] ?? '',
      action: map['action'] ?? '',
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      metadata: map['metadata'],
    );
  }
}
