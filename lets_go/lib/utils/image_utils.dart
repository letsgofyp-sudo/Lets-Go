import '../constants.dart';
class ImageUtils {
  static const String baseUrl = url;
  
  /// Validates if a URL is properly formatted for network images
  static bool isValidImageUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    
    // Check if it's a proper HTTP/HTTPS URL
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return false;
    }
    
    // Check if it's not a file:// URL (which causes the error)
    if (url.startsWith('file://')) {
      return false;
    }
    
    return true;
  }
  
  /// Ensures a URL is properly formatted for the backend
  static String? ensureValidImageUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    
    // If it's already a valid URL, return as is
    if (isValidImageUrl(url)) {
      return url;
    }
    
    // If it's a relative path, make it absolute
    if (url.startsWith('/')) {
      return '$baseUrl$url';
    }
    
    // If it's a file:// URL, return null to use fallback
    if (url.startsWith('file://')) {
      return null;
    }
    
    return null;
  }
  
  /// Gets a fallback URL for debugging purposes
  static String getFallbackImageUrl(String type, int id, String field) {
    return '$baseUrl/lets_go/${type}_image/$id/$field/';
  }
}
