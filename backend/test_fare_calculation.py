#!/usr/bin/env python3
"""
Test script for Pakistan-specific fare calculation system
"""

import os
import sys
import django
from decimal import Decimal

# Add the backend directory to Python path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'backend.settings')
django.setup()

from lets_go.models import Route, RouteStop, Vehicle, UsersData
from backend.lets_go.views_authentication import calculate_pakistan_fare
from datetime import time

def create_test_data():
    """Create test data for fare calculation"""
    print("Creating test data...")
    
    # Create a test user
    user, created = UsersData.objects.get_or_create(
        username='test_driver',
        defaults={
            'name': 'Test Driver',
            'email': 'test@example.com',
            'password': 'testpassword123',
            'address': 'Test Address',
            'phone_no': '+923001234567',
            'cnic_no': '12345-1234567-1',
            'gender': 'male',
            'status': 'VERIFIED'
        }
    )
    
    # Create a test vehicle
    vehicle, created = Vehicle.objects.get_or_create(
        plate_number='ABC-1234',
        defaults={
            'owner': user,
            'model_number': 'Test Model',
            'company_name': 'Test Company',
            'vehicle_type': 'FW',
            'color': 'White',
            'seats': 4,
            'fuel_type': 'Petrol'
        }
    )
    
    # Create a test route
    route, created = Route.objects.get_or_create(
        route_id='TEST001',
        defaults={
            'route_name': 'Test Route - Islamabad to Lahore',
            'route_description': 'Test route for fare calculation',
            'total_distance_km': Decimal('300.0'),
            'estimated_duration_minutes': 240
        }
    )
    
    # Create route stops
    stops_data = [
        {'name': 'Islamabad', 'order': 1, 'lat': 33.6844, 'lng': 73.0479},
        {'name': 'Rawalpindi', 'order': 2, 'lat': 33.5651, 'lng': 73.0169},
        {'name': 'Gujranwala', 'order': 3, 'lat': 32.1877, 'lng': 74.1945},
        {'name': 'Lahore', 'order': 4, 'lat': 31.5204, 'lng': 74.3587},
    ]
    
    for stop_data in stops_data:
        RouteStop.objects.get_or_create(
            route=route,
            stop_order=stop_data['order'],
            defaults={
                'stop_name': stop_data['name'],
                'latitude': Decimal(str(stop_data['lat'])),
                'longitude': Decimal(str(stop_data['lng'])),
                'address': f'Address for {stop_data["name"]}',
                'estimated_time_from_start': stop_data['order'] * 60
            }
        )
    
    return route, vehicle, user

def test_fare_calculation():
    """Test the fare calculation system"""
    print("\n" + "="*60)
    print("PAKISTAN-SPECIFIC FARE CALCULATION TEST")
    print("="*60)
    
    # Create test data
    route, vehicle, user = create_test_data()
    
    # Test scenarios
    test_scenarios = [
        {
            'name': 'Peak Hour (Morning Rush)',
            'time': time(8, 0),  # 8:00 AM
            'seats': 1,
            'description': 'Single passenger during peak hours'
        },
        {
            'name': 'Off-Peak Hour',
            'time': time(14, 0),  # 2:00 PM
            'seats': 1,
            'description': 'Single passenger during off-peak hours'
        },
        {
            'name': 'Bulk Booking (4 seats)',
            'time': time(10, 0),  # 10:00 AM
            'seats': 4,
            'description': 'Family booking with 4 seats'
        },
        {
            'name': 'Late Night',
            'time': time(23, 0),  # 11:00 PM
            'seats': 2,
            'description': 'Late night travel with 2 passengers'
        }
    ]
    
    for scenario in test_scenarios:
        print(f"\n📊 {scenario['name']}")
        print(f"   Description: {scenario['description']}")
        print(f"   Time: {scenario['time'].strftime('%H:%M')}")
        print(f"   Seats: {scenario['seats']}")
        print("-" * 40)
        
        # Calculate fare
        result = calculate_pakistan_fare(
            route=route,
            vehicle=vehicle,
            departure_time=scenario['time'],
            total_seats=scenario['seats']
        )
        
        fare = result['base_fare']
        breakdown = result['calculation_breakdown']
        
        print(f"   💰 Total Fare: ₨{fare:.2f}")
        print(f"   📏 Distance: {breakdown['total_distance_km']:.1f} km")
        print(f"   ⛽ Fuel Type: {breakdown['fuel_type']}")
        print(f"   🚗 Vehicle Multiplier: {breakdown['vehicle_multiplier']:.2f}x")
        print(f"   ⏰ Time Multiplier: {breakdown['time_multiplier']:.2f}x")
        print(f"   🪑 Seat Factor: {breakdown['seat_factor']:.2f}x")
        print(f"   📍 Distance Factor: {breakdown['distance_factor']:.2f}x")
        
        if breakdown['is_peak_hour']:
            print(f"   🚦 Peak Hour: YES (+30%)")
        
        if breakdown['bulk_discount'] > 0:
            print(f"   🎁 Bulk Discount: -{breakdown['bulk_discount']:.1f}%")
        
        print(f"   ⛽ Fuel Cost: ₨{breakdown['fuel_cost']:.2f}")
        print(f"   💵 Profit Margin: ₨{breakdown['profit_margin']:.2f}")
        print(f"   📈 Profit %: {breakdown['profit_percentage']:.1f}%")
        
        print("-" * 40)
    
    # Test different vehicle types
    print("\n🚗 VEHICLE TYPE COMPARISON")
    print("-" * 40)
    
    vehicle_types = [
        {'type': 'TW', 'fuel': 'Petrol', 'seats': 2, 'name': 'Motorcycle'},
        {'type': 'FW', 'fuel': 'Petrol', 'seats': 4, 'name': 'Car (Petrol)'},
        {'type': 'FW', 'fuel': 'Diesel', 'seats': 4, 'name': 'Car (Diesel)'},
        {'type': 'FW', 'fuel': 'CNG', 'seats': 4, 'name': 'Car (CNG)'},
        {'type': 'FW', 'fuel': 'Electric', 'seats': 4, 'name': 'Car (Electric)'},
    ]
    
    for v_type in vehicle_types:
        # Update vehicle for this test
        vehicle.vehicle_type = v_type['type']
        vehicle.fuel_type = v_type['fuel']
        vehicle.seats = v_type['seats']
        vehicle.save()
        
        result = calculate_pakistan_fare(
            route=route,
            vehicle=vehicle,
            departure_time=time(10, 0),
            total_seats=1
        )
        
        print(f"   {v_type['name']:15} | ₨{result['base_fare']:8.2f} | {result['calculation_breakdown']['fuel_type']:8} | {result['calculation_breakdown']['vehicle_multiplier']:.2f}x")
    
    print("\n✅ Fare calculation test completed successfully!")
    print("\n📋 SUMMARY:")
    print("   • Dynamic fare calculation based on Pakistan's current fuel prices")
    print("   • Peak hour surcharges (30% during rush hours)")
    print("   • Vehicle type multipliers (Two-wheelers 30% cheaper)")
    print("   • Fuel type optimization (CNG cheapest, Electric most efficient)")
    print("   • Bulk booking discounts (up to 18% for 6+ seats)")
    print("   • Distance-based pricing (short trips premium, long trips discount)")
    print("   • Transparent fuel cost and profit margin calculations")

if __name__ == '__main__':
    test_fare_calculation() 