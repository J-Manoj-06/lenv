/// Cache entry for download status to prevent redundant file checks
class _CachedStatus {
  final bool isDownloaded;
  final String? localPath;
  final double? imgW;
  final double? imgH;
  final DateTime timestamp;

  _CachedStatus({required this.isDownloaded})
    : localPath = null,
      imgW = null,
      imgH = null,
      timestamp = DateTime.now();

  bool get isStale {
    // Cache is valid for 30 seconds
    return DateTime.now().difference(timestamp).inSeconds > 30;
  }
}
