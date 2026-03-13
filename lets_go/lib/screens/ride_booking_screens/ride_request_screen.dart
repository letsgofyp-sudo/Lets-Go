import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../controllers/ride_booking_controllers/ride_request_controller.dart';
import '../../utils/map_util.dart';

class RideRequestScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String tripId;
  final Map<String, dynamic> rideData;

  const RideRequestScreen({
    super.key,
    required this.userData,
    required this.tripId,
    required this.rideData,
  });

  @override
  State<RideRequestScreen> createState() => _RideRequestScreenState();
}

class _RideRequestScreenState extends State<RideRequestScreen> {
  late RideRequestController _controller;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  void _initializeController() {
    _controller = RideRequestController(
      onStateChanged: () {
        if (!mounted) return;
        setState(() {});
      },
      onError: (message) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: const Color(0xFFE53935)),
          );
        }
      },
      onSuccess: (message) {
        if (!mounted) return;
        // Show quick success feedback then navigate to Home with a slight delay
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ride requested successfully!'),
            backgroundColor: Color(0xFF4CAF50),
            duration: Duration(milliseconds: 1200),
          ),
        );
        // Prevent any further state updates from controller after leaving the page
        _controller.onStateChanged = null;
        // Navigate to Home by replacing the entire stack to avoid popping to Login
        Future.delayed(const Duration(milliseconds: 400), () {
          if (!mounted) return;
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/home',
            (route) => false,
            arguments: widget.userData,
          );
        });
      },
      onInfo: (message) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: const Color(0xFF26A69A)),
          );
        }
      },
    );

    // Initialize controller with ride data
    debugPrint('DEBUG: RideRequestScreen - widget.rideData keys: ${widget.rideData.keys.toList()}');
    debugPrint('DEBUG: RideRequestScreen - widget.rideData: ${widget.rideData}');
    _controller.initializeWithRideData(widget.rideData);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Request Ride',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Card(
              color: const Color(0xFFE0F2F1), // Lighter teal shade
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: const Color(0xFF00897B)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Request Your Ride',
                            style: TextStyle(
                              color: Colors.teal.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Fill in the details below to request your ride',
                            style: TextStyle(
                              color: Colors.teal.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Route Map
            if (_controller.routePoints.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Route Overview',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 200,
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: _controller.routePoints.isNotEmpty 
                                ? _controller.routePoints.first 
                                : const LatLng(0, 0),
                            initialZoom: 12.0,
                          ),
                          children: [
                            MapUtil.buildDefaultTileLayer(userAgentPackageName: 'com.example.lets_go'),
                            MarkerLayer(
                              markers: _controller.stopPoints.asMap().entries.map((entry) {
                                final index = entry.key;
                                final point = entry.value;
                                final locationName = index < _controller.locationNames.length
                                    ? _controller.locationNames[index]
                                    : null;
                                // Convert 0-based index to 1-based stop order used by controller
                                final stopOrder = index + 1;
                                // Determine color and icon based on selected range
                                Color markerColor;
                                IconData markerIcon;
                                if (stopOrder == _controller.selectedFromStop) {
                                  markerColor = Colors.green; // pickup
                                  markerIcon = Icons.trip_origin;
                                } else if (stopOrder == _controller.selectedToStop) {
                                  markerColor = Colors.red; // drop-off
                                  markerIcon = Icons.place;
                                } else if (stopOrder > _controller.selectedFromStop && stopOrder < _controller.selectedToStop) {
                                  markerColor = Colors.orange; // in-between selected segment
                                  markerIcon = Icons.location_on;
                                } else {
                                  markerColor = Colors.grey; // out-of-segment
                                  markerIcon = Icons.location_on;
                                }
                                return Marker(
                                  width: 30,
                                  height: 30,
                                  point: point,
                                  child: Stack(
                                    children: [
                                      Icon(
                                        markerIcon,
                                        color: markerColor,
                                        size: 30,
                                      ),
                                      if (locationName != null)
                                        Positioned(
                                          bottom: -2,
                                          left: 0,
                                          right: 0,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 2,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black87,
                                              borderRadius: BorderRadius.circular(2),
                                            ),
                                            child: Text(
                                              locationName.length > 6
                                                  ? '${locationName.substring(0, 6)}...'
                                                  : locationName,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 8,
                                              ),
                                              textAlign: TextAlign.center,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                            // Draw interpolated route line
                            if (_controller.routePoints.length > 1)
                              MapUtil.buildPolylineLayerFromPolylines(
                                polylines: [
                                  MapUtil.polyline(
                                    points: _controller.getInterpolatedRoutePoints(),
                                    color: Colors.blue,
                                    strokeWidth: 3,
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            const SizedBox(height: 20),

            // Trip Summary Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trip Summary',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoTile(
                            icon: Icons.calendar_today,
                            title: 'Date',
                            subtitle: _controller.getFormattedTripDate(),
                          ),
                        ),
                        Expanded(
                          child: _buildInfoTile(
                            icon: Icons.access_time,
                            title: 'Trip Time',
                            subtitle: _controller.getEstimatedTimeRange(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoTile(
                            icon: Icons.route,
                            title: 'Route',
                            subtitle: _controller.getRouteSummary(),
                          ),
                        ),
                        Expanded(
                          child: _buildInfoTile(
                            icon: Icons.timer,
                            title: 'Duration',
                            subtitle: _controller.getFormattedDuration(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoTile(
                            icon: Icons.attach_money,
                            title: 'Base Fare',
                            subtitle: '₨${_controller.getBaseFare()}',
                          ),
                        ),
                        Expanded(
                          child: _buildInfoTile(
                            icon: Icons.schedule,
                            title: 'Pickup Time',
                            subtitle: _controller.getEstimatedDepartureTime(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Booking Form Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Booking Details',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // From Stop Selection
                    Text(
                      'Pickup Location',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: _controller.selectedFromStop,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        isDense: true,
                      ),
                      items: _controller.getFromStopOptions().map<DropdownMenuItem<int>>((stop) {
                        return DropdownMenuItem<int>(
                          value: stop['order'] as int,
                          child: Text(
                            stop['display_name'] as String,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: const TextStyle(fontSize: 13),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          _controller.updateFromStop(value);
                        }
                      },
                    ),

                    const SizedBox(height: 16),

                    // Dynamic Price Update Indicator
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calculate_outlined, color: Colors.green.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Dynamic Pricing Active',
                                  style: TextStyle(
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  'Price: ₨${_controller.getOriginalPricePerSeat()} per seat • Duration: ${_controller.getFormattedDuration()}',
                                  style: TextStyle(
                                    color: Colors.green.shade600,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Pickup: ${_controller.getEstimatedDepartureTime()} • Arrival: ${_controller.getEstimatedArrivalTime()}',
                                  style: TextStyle(
                                    color: Colors.green.shade600,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // To Stop Selection
                    Text(
                      'Drop-off Location',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: _controller.selectedToStop,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        isDense: true,
                      ),
                      items: _controller.getToStopOptions().map<DropdownMenuItem<int>>((stop) {
                        return DropdownMenuItem<int>(
                          value: stop['order'] as int,
                          child: Text(
                            stop['display_name'] as String,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: const TextStyle(fontSize: 13),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          _controller.updateToStop(value);
                        }
                      },
                    ),

                    const SizedBox(height: 16),

                    // Seat and Gender Selection
                    Text(
                      'Seat and Gender Selection',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    
                    // Male Seats
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.male,
                            color: Colors.blue.shade700,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Male Seats',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                Text(
                                  'Select number of male passengers',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                onPressed: _controller.maleSeats > 0
                                    ? () => _controller.updateMaleSeats(_controller.maleSeats - 1)
                                    : null,
                                icon: Icon(
                                  Icons.remove_circle_outline,
                                  color: _controller.maleSeats > 0 ? Colors.red.shade600 : Colors.grey.shade400,
                                ),
                              ),
                              Container(
                                width: 40,
                                alignment: Alignment.center,
                                child: Text(
                                  '${_controller.maleSeats}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: _controller.canAddMaleSeats()
                                    ? () => _controller.updateMaleSeats(_controller.maleSeats + 1)
                                    : null,
                                icon: Icon(
                                  Icons.add_circle_outline,
                                  color: _controller.canAddMaleSeats() ? Colors.green.shade600 : Colors.grey.shade400,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Female Seats
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.female,
                            color: Colors.pink.shade700,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Female Seats',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                Text(
                                  'Select number of female passengers',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                onPressed: _controller.femaleSeats > 0
                                    ? () => _controller.updateFemaleSeats(_controller.femaleSeats - 1)
                                    : null,
                                icon: Icon(
                                  Icons.remove_circle_outline,
                                  color: _controller.femaleSeats > 0 ? Colors.red.shade600 : Colors.grey.shade400,
                                ),
                              ),
                              Container(
                                width: 40,
                                alignment: Alignment.center,
                                child: Text(
                                  '${_controller.femaleSeats}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: _controller.canAddFemaleSeats()
                                    ? () => _controller.updateFemaleSeats(_controller.femaleSeats + 1)
                                    : null,
                                icon: Icon(
                                  Icons.add_circle_outline,
                                  color: _controller.canAddFemaleSeats() ? Colors.green.shade600 : Colors.grey.shade400,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Total Seats Summary
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event_seat, color: Colors.blue.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total Seats: ${_controller.getTotalSeats()}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  'Male: ${_controller.maleSeats}, Female: ${_controller.femaleSeats}',
                                  style: TextStyle(
                                    color: Colors.blue.shade700,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Price Negotiation Section
                    if (_controller.getIsPriceNegotiable()) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.handshake, color: Colors.orange.shade700),
                                const SizedBox(width: 8),
                                Text(
                                  'Price Negotiation',
                                  style: TextStyle(
                                    color: Colors.orange.shade700,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'The driver is open to price negotiation. You can propose a different price.',
                              style: TextStyle(
                                color: Colors.orange.shade600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            // Original Price
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Original Price per Seat:',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '₨${_controller.getOriginalPricePerSeat()}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            
                            // Price Slider
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Your Offer per Seat:',
                                      style: const TextStyle(fontWeight: FontWeight.w500),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '₨${_controller.getFinalPricePerSeat()}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange.shade700,
                                        fontSize: 14,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.end,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                
                                // Price Range Info
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Min: ₨${_controller.getMinPrice()}',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 11,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'Max: ₨${_controller.getMaxPrice()}',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 11,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.end,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                
                                // Bargaining Text Input
                                TextField(
                                  controller: _controller.priceController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    border: const OutlineInputBorder(),
                                    labelText: 'Enter your offer (PKR)',
                                    hintText: '₨0 to ₨${_controller.getMaxPrice()}',
                                    suffixText: 'PKR',
                                    helperText: 'Maximum: ₨${_controller.getMaxPrice()} (Driver\'s price)',
                                    errorText: _controller.getFinalPricePerSeat() > _controller.getMaxPrice() 
                                        ? 'Cannot exceed ₨${_controller.getMaxPrice()}'
                                        : null,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  ),
                                  onChanged: (value) {
                                    _controller.updateProposedPrice(value);
                                  },
                                ),
                                
                                const SizedBox(height: 8),
                                
                                // Price Validation Message
                                if (_controller.getFinalPricePerSeat() < _controller.getMinPrice() || 
                                    _controller.getFinalPricePerSeat() > _controller.getMaxPrice())
                                  Text(
                                    'Price must be between ₨${_controller.getMinPrice()} and ₨${_controller.getMaxPrice()}',
                                    style: TextStyle(
                                      color: Colors.red.shade600,
                                      fontSize: 11,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            
                            // Savings
                            if (_controller.getSavings() > 0) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Potential Savings:',
                                    style: const TextStyle(fontWeight: FontWeight.w500),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '-₨${_controller.getSavings()}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.end,
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Special Requests
                    Text(
                      'Special Requests (Optional)',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      maxLines: 3,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Any special requests or notes...',
                      ),
                      onChanged: _controller.updateSpecialRequests,
                    ),

                    const SizedBox(height: 20),

                    // Price Summary
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildInfoTile(
                                  icon: Icons.route,
                                  title: 'Route',
                                  subtitle: _controller.getRouteSummary(),
                                ),
                              ),
                              Expanded(
                                child: _buildInfoTile(
                                  icon: Icons.attach_money,
                                  title: 'Base Fare',
                                  subtitle: '₨${_controller.getBaseFare()}',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildInfoTile(
                                  icon: Icons.location_on,
                                  title: 'Selected Route',
                                  subtitle: _controller.getSelectedRouteSummary(),
                                ),
                              ),
                              Expanded(
                                child: _buildInfoTile(
                                  icon: Icons.calculate,
                                  title: 'Calculated Price',
                                  subtitle: '₨${_controller.getOriginalPricePerSeat()}',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildInfoTile(
                                  icon: Icons.attach_money,
                                  title: 'Price per seat',
                                  subtitle: '₨${_controller.getFinalPricePerSeat()}',
                                ),
                              ),
                              Expanded(
                                child: _buildInfoTile(
                                  icon: Icons.event_seat,
                                  title: 'Number of seats',
                                  subtitle: '${_controller.getTotalSeats()}',
                                ),
                              ),
                            ],
                          ),
                          if (_controller.getIsPriceNegotiable() && _controller.getSavings() > 0) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildInfoTile(
                                    icon: Icons.savings,
                                    title: 'Total savings',
                                    subtitle: '-₨${_controller.getSavings() * _controller.getTotalSeats()}',
                                  ),
                                ),
                                Expanded(
                                  child: Container(), // Empty space for alignment
                                ),
                              ],
                            ),
                          ],
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total Price:',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              Text(
                                '₨${_controller.calculateTotalFare()}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Request Ride Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _controller.isBookingInProgress
                            ? null
                            : _controller.requestRideBooking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _controller.isBookingInProgress
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text('Processing...'),
                                ],
                              )
                            : const Text(
                                'Request Ride',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // Helper method to build info tiles
  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
