class ProductModel {
  final String id;
  final String name;
  final String category; // e.g., books, kits, stationery
  final String imageUrl;
  final String storeName; // e.g., Amazon, Bookworm Store
  final String amazonLink; // affiliate link or stored link
  final double price;
  final int pointsRequired;
  final double rating;

  ProductModel({
    required this.id,
    required this.name,
    required this.category,
    required this.imageUrl,
    required this.storeName,
    required this.amazonLink,
    required this.price,
    required this.pointsRequired,
    required this.rating,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json, {String? id}) {
    return ProductModel(
      id: id ?? (json['id'] as String? ?? ''),
      name: (json['name'] as String? ?? ''),
      category: (json['category'] as String? ?? 'all'),
      imageUrl: (json['imageUrl'] as String? ?? ''),
      storeName: (json['storeName'] as String? ?? 'Amazon'),
      amazonLink: (json['amazonLink'] as String? ?? ''),
      price: (json['price'] as num? ?? 0).toDouble(),
      pointsRequired: (json['pointsRequired'] as num? ?? 0).toInt(),
      rating: (json['rating'] as num? ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'imageUrl': imageUrl,
    'storeName': storeName,
    'amazonLink': amazonLink,
    'price': price,
    'pointsRequired': pointsRequired,
    'rating': rating,
  };
}
