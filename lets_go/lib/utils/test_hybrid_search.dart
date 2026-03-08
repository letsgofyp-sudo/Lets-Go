import 'package:flutter/foundation.dart';
import '../services/places_service.dart';

// Test the hybrid search functionality
class HybridSearchTest {
  static Future<void> testPlacesService() async {
    debugPrint('Testing PlacesService...');
    
    // Load places
    await PlacesService.loadPlaces();
    
    // Test search functionality
    final testQueries = ['lahore', 'karachi', 'islamabad', 'comsats', 'airport'];
    
    for (final query in testQueries) {
      debugPrint('\nSearching for: $query');
      final results = PlacesService.searchLocalPlaces(query, null);
      debugPrint('Found ${results.length} results:');
      
      for (final result in results.take(3)) {
        debugPrint('  - ${result['mainText']} (${result['source']})');
      }
    }
    
    // Test place types
    final types = ['city', 'university', 'airport', 'landmark'];
    for (final type in types) {
      final places = PlacesService.getPlacesByType(type);
      debugPrint('\nPlaces of type "$type": ${places.length}');
    }
    
    debugPrint('\nHybrid search test completed successfully!');
  }
} 