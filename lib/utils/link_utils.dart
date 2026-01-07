/// Utility functions for link detection and processing
class LinkUtils {
  /// Add https:// to bare domains that don't have a protocol
  /// Examples:
  ///   "google.com" -> "https://google.com"
  ///   "www.google.com" -> "https://www.google.com"
  ///   "https://google.com" -> "https://google.com" (unchanged)
  static String addProtocolToBareUrls(String text) {
    // Regex pattern to detect bare domains (without http://, https://, or www. prefix)
    // Matches: word characters followed by a dot and TLD (2+ chars)
    // Excludes URLs that already have http://, https://, or www.
    final bareUrlPattern = RegExp(
      r'\b(?<!/)(?<!:)(?<!//)(?<!https://)(?<!http://)(?<!www\.)([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}\b',
      caseSensitive: false,
    );

    // Replace bare URLs with https:// prepended
    return text.replaceAllMapped(bareUrlPattern, (match) {
      final url = match.group(0)!;
      // Make sure we don't double-add protocol
      if (url.startsWith('http://') || url.startsWith('https://')) {
        return url;
      }
      return 'https://$url';
    });
  }
}
