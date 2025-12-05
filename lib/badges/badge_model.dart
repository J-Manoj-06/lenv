class Badge {
  final String id;
  final String title;
  final String description;
  final String emoji; // emoji icon for universal rendering
  final String category;

  const Badge({
    required this.id,
    required this.title,
    required this.description,
    required this.emoji,
    required this.category,
  });
}
