import 'package:cloud_firestore/cloud_firestore.dart';

enum RewardRequestStatus { pending, approved, orderPlaced, rejected }

class RewardRequestModel {
  final String id;
  final String studentId;
  final String productId; // reference to ProductModel in 'products'
  final String productName;
  final String amazonLink;
  final double price;
  final int pointsRequired;
  final RewardRequestStatus status;
  final DateTime requestedOn;
  final String? parentId; // who approved
  final DateTime? approvedOn;

  RewardRequestModel({
    required this.id,
    required this.studentId,
    required this.productId,
    required this.productName,
    required this.amazonLink,
    required this.price,
    required this.pointsRequired,
    required this.status,
    required this.requestedOn,
    this.parentId,
    this.approvedOn,
  });

  factory RewardRequestModel.fromJson(Map<String, dynamic> json, {String? id}) {
    final statusStr = (json['status'] as String? ?? 'pending');
    RewardRequestStatus parseStatus(String s) {
      switch (s) {
        case 'approved':
          return RewardRequestStatus.approved;
        case 'order_placed':
        case 'orderPlaced':
          return RewardRequestStatus.orderPlaced;
        case 'rejected':
          return RewardRequestStatus.rejected;
        default:
          return RewardRequestStatus.pending;
      }
    }

    return RewardRequestModel(
      id: id ?? (json['id'] as String? ?? ''),
      studentId: (json['studentId'] as String? ?? ''),
      productId: (json['productId'] as String? ?? ''),
      productName: (json['productName'] as String? ?? ''),
      amazonLink: (json['amazonLink'] as String? ?? ''),
      price: (json['price'] as num? ?? 0).toDouble(),
      pointsRequired: (json['pointsRequired'] as num? ?? 0).toInt(),
      status: parseStatus(statusStr),
      requestedOn: (json['requestedOn'] is Timestamp)
          ? (json['requestedOn'] as Timestamp).toDate()
          : DateTime.tryParse(json['requestedOn']?.toString() ?? '') ??
                DateTime.now(),
      parentId: json['parentId'] as String?,
      approvedOn: (json['approvedOn'] is Timestamp)
          ? (json['approvedOn'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'studentId': studentId,
    'productId': productId,
    'productName': productName,
    'amazonLink': amazonLink,
    'price': price,
    'pointsRequired': pointsRequired,
    'status': _statusString(status),
    'requestedOn': Timestamp.fromDate(requestedOn),
    if (parentId != null) 'parentId': parentId,
    if (approvedOn != null) 'approvedOn': Timestamp.fromDate(approvedOn!),
  };

  static String _statusString(RewardRequestStatus s) {
    switch (s) {
      case RewardRequestStatus.approved:
        return 'approved';
      case RewardRequestStatus.orderPlaced:
        return 'order_placed';
      case RewardRequestStatus.rejected:
        return 'rejected';
      case RewardRequestStatus.pending:
        return 'pending';
    }
  }
}
