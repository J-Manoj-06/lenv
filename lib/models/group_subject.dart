class GroupSubject {
  final String id;
  final String name;
  final String teacherName;
  final String icon;

  GroupSubject({
    required this.id,
    required this.name,
    required this.teacherName,
    required this.icon,
  });

  factory GroupSubject.fromFirestore(Map<String, dynamic> data, String id) {
    return GroupSubject(
      id: id,
      name: data['name'] ?? '',
      teacherName: data['teacherName'] ?? '',
      icon: data['icon'] ?? '📚',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {'name': name, 'teacherName': teacherName, 'icon': icon};
  }
}
