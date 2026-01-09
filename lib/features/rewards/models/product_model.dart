import 'package:cloud_firestore/cloud_firestore.dart';

/// Product model for reward catalog
class ProductModel {
  final String productId;
  final String source; // 'amazon', 'flipkart', 'manual'
  final String? asin; // Amazon ASIN
  final String title;
  final String? imageUrl;
  final PriceModel price;
  final String? affiliateUrl;
  final PointsRuleModel pointsRule;
  final String status; // 'active', 'inactive', 'discontinued'
  final DateTime createdAt;
  final String? description;
  final double? rating;
  final int? reviewCount;

  ProductModel({
    required this.productId,
    required this.source,
    this.asin,
    required this.title,
    this.imageUrl,
    required this.price,
    this.affiliateUrl,
    required this.pointsRule,
    required this.status,
    required this.createdAt,
    this.description,
    this.rating,
    this.reviewCount,
  });

  /// Convert to Firestore document
  Map<String, dynamic> toMap() {
    return {
      'product_id': productId,
      'source': source,
      'asin': asin,
      'title': title,
      'image_url': imageUrl,
      'price': price.toMap(),
      'affiliate_url': affiliateUrl,
      'points_rule': pointsRule.toMap(),
      'status': status,
      'created_at': Timestamp.fromDate(createdAt),
      'description': description,
      'rating': rating,
      'review_count': reviewCount,
    };
  }

  /// Create from Firestore document
  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      productId: map['product_id'] ?? '',
      source: map['source'] ?? 'manual',
      asin: map['asin'],
      title: map['title'] ?? '',
      imageUrl: map['image_url'],
      price: PriceModel.fromMap(map['price'] ?? {}),
      affiliateUrl: map['affiliate_url'],
      pointsRule: PointsRuleModel.fromMap(map['points_rule'] ?? {}),
      status: map['status'] ?? 'active',
      createdAt: (map['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      description: map['description'],
      rating: (map['rating'] as num?)?.toDouble(),
      reviewCount: map['review_count'],
    );
  }

  /// Create a copy with modified fields
  ProductModel copyWith({
    String? productId,
    String? source,
    String? asin,
    String? title,
    String? imageUrl,
    PriceModel? price,
    String? affiliateUrl,
    PointsRuleModel? pointsRule,
    String? status,
    DateTime? createdAt,
    String? description,
    double? rating,
    int? reviewCount,
  }) {
    return ProductModel(
      productId: productId ?? this.productId,
      source: source ?? this.source,
      asin: asin ?? this.asin,
      title: title ?? this.title,
      imageUrl: imageUrl ?? this.imageUrl,
      price: price ?? this.price,
      affiliateUrl: affiliateUrl ?? this.affiliateUrl,
      pointsRule: pointsRule ?? this.pointsRule,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      description: description ?? this.description,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
    );
  }

  @override
  String toString() =>
      'ProductModel(id: $productId, title: $title, points: ${pointsRule.maxPoints})';
}

/// Price model
class PriceModel {
  final String currency; // 'INR', 'USD'
  final double estimatedPrice;

  PriceModel({required this.currency, required this.estimatedPrice});

  Map<String, dynamic> toMap() {
    return {'currency': currency, 'estimated_price': estimatedPrice};
  }

  factory PriceModel.fromMap(Map<String, dynamic> map) {
    return PriceModel(
      currency: map['currency'] ?? 'INR',
      estimatedPrice: (map['estimated_price'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Points rule model
class PointsRuleModel {
  final double pointsPerRupee; // e.g., 0.8
  final int maxPoints; // e.g., 1500

  PointsRuleModel({required this.pointsPerRupee, required this.maxPoints});

  Map<String, dynamic> toMap() {
    return {'points_per_rupee': pointsPerRupee, 'max_points': maxPoints};
  }

  factory PointsRuleModel.fromMap(Map<String, dynamic> map) {
    return PointsRuleModel(
      pointsPerRupee: (map['points_per_rupee'] as num?)?.toDouble() ?? 1.0,
      maxPoints: (map['max_points'] as num?)?.toInt() ?? 1000,
    );
  }

  /// Calculate points for given price
  int calculatePoints(double price) {
    final calculated = (price * pointsPerRupee).round();
    return calculated > maxPoints ? maxPoints : calculated;
  }
}
