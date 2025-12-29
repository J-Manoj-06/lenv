/// Cache entry for download status to prevent redundant file checks
class _CachedStatus {
  final bool isDownloaded;
  final String? localPath;
  final double? imgW;
  final double? imgH;
  final DateTime timestamp;

  _CachedStatus({
    required this.isDownloaded,
    this.localPath,
    this.imgW,
    this.imgH,
  }) : timestamp = DateTime.now();

  bool get isStale {
    // Cache is valid for 30 seconds
    return DateTime.now().difference(timestamp).inSeconds > 30;
  }
}
