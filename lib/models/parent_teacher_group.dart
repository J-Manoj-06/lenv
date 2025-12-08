class ParentTeacherGroup {
  final String id; // e.g., schoolCode_class_section
  final String name; // e.g., "Grade 10 - A Parents & Teachers"
  final String className;
  final String section;
  final String schoolCode;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final int memberCount;

  ParentTeacherGroup({
    required this.id,
    required this.name,
    required this.className,
    required this.section,
    required this.schoolCode,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.memberCount,
  });

  factory ParentTeacherGroup.empty({
    required String id,
    required String name,
    required String className,
    required String section,
    required String schoolCode,
  }) {
    return ParentTeacherGroup(
      id: id,
      name: name,
      className: className,
      section: section,
      schoolCode: schoolCode,
      lastMessage: '',
      lastMessageAt: null,
      memberCount: 0,
    );
  }
}
