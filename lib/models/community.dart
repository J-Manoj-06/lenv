class Community {
  final String id;
  final String name;
  final String description;
  final String icon;

  Community({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
  });

  factory Community.fromFirestore(Map<String, dynamic> data, String id) {
    return Community(
      id: id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      icon: data['icon'] ?? '🌐',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {'name': name, 'description': description, 'icon': icon};
  }
}
