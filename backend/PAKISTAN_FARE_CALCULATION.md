# 🇵🇰 Pakistan-Specific Dynamic Fare Calculation System

## Overview

The Let's Go application now features a sophisticated, Pakistan-specific dynamic fare calculation system that considers current fuel prices, vehicle types, peak hours, and market conditions to provide fair and competitive pricing.

## 🚀 Key Features

### 1. **Current Pakistan Fuel Prices (2025)**
- **Petrol**: ₨275/Liter
- **Diesel**: ₨285/Liter  
- **CNG**: ₨230/Kg
- **Electric**: ₨25/kWh (charging cost)
- **Hybrid**: ₨275/Liter (petrol component)

### 2. **Dynamic Pricing Factors**

#### **Base Rates (PKR per km)**
- **Petrol**: ₨22.00/km
- **Diesel**: ₨20.00/km (more efficient)
- **CNG**: ₨16.00/km (cheapest fuel)
- **Electric**: ₨14.00/km (lowest operating cost)
- **Hybrid**: ₨18.00/km

#### **Vehicle Type Multipliers**
- **Two-Wheelers (TW)**: 0.7x (30% cheaper)
- **Four-Wheelers (FW)**: 1.0x (standard rate)

#### **Peak Hour Surcharges**
- **Peak Hours**: 1.30x (30% higher)
  - Morning: 7:00 AM - 10:00 AM
  - Evening: 5:00 PM - 8:00 PM
- **Off-Peak**: 1.0x (standard rate)

#### **Seat Capacity Factors**
- **Small (1-4 seats)**: 1.0x
- **Medium (5-7 seats)**: 1.10x (10% higher)
- **Large (8+ seats)**: 1.20x (20% higher)

#### **Distance-Based Pricing**
- **Short trips (≤5 km)**: 1.25x (25% premium)
- **Standard (6-15 km)**: 1.0x
- **Medium (16-30 km)**: 0.92x (8% discount)
- **Long trips (>30 km)**: 0.85x (15% discount)

#### **Bulk Booking Discounts**
- **1 seat**: No discount
- **2 seats**: 5% discount
- **3 seats**: 8% discount
- **4 seats**: 12% discount
- **5 seats**: 15% discount
- **6+ seats**: 18% discount

### 3. **Minimum Fares**
- **Two-Wheelers**: ₨100 minimum
- **Four-Wheelers**: ₨150 minimum

## 🧮 Calculation Formula

```
Final Fare = Base Rate × Distance × Vehicle Multiplier × Time Multiplier × Seat Factor × Distance Factor × (1 - Bulk Discount)
```

### Example Calculation
For a 20km trip in a petrol car during peak hours with 2 passengers:

```
Base Rate: ₨22.00/km
Distance: 20 km
Vehicle Multiplier: 1.0x (Four-wheeler)
Time Multiplier: 1.30x (Peak hour)
Seat Factor: 1.0x (Standard seats)
Distance Factor: 0.92x (Medium trip discount)
Bulk Discount: 0.05 (5% for 2 seats)

Fare = 22 × 20 × 1.0 × 1.30 × 1.0 × 0.92 × (1 - 0.05)
Fare = ₨499.12
```

## 🔧 API Endpoints

### 1. Calculate Fare
**POST** `/lets_go/calculate_fare/`

**Request Body:**
```json
{
  "route_id": "R001",
  "vehicle_id": 1,
  "departure_time": "08:30",
  "total_seats": 2
}
```

**Response:**
```json
{
  "success": true,
  "fare": 499.12,
  "breakdown": {
    "total_distance_km": 20.0,
    "base_rate_per_km": 22.0,
    "vehicle_multiplier": 1.0,
    "time_multiplier": 1.30,
    "seat_factor": 1.0,
    "distance_factor": 0.92,
    "is_peak_hour": true,
    "bulk_discount": 5.0,
    "fuel_type": "Petrol",
    "fuel_consumed": 1.67,
    "fuel_cost": 458.33,
    "fuel_efficiency_km_per_unit": 12.0,
    "profit_margin": 40.79,
    "profit_percentage": 8.2,
    "calculation_formula": "Base Rate (22.00 PKR/km) × Distance (20.0km) × Vehicle (1.0) × Time (1.30) × Seats (1.0) × Distance Factor (0.92) × Discount (0.95)"
  }
}
```

### 2. Create Trip (with Dynamic Fare)
**POST** `/lets_go/create_trip/`

**Request Body:**
```json
{
  "route_id": "R001",
  "vehicle_id": 1,
  "driver_id": 1,
  "trip_date": "2025-01-15",
  "departure_time": "08:30",
  "total_seats": 4,
  "notes": "Optional trip notes"
}
```

**Response:**
```json
{
  "success": true,
  "trip_id": "T123-2025-01-15-0830",
  "calculated_fare": 499.12,
  "fare_breakdown": {
    // Same breakdown as above
  }
}
```

## 📱 Flutter Integration

### 1. API Service
```dart
// Calculate fare
final result = await ApiService.calculateFare(
  routeId: 'R001',
  vehicleId: 1,
  departureTime: '08:30',
  totalSeats: 2,
);

// Create trip with dynamic fare
final response = await ApiService.createTrip(
  routeId: 'R001',
  vehicleId: 1,
  driverId: 1,
  tripDate: '2025-01-15',
  departureTime: '08:30',
  totalSeats: 4,
  notes: 'Optional notes',
);
```

### 2. Fare Preview Widget
```dart
PakistanFarePreview(
  routeId: 'R001',
  vehicleId: 1,
  departureTime: '08:30',
  totalSeats: 2,
)
```

## 🧪 Testing

Run the test script to verify the fare calculation system:

```bash
cd backend
python test_fare_calculation.py
```

This will test various scenarios including:
- Peak vs off-peak hours
- Different vehicle types
- Bulk booking discounts
- Fuel type comparisons

## 📊 Fuel Efficiency Standards

| Fuel Type | Efficiency | Unit |
|-----------|------------|------|
| Petrol | 12.0 km/liter | km/L |
| Diesel | 15.0 km/liter | km/L |
| CNG | 18.0 km/kg | km/kg |
| Electric | 8.0 km/kWh | km/kWh |
| Hybrid | 14.0 km/liter | km/L |

## 🎯 Business Benefits

### For Drivers
- **Fair Pricing**: Transparent calculation based on actual costs
- **Profit Optimization**: Automatic profit margin calculations
- **Market Competitiveness**: Dynamic pricing based on demand

### For Passengers
- **Transparent Pricing**: Clear breakdown of fare components
- **Fair Rates**: No arbitrary pricing
- **Bulk Discounts**: Savings for group bookings

### For Platform
- **Market Responsive**: Adapts to fuel price changes
- **Scalable**: Easy to update rates and factors
- **Data-Driven**: Insights into profitability and demand

## 🔄 Future Enhancements

1. **Real-time Fuel Prices**: Integration with fuel price APIs
2. **Weather Impact**: Pricing adjustments for weather conditions
3. **Event-based Pricing**: Special rates during events/festivals
4. **Loyalty Programs**: Additional discounts for regular users
5. **Route Optimization**: Dynamic pricing based on route popularity

## 📞 Support

For questions or issues with the fare calculation system, please contact the development team or refer to the API documentation. 