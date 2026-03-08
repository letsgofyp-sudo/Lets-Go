#!/usr/bin/env python
"""
Test script to verify image serving functionality
"""
import os
import sys
import django

# Add the backend directory to Python path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Set up Django environment
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'backend.settings')
django.setup()

from lets_go.models import UsersData, Vehicle

def test_user_images():
    """Test if user images exist in database"""
    print("=== Testing User Images ===")
    
    try:
        # Get the first user
        user = UsersData.objects.first()
        if not user:
            print("No users found in database")
            return
        
        print(f"User ID: {user.id}")
        print(f"User Name: {user.name}")
        print(f"User Email: {user.email}")
        
        # Check image fields
        image_fields = [
            'profile_photo', 'live_photo',
            'cnic_front_image', 'cnic_back_image',
            'driving_license_front', 'driving_license_back',
            'accountqr'
        ]
        
        for field in image_fields:
            image_data = getattr(user, field)
            if image_data:
                print(f"✓ {field}: {len(image_data)} bytes")
            else:
                print(f"✗ {field}: None")
                
    except Exception as e:
        print(f"Error testing user images: {str(e)}")

def test_vehicle_images():
    """Test if vehicle images exist in database"""
    print("\n=== Testing Vehicle Images ===")
    
    try:
        # Get the first vehicle
        vehicle = Vehicle.objects.first()
        if not vehicle:
            print("No vehicles found in database")
            return
        
        print(f"Vehicle ID: {vehicle.id}")
        print(f"Vehicle Model: {vehicle.model_number}")
        print(f"Vehicle Plate: {vehicle.plate_number}")
        
        # Check image fields
        image_fields = ['photo_front', 'photo_back', 'documents_image']
        
        for field in image_fields:
            image_data = getattr(vehicle, field)
            if image_data:
                print(f"✓ {field}: {len(image_data)} bytes")
            else:
                print(f"✗ {field}: None")
                
    except Exception as e:
        print(f"Error testing vehicle images: {str(e)}")

def test_database_connection():
    """Test database connection"""
    print("=== Testing Database Connection ===")
    
    try:
        from django.db import connection
        cursor = connection.cursor()
        cursor.execute("SELECT 1")
        result = cursor.fetchone()
        print(f"✓ Database connection successful: {result}")
    except Exception as e:
        print(f"✗ Database connection failed: {str(e)}")

if __name__ == "__main__":
    test_database_connection()
    test_user_images()
    test_vehicle_images()
    print("\n=== Test Complete ===") 