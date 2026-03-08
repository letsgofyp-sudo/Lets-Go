from decimal import Decimal
from uuid import uuid4

import pytest
from django.core.exceptions import ValidationError
from django.utils import timezone

from lets_go.models import Booking, Route, RouteStop, Trip, UsersData, Vehicle


pytestmark = pytest.mark.django_db


def _uniq(prefix: str) -> str:
    return f"{prefix}_{uuid4().hex[:10]}"


@pytest.fixture()
def driver_user():
    u = UsersData(
        name="Driver One",
        username=_uniq("driver"),
        email=f"{_uniq('driver')}@example.com",
        password="Password@123",
        address="Street 1",
        phone_no="+923001234567",
        cnic_no="36603-0269853-9",
        gender="male",
        status="VERIFIED",
    )
    u.full_clean()
    u.save()
    return u


@pytest.fixture()
def passenger_user():
    u = UsersData(
        name="Passenger One",
        username=_uniq("passenger"),
        email=f"{_uniq('passenger')}@example.com",
        password="Password@123",
        address="Street 2",
        phone_no="+923009876543",
        cnic_no="36603-0269853-8",
        gender="female",
        status="VERIFIED",
    )
    u.full_clean()
    u.save()
    return u


@pytest.fixture()
def route_with_two_stops():
    r = Route(
        route_id=_uniq("R"),
        route_name="Route 1",
        total_distance_km=Decimal("10.00"),
        estimated_duration_minutes=30,
    )
    r.full_clean()
    r.save()

    # Use Decimal strings to avoid float->Decimal precision artifacts
    # that can violate max decimal_places validation.
    s1 = RouteStop(
        route=r,
        stop_name="Stop A",
        stop_order=1,
        latitude=Decimal("31.50000000"),
        longitude=Decimal("74.30000000"),
    )
    s2 = RouteStop(
        route=r,
        stop_name="Stop B",
        stop_order=2,
        latitude=Decimal("31.60000000"),
        longitude=Decimal("74.40000000"),
    )
    s1.full_clean()
    s2.full_clean()
    s1.save()
    s2.save()

    return r, s1, s2


@pytest.fixture()
def driver_vehicle(driver_user):
    v = Vehicle(
        owner=driver_user,
        model_number="Model X",
        variant="",
        company_name="Honda",
        plate_number=f"ABC-{int(uuid4().int % 10000):04d}",
        vehicle_type=Vehicle.TWO_WHEELER,
        color="Red",
        seats=None,
        engine_number="",
        chassis_number="",
        fuel_type="",
        status=Vehicle.STATUS_VERIFIED,
    )
    v.full_clean()
    v.save()
    return v


@pytest.fixture()
def scheduled_trip(route_with_two_stops, driver_user, driver_vehicle):
    r, _, _ = route_with_two_stops
    trip = Trip(
        trip_id=_uniq("T"),
        route=r,
        vehicle=driver_vehicle,
        driver=driver_user,
        trip_date=timezone.now().date(),
        departure_time=timezone.datetime(2026, 1, 1, 10, 0).time(),
        estimated_arrival_time=timezone.datetime(2026, 1, 1, 12, 0).time(),
        trip_status="SCHEDULED",
        total_seats=4,
        available_seats=4,
        base_fare=Decimal("200.00"),
    )
    trip.full_clean()
    trip.save()
    return trip


def test_db_smoke_create_and_query(driver_user, passenger_user, route_with_two_stops, scheduled_trip):
    r, s1, s2 = route_with_two_stops

    assert UsersData.objects.filter(username=driver_user.username).exists()
    assert Route.objects.filter(route_id=r.route_id).exists()
    assert Trip.objects.filter(trip_id=scheduled_trip.trip_id).exists()

    b = Booking(
        booking_id=_uniq("B"),
        trip=scheduled_trip,
        passenger=passenger_user,
        from_stop=s1,
        to_stop=s2,
        number_of_seats=1,
        male_seats=0,
        female_seats=1,
        total_fare=Decimal("200.00"),
        booking_status="PENDING",
        payment_status="PENDING",
        seat_numbers=[1],
    )
    b.full_clean()
    b.save()

    fetched = Booking.objects.select_related("trip", "passenger").get(booking_id=b.booking_id)
    assert fetched.trip.trip_id == scheduled_trip.trip_id
    assert fetched.passenger.email == passenger_user.email


def test_booking_clean_rejects_wrong_stop_order(route_with_two_stops, scheduled_trip, passenger_user):
    _, s1, s2 = route_with_two_stops

    b = Booking(
        booking_id=_uniq("B"),
        trip=scheduled_trip,
        passenger=passenger_user,
        from_stop=s2,
        to_stop=s1,
        number_of_seats=1,
        male_seats=0,
        female_seats=1,
        total_fare=Decimal("200.00"),
        booking_status="PENDING",
        payment_status="PENDING",
        seat_numbers=[1],
    )

    with pytest.raises(ValidationError):
        b.full_clean()
