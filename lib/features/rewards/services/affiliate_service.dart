/// Service for building affiliate URLs
class AffiliateService {
  static const String defaultAffiliateTag = 'lenv-21';

  /// Build Amazon affiliate URL
  static String buildAmazonUrl({
    required String asin,
    String affiliateTag = defaultAffiliateTag,
  }) {
    return 'https://www.amazon.in/dp/$asin/?tag=$affiliateTag';
  }

  /// Build Flipkart affiliate URL
  static String buildFlipkartUrl({
    required String productId,
    String affiliateTag = defaultAffiliateTag,
  }) {
    return 'https://www.flipkart.com/p/$productId?affid=$affiliateTag';
  }

  /// Open affiliate URL externally
  static Future<void> openAffiliateUrl(String? url) async {
    if (url == null || url.isEmpty) {
      throw Exception('URL is empty');
    }
    // Implementation would use url_launcher package
    // await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  /// Build generic affiliate URL
  static String buildUrl({
    required String source,
    required String productId,
    String? asin,
    String affiliateTag = defaultAffiliateTag,
  }) {
    switch (source.toLowerCase()) {
      case 'amazon':
        return buildAmazonUrl(
          asin: asin ?? productId,
          affiliateTag: affiliateTag,
        );
      case 'flipkart':
        return buildFlipkartUrl(
          productId: productId,
          affiliateTag: affiliateTag,
        );
      default:
        return productId; // Return productId as fallback
    }
  }
}
