#!/usr/bin/env python
"""
Test script to verify import issues are resolved
"""
import os
import sys
import django

# Add the backend directory to Python path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Set up Django environment
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'backend.settings')
django.setup()

def test_imports():
    """Test if all imports work correctly"""
    print("=== Testing Imports ===")
    
    try:
        # Test phone_otp_send imports
        from lets_go.phone_otp_send import send_phone_otp, send_phone_otp_for_reset
        print("✓ phone_otp_send imports successful")
        
        # Test email_otp imports
        from lets_go.email_otp import send_email_otp, send_email_otp_for_reset
        print("✓ email_otp imports successful")
        
        # Test views_authentication imports
        from lets_go import views_authentication
        print("✓ views_authentication imports successful")
        
        # Test views_rideposting imports
        from lets_go import views_rideposting
        print("✓ views_rideposting imports successful")
        
        # Test models imports
        from lets_go.models import UsersData, Vehicle, Trip, Route, Booking
        print("✓ models imports successful")
        
        print("\n✅ All imports successful!")
        return True
        
    except ImportError as e:
        print(f"❌ Import error: {str(e)}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {str(e)}")
        return False

if __name__ == "__main__":
    test_imports() 