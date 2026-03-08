from django.db import models
from django.utils import timezone


class TripHistorySnapshot(models.Model):
    trip_obj = models.OneToOneField('Trip', on_delete=models.SET_NULL, null=True, blank=True, related_name='history_snapshot')

    trip_id = models.CharField(max_length=50, db_index=True)
    trip_status = models.CharField(max_length=20, db_index=True)

    driver = models.ForeignKey('UsersData', on_delete=models.CASCADE, related_name='trip_history_snapshots')

    trip_date = models.DateField(null=True, blank=True, db_index=True)
    departure_time = models.TimeField(null=True, blank=True, db_index=True)

    route_id = models.CharField(max_length=50, null=True, blank=True, db_index=True)
    route_name = models.CharField(max_length=255, null=True, blank=True)
    route_names = models.JSONField(default=list, blank=True)

    planned_stops = models.JSONField(default=list, blank=True)

    vehicle_data = models.JSONField(default=dict, blank=True)

    total_seats = models.IntegerField(null=True, blank=True)
    base_fare = models.IntegerField(null=True, blank=True)
    gender_preference = models.CharField(max_length=10, null=True, blank=True)
    notes = models.TextField(null=True, blank=True)
    is_negotiable = models.BooleanField(default=True)

    fare_calculation = models.JSONField(default=dict, blank=True)
    stop_breakdown = models.JSONField(default=list, blank=True)

    actual_path = models.JSONField(default=list, blank=True)

    started_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)
    finalized_at = models.DateTimeField(null=True, blank=True, db_index=True)

    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        indexes = [
            models.Index(fields=['driver', 'finalized_at']),
            models.Index(fields=['trip_status', 'finalized_at']),
            models.Index(fields=['trip_date', 'departure_time']),
        ]


class BookingHistorySnapshot(models.Model):
    booking_obj = models.OneToOneField('Booking', on_delete=models.SET_NULL, null=True, blank=True, related_name='history_snapshot')

    booking_id = models.CharField(max_length=50, db_index=True)

    trip_obj = models.ForeignKey('Trip', on_delete=models.SET_NULL, null=True, blank=True, related_name='booking_history_snapshots')
    trip_id = models.CharField(max_length=50, db_index=True)

    passenger = models.ForeignKey('UsersData', on_delete=models.CASCADE, related_name='booking_history_snapshots')

    booking_status = models.CharField(max_length=20, db_index=True)
    ride_status = models.CharField(max_length=20, db_index=True)
    payment_status = models.CharField(max_length=20, db_index=True)

    from_stop_name = models.CharField(max_length=255, null=True, blank=True)
    to_stop_name = models.CharField(max_length=255, null=True, blank=True)
    from_stop_order = models.IntegerField(null=True, blank=True)
    to_stop_order = models.IntegerField(null=True, blank=True)

    number_of_seats = models.IntegerField(null=True, blank=True)
    total_fare = models.IntegerField(null=True, blank=True)

    booked_at = models.DateTimeField(null=True, blank=True)
    pickup_verified_at = models.DateTimeField(null=True, blank=True)
    dropoff_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    finalized_at = models.DateTimeField(null=True, blank=True, db_index=True)

    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        indexes = [
            models.Index(fields=['passenger', 'finalized_at']),
            models.Index(fields=['trip_obj', 'finalized_at']),
            models.Index(fields=['payment_status', 'ride_status', 'finalized_at']),
        ]


class TripActualPathSummary(models.Model):
    trip_obj = models.OneToOneField('Trip', on_delete=models.SET_NULL, null=True, blank=True, related_name='actual_path_summary')
    trip_id = models.CharField(max_length=50, db_index=True)

    source = models.CharField(max_length=32, default='TripLiveLocationUpdate', db_index=True)

    point_count = models.IntegerField(default=0)
    started_at = models.DateTimeField(null=True, blank=True)
    ended_at = models.DateTimeField(null=True, blank=True)

    distance_km = models.DecimalField(max_digits=10, decimal_places=3, null=True, blank=True)
    duration_seconds = models.IntegerField(null=True, blank=True)

    bbox = models.JSONField(default=dict, blank=True)

    # Storage options:
    # - simplified_points: list of {lat,lng,timestamp?}
    # - encoded_polyline: optional if you later want compressed representation
    simplified_points = models.JSONField(default=list, blank=True)
    encoded_polyline = models.TextField(null=True, blank=True)

    generated_at = models.DateTimeField(default=timezone.now, db_index=True)

    class Meta:
        indexes = [
            models.Index(fields=['trip_obj', 'generated_at']),
            models.Index(fields=['generated_at']),
        ]


class TripActualPathPoint(models.Model):
    summary = models.ForeignKey(TripActualPathSummary, on_delete=models.CASCADE, related_name='points')
    point_index = models.IntegerField(db_index=True)
    latitude = models.DecimalField(max_digits=10, decimal_places=8)
    longitude = models.DecimalField(max_digits=11, decimal_places=8)
    speed_mps = models.FloatField(null=True, blank=True)
    recorded_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        unique_together = ['summary', 'point_index']
        indexes = [
            models.Index(fields=['summary', 'point_index']),
        ]
        ordering = ['summary', 'point_index']


class ResolvedSosAuditSnapshot(models.Model):
    incident_obj = models.OneToOneField(
        'SosIncident',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='resolved_audit_snapshot',
    )

    incident_id = models.IntegerField(db_index=True)
    trip_id = models.CharField(max_length=50, null=True, blank=True, db_index=True)
    booking_id = models.CharField(max_length=50, null=True, blank=True, db_index=True)

    resolved_at = models.DateTimeField(null=True, blank=True, db_index=True)
    resolved_by_username = models.CharField(max_length=150, null=True, blank=True)

    payload = models.JSONField(default=dict, blank=True)

    created_at = models.DateTimeField(default=timezone.now)
    updated_at = models.DateTimeField(default=timezone.now)

    class Meta:
        indexes = [
            models.Index(fields=['incident_id']),
            models.Index(fields=['resolved_at']),
            models.Index(fields=['trip_id', 'resolved_at']),
        ]
