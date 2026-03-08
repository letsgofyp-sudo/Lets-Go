import 'package:flutter/material.dart';
import '../utils/fare_calculator.dart';

class PakistanFarePreview extends StatefulWidget {
  final String routeId;
  final Map<String, dynamic> vehicle;
  final DateTime departureTime;
  final int totalSeats;
  final List<Map<String, dynamic>> routeStops;

  const PakistanFarePreview({
    super.key,
    required this.routeId,
    required this.vehicle,
    required this.departureTime,
    required this.totalSeats,
    required this.routeStops,
  });

  @override
  State<PakistanFarePreview> createState() => _PakistanFarePreviewState();
}

class _PakistanFarePreviewState extends State<PakistanFarePreview> {
  Map<String, dynamic>? _fareCalculation;
  bool _isCalculating = false;

  @override
  void initState() {
    super.initState();
    _calculateFare();
  }

  void _calculateFare() {
    setState(() {
      _isCalculating = true;
    });

    try {
      // Use hybrid calculator for instant results (no bulk discounts)
      final result = FareCalculator.calculateHybridFare(
        routeStops: widget.routeStops,
        fuelType: widget.vehicle['fuel_type'] ?? 'Petrol',
        vehicleType: widget.vehicle['vehicle_type'] ?? 'FW',
        departureTime: widget.departureTime,
        totalSeats: widget.totalSeats,
      );

      setState(() {
        _fareCalculation = result;
        _isCalculating = false;
      });
    } catch (e) {
      setState(() {
        _fareCalculation = {
          'base_fare': 100.0,
          'calculation_breakdown': {'error': 'Calculation failed: $e'}
        };
        _isCalculating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCalculating) {
      return Card(
        margin: const EdgeInsets.all(8.0),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Calculating fare...'),
            ],
          ),
        ),
      );
    }

    if (_fareCalculation == null) {
      return Card(
        margin: const EdgeInsets.all(8.0),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('Unable to calculate fare'),
        ),
      );
    }

    final fare = _fareCalculation!['base_fare'] as double;

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '💰 Dynamic Fare Calculation',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _calculateFare,
                  tooltip: 'Recalculate Fare',
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Total Fare Display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                children: [
                  const Text(
                    'Total Fare',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.green,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Rs. ${fare.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            const SizedBox(height: 12),
            
            // Info Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Fare calculated locally for instant results. Prices are based on current Pakistan market conditions.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

} 