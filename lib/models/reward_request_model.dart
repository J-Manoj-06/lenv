import 'package:cloud_firestore/cloud_firestore.dart';

enum RewardRequestStatus {
  requested,
  pending,
  pendingPrice,
  approved,
  orderPlaced,
  delivered,
  rejected,
}

class RewardRequestModel {
  final String id;
  final String studentId;
  final String studentName;
  final String productId; // reference to ProductModel in 'products'
  final String productName;
  final String productImageUrl;
  final String amazonLink;
  final double price;
  final int pointsRequired;
  final RewardRequestStatus status;
  final String? purchaseMethod;
  final bool priceEntered;
  final double? enteredPrice;
  final int pointsDeducted;
  final DateTime requestedOn;
  final String? parentId; // who approved
  final DateTime? approvedOn;

  RewardRequestModel({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.productId,
    required this.productName,
    this.productImageUrl = '',
    required this.amazonLink,
    required this.price,
    required this.pointsRequired,
    required this.status,
    this.purchaseMethod,
    this.priceEntered = false,
    this.enteredPrice,
    this.pointsDeducted = 0,
    required this.requestedOn,
    this.parentId,
    this.approvedOn,
  });

  factory RewardRequestModel.fromJson(Map<String, dynamic> json, {String? id}) {
    final statusStr = (json['status'] as String? ?? 'pending');
    RewardRequestStatus parseStatus(String s) {
      switch (s) {
        case 'requested':
          return RewardRequestStatus.requested;
        case 'pending_price':
        case 'pendingPrice':
          return RewardRequestStatus.pendingPrice;
        case 'approved':
          return RewardRequestStatus.approved;
        case 'approvedPurchaseInProgress':
        case 'order_placed':
        case 'orderPlaced':
          return RewardRequestStatus.orderPlaced;
        case 'delivered':
          return RewardRequestStatus.delivered;
        case 'rejected':
        case 'cancelled':
          return RewardRequestStatus.rejected;
        case 'pendingParentApproval':
        case 'pending_parent_approval':
          return RewardRequestStatus.pending;
        default:
          return RewardRequestStatus.pending;
      }
    }

    // Handle both old format (requestedOn) and new format (timestamps.requested_at)
    DateTime extractRequestedOn() {
      // Try new format first: timestamps.requested_at
      if (json['timestamps'] is Map) {
        final timestamps = json['timestamps'] as Map;
        if (timestamps['requested_at'] is Timestamp) {
          return (timestamps['requested_at'] as Timestamp).toDate();
        }
      }

      // Fall back to old format: requestedOn
      if (json['requestedOn'] is Timestamp) {
        return (json['requestedOn'] as Timestamp).toDate();
      }

      return DateTime.tryParse(json['requestedOn']?.toString() ?? '') ??
          DateTime.now();
    }

    // Extract product info from product_snapshot (new format) or direct fields (old format)
    String extractProductName() {
      if (json['product_snapshot'] is Map) {
        final product = json['product_snapshot'] as Map;
        return product['title'] as String? ?? 'Unknown Product';
      }
      return json['productName'] as String? ?? 'Unknown Product';
    }

    String extractProductImageUrl() {
      if (json['product_snapshot'] is Map) {
        final product = json['product_snapshot'] as Map;
        final directImage = product['image_url'] as String?;
        if (directImage != null && directImage.trim().isNotEmpty) {
          return directImage.trim();
        }

        final images = product['images'];
        if (images is List && images.isNotEmpty) {
          final firstImage = images.first;
          if (firstImage is Map) {
            final imageUrl = firstImage['url'] as String?;
            if (imageUrl != null && imageUrl.trim().isNotEmpty) {
              return imageUrl.trim();
            }
          }
        }
      }

      final directImage = json['imageUrl'] as String?;
      if (directImage != null && directImage.trim().isNotEmpty) {
        return directImage.trim();
      }

      return '';
    }

    String extractAmazonLink() {
      if (json['product_snapshot'] is Map) {
        final product = json['product_snapshot'] as Map;
        return product['affiliate_url'] as String? ??
            product['description'] as String? ??
            '';
      }
      return json['amazonLink'] as String? ?? '';
    }

    double extractPrice() {
      if (json['product_snapshot'] is Map) {
        final product = json['product_snapshot'] as Map;
        final price = product['price'];
        if (price is Map) {
          return (price['estimated_price'] as num? ?? 0).toDouble();
        }
      }
      return (json['price'] as num? ?? 0).toDouble();
    }

    int extractPointsRequired() {
      // Try new format: points.required
      if (json['points'] is Map) {
        final points = json['points'] as Map;
        return (points['required'] as num? ?? 0).toInt();
      }
      // Fall back to old format
      return (json['pointsRequired'] as num? ?? 0).toInt();
    }

    String extractProductId() {
      if (json['product_snapshot'] is Map) {
        final product = json['product_snapshot'] as Map;
        return product['product_id'] as String? ?? '';
      }
      return json['productId'] as String? ?? '';
    }

    String extractStudentName() {
      final directName = json['studentName'] as String?;
      if (directName != null && directName.trim().isNotEmpty) {
        return directName.trim();
      }

      final snakeCaseName = json['student_name'] as String?;
      if (snakeCaseName != null && snakeCaseName.trim().isNotEmpty) {
        return snakeCaseName.trim();
      }

      if (json['student_snapshot'] is Map) {
        final student = json['student_snapshot'] as Map;
        final snapshotName =
            student['name'] as String? ??
            student['student_name'] as String? ??
            student['full_name'] as String?;
        if (snapshotName != null && snapshotName.trim().isNotEmpty) {
          return snapshotName.trim();
        }
      }

      return 'Unknown Student';
    }

    return RewardRequestModel(
      id: id ?? (json['id'] as String? ?? json['request_id'] as String? ?? ''),
      studentId:
          (json['studentId'] as String? ?? json['student_id'] as String? ?? ''),
      studentName: extractStudentName(),
      productId: extractProductId(),
      productName: extractProductName(),
      productImageUrl: extractProductImageUrl(),
      amazonLink: extractAmazonLink(),
      price: extractPrice(),
      pointsRequired: extractPointsRequired(),
      status: parseStatus(statusStr),
        purchaseMethod:
          json['purchaseMethod'] as String? ??
          json['purchase_method'] as String? ??
          json['purchase_mode'] as String?,
        priceEntered: (json['priceEntered'] as bool?) ??
          (json['price_entered'] as bool?) ??
          false,
        enteredPrice: (json['enteredPrice'] as num?)?.toDouble() ??
          (json['entered_price'] as num?)?.toDouble() ??
          (json['manual_price'] as num?)?.toDouble(),
        pointsDeducted: (json['pointsDeducted'] as num?)?.toInt() ??
          (json['points_deducted'] as num?)?.toInt() ??
          (json['points'] is Map
            ? (((json['points'] as Map)['deducted'] as num?)?.toInt() ?? 0)
            : 0),
      requestedOn: extractRequestedOn(),
      parentId: json['parentId'] as String? ?? json['parent_id'] as String?,
      approvedOn: (json['approvedOn'] is Timestamp)
          ? (json['approvedOn'] as Timestamp).toDate()
          : (json['approved_on'] is Timestamp)
          ? (json['approved_on'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'student_id': studentId,
    'studentName': studentName,
    'productId': productId,
    'productName': productName,
    'imageUrl': productImageUrl,
    'amazonLink': amazonLink,
    'price': price,
    'pointsRequired': pointsRequired,
    'status': _statusString(status),
    if (purchaseMethod != null) 'purchaseMethod': purchaseMethod,
    'priceEntered': priceEntered,
    if (enteredPrice != null) 'enteredPrice': enteredPrice,
    'pointsDeducted': pointsDeducted,
    'timestamps': {'requested_at': Timestamp.fromDate(requestedOn)},
    if (parentId != null) 'parentId': parentId,
    if (approvedOn != null) 'approvedOn': Timestamp.fromDate(approvedOn!),
  };

  static String _statusString(RewardRequestStatus s) {
    switch (s) {
      case RewardRequestStatus.requested:
        return 'requested';
      case RewardRequestStatus.pendingPrice:
        return 'pending_price';
      case RewardRequestStatus.approved:
        return 'approved';
      case RewardRequestStatus.orderPlaced:
        return 'order_placed';
      case RewardRequestStatus.delivered:
        return 'delivered';
      case RewardRequestStatus.rejected:
        return 'rejected';
      case RewardRequestStatus.pending:
        return 'pending';
    }
  }
}

// Amazon Product Model (Mock data - to be replaced with actual API)
class AmazonProductModel {
  final String id;
  final String title;
  final String? description;
  final double price;
  final String? imageUrl;
  final double? rating;
  final int? reviewCount;
  final String category;
  final String amazonLink;

  AmazonProductModel({
    required this.id,
    required this.title,
    this.description,
    required this.price,
    this.imageUrl,
    this.rating,
    this.reviewCount,
    required this.category,
    required this.amazonLink,
  });

  // Calculate points required (1.5 points per rupee)
  int get pointsRequired => (price * 1.5).round();

  // Mock products for demonstration (to be replaced with API calls)
  static List<AmazonProductModel> getMockProducts({
    String query = '',
    String category = 'All',
  }) {
    final allProducts = [
      AmazonProductModel(
        id: '1',
        title: 'Bluetooth Wireless Headphones',
        description: 'Premium sound quality with noise cancellation',
        price: 999,
        imageUrl: 'https://m.media-amazon.com/images/I/61iiPh7TPNL._SX679_.jpg',
        rating: 4.5,
        reviewCount: 1250,
        category: 'Electronics',
        amazonLink: 'https://www.amazon.in/dp/B0EXAMPLE1',
      ),
      AmazonProductModel(
        id: '2',
        title: 'Study Desk Lamp LED',
        description: 'Adjustable brightness, eye-care LED lamp',
        price: 499,
        imageUrl: 'https://m.media-amazon.com/images/I/51Y7EXAMPLE.jpg',
        rating: 4.2,
        reviewCount: 890,
        category: 'Home',
        amazonLink: 'https://www.amazon.in/dp/B0EXAMPLE2',
      ),
      AmazonProductModel(
        id: '3',
        title: 'Water Bottle 1L Insulated',
        description: 'Keeps water cold for 24 hours',
        price: 349,
        imageUrl: 'https://m.media-amazon.com/images/I/61EXAMPLE.jpg',
        rating: 4.7,
        reviewCount: 2100,
        category: 'Sports',
        amazonLink: 'https://www.amazon.in/dp/B0EXAMPLE3',
      ),
      AmazonProductModel(
        id: '4',
        title: 'Backpack Laptop 15.6"',
        description: 'Waterproof, multiple compartments',
        price: 799,
        imageUrl: 'https://m.media-amazon.com/images/I/71EXAMPLE.jpg',
        rating: 4.4,
        reviewCount: 1560,
        category: 'Bags',
        amazonLink: 'https://www.amazon.in/dp/B0EXAMPLE4',
      ),
      AmazonProductModel(
        id: '5',
        title: 'Wireless Mouse Gaming RGB',
        description: 'RGB lighting, 6 programmable buttons',
        price: 699,
        imageUrl: 'https://m.media-amazon.com/images/I/61EXAMPLE2.jpg',
        rating: 4.6,
        reviewCount: 980,
        category: 'Electronics',
        amazonLink: 'https://www.amazon.in/dp/B0EXAMPLE5',
      ),
      AmazonProductModel(
        id: '6',
        title: 'Notebook Set A5 - 5 Pack',
        description: 'Premium quality paper, spiral bound',
        price: 299,
        imageUrl: 'https://m.media-amazon.com/images/I/71EXAMPLE3.jpg',
        rating: 4.3,
        reviewCount: 750,
        category: 'Stationery',
        amazonLink: 'https://www.amazon.in/dp/B0EXAMPLE6',
      ),
      AmazonProductModel(
        id: '7',
        title: 'Fitness Tracker Smart Band',
        description: 'Heart rate monitor, sleep tracking',
        price: 1299,
        imageUrl: 'https://m.media-amazon.com/images/I/61EXAMPLE4.jpg',
        rating: 4.1,
        reviewCount: 1890,
        category: 'Electronics',
        amazonLink: 'https://www.amazon.in/dp/B0EXAMPLE7',
      ),
      AmazonProductModel(
        id: '8',
        title: 'Portable Speaker Bluetooth',
        description: 'Waterproof, 12-hour battery life',
        price: 899,
        imageUrl: 'https://m.media-amazon.com/images/I/71EXAMPLE5.jpg',
        rating: 4.5,
        reviewCount: 1670,
        category: 'Electronics',
        amazonLink: 'https://www.amazon.in/dp/B0EXAMPLE8',
      ),
    ];

    // Filter by search query
    var filtered = allProducts;
    if (query.isNotEmpty) {
      filtered = filtered
          .where(
            (p) =>
                p.title.toLowerCase().contains(query.toLowerCase()) ||
                (p.description?.toLowerCase().contains(query.toLowerCase()) ??
                    false),
          )
          .toList();
    }

    // Filter by category
    if (category != 'All' &&
        category != 'Badges' &&
        category != 'Points' &&
        category != 'Certificates' &&
        category != 'Gifts' &&
        category != 'Custom') {
      filtered = filtered.where((p) => p.category == category).toList();
    }

    return filtered;
  }

  static List<String> getCategories() {
    return ['All', 'Electronics', 'Home', 'Sports', 'Bags', 'Stationery'];
  }
}
