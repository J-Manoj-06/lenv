class SchoolModel {
  final String id;
  final String name;
  final String? address;

  SchoolModel({required this.id, required this.name, this.address});

  factory SchoolModel.fromMap(String id, Map<String, dynamic> data) {
    return SchoolModel(
      id: id,
      name: (data['name'] ?? '').toString(),
      address: data['address']?.toString(),
    );
  }
}
