/// Model for incoming shared content from other apps
class IncomingShareData {
  final ShareContentType type;
  final String? text;
  final List<String> files;
  final List<String> mimeTypes;

  IncomingShareData({
    required this.type,
    this.text,
    this.files = const [],
    this.mimeTypes = const [],
  });

  bool get isEmpty => text == null && files.isEmpty;

  bool get hasText => text != null && text!.isNotEmpty;

  bool get hasFiles => files.isNotEmpty;

  @override
  String toString() {
    return 'IncomingShareData(type: $type, text: $text, files: ${files.length}, mimeTypes: $mimeTypes)';
  }
}

enum ShareContentType {
  text,
  image,
  audio,
  file,
  mixed, // Multiple types
}
