from django.db import migrations, models
import django.db.models.deletion
import django.utils.timezone


class Migration(migrations.Migration):

    dependencies = [
        ('lets_go', '0027_booking_blocked_and_blockeduser'),
    ]

    operations = [
        migrations.CreateModel(
            name='TripActualPathSummary',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('source', models.CharField(db_index=True, default='TripLiveLocationUpdate', max_length=32)),
                ('point_count', models.IntegerField(default=0)),
                ('started_at', models.DateTimeField(blank=True, null=True)),
                ('ended_at', models.DateTimeField(blank=True, null=True)),
                ('distance_km', models.DecimalField(blank=True, decimal_places=3, max_digits=10, null=True)),
                ('duration_seconds', models.IntegerField(blank=True, null=True)),
                ('bbox', models.JSONField(blank=True, default=dict)),
                ('simplified_points', models.JSONField(blank=True, default=list)),
                ('encoded_polyline', models.TextField(blank=True, null=True)),
                ('generated_at', models.DateTimeField(db_index=True, default=django.utils.timezone.now)),
                ('trip_obj', models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name='actual_path_summary', to='lets_go.trip')),
            ],
            options={
                'indexes': [
                    models.Index(fields=['trip_obj', 'generated_at'], name='lets_go_tri_trip_gen_d9c1b2_idx'),
                    models.Index(fields=['generated_at'], name='lets_go_tri_generated_70a8c4_idx'),
                ],
            },
        ),
        migrations.CreateModel(
            name='TripHistorySnapshot',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('trip_id', models.CharField(db_index=True, max_length=50)),
                ('trip_status', models.CharField(db_index=True, max_length=20)),
                ('trip_date', models.DateField(blank=True, db_index=True, null=True)),
                ('departure_time', models.TimeField(blank=True, db_index=True, null=True)),
                ('route_id', models.CharField(blank=True, db_index=True, max_length=50, null=True)),
                ('route_name', models.CharField(blank=True, max_length=255, null=True)),
                ('route_names', models.JSONField(blank=True, default=list)),
                ('planned_stops', models.JSONField(blank=True, default=list)),
                ('vehicle_data', models.JSONField(blank=True, default=dict)),
                ('total_seats', models.IntegerField(blank=True, null=True)),
                ('base_fare', models.IntegerField(blank=True, null=True)),
                ('gender_preference', models.CharField(blank=True, max_length=10, null=True)),
                ('notes', models.TextField(blank=True, null=True)),
                ('is_negotiable', models.BooleanField(default=True)),
                ('fare_calculation', models.JSONField(blank=True, default=dict)),
                ('stop_breakdown', models.JSONField(blank=True, default=list)),
                ('started_at', models.DateTimeField(blank=True, null=True)),
                ('completed_at', models.DateTimeField(blank=True, null=True)),
                ('cancelled_at', models.DateTimeField(blank=True, null=True)),
                ('finalized_at', models.DateTimeField(blank=True, db_index=True, null=True)),
                ('created_at', models.DateTimeField(default=django.utils.timezone.now)),
                ('driver', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='trip_history_snapshots', to='lets_go.usersdata')),
                ('trip_obj', models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name='history_snapshot', to='lets_go.trip')),
            ],
            options={
                'indexes': [
                    models.Index(fields=['driver', 'finalized_at'], name='lets_go_tri_driver_f_d3b3f5_idx'),
                    models.Index(fields=['trip_status', 'finalized_at'], name='lets_go_tri_status_f_eef5d9_idx'),
                    models.Index(fields=['trip_date', 'departure_time'], name='lets_go_tri_date_dep_83b5ab_idx'),
                ],
            },
        ),
        migrations.CreateModel(
            name='BookingHistorySnapshot',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('booking_id', models.CharField(db_index=True, max_length=50)),
                ('trip_id', models.CharField(db_index=True, max_length=50)),
                ('booking_status', models.CharField(db_index=True, max_length=20)),
                ('ride_status', models.CharField(db_index=True, max_length=20)),
                ('payment_status', models.CharField(db_index=True, max_length=20)),
                ('from_stop_name', models.CharField(blank=True, max_length=255, null=True)),
                ('to_stop_name', models.CharField(blank=True, max_length=255, null=True)),
                ('from_stop_order', models.IntegerField(blank=True, null=True)),
                ('to_stop_order', models.IntegerField(blank=True, null=True)),
                ('number_of_seats', models.IntegerField(blank=True, null=True)),
                ('total_fare', models.IntegerField(blank=True, null=True)),
                ('booked_at', models.DateTimeField(blank=True, null=True)),
                ('pickup_verified_at', models.DateTimeField(blank=True, null=True)),
                ('dropoff_at', models.DateTimeField(blank=True, null=True)),
                ('completed_at', models.DateTimeField(blank=True, null=True)),
                ('finalized_at', models.DateTimeField(blank=True, db_index=True, null=True)),
                ('created_at', models.DateTimeField(default=django.utils.timezone.now)),
                ('booking_obj', models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name='history_snapshot', to='lets_go.booking')),
                ('passenger', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='booking_history_snapshots', to='lets_go.usersdata')),
                ('trip_obj', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='booking_history_snapshots', to='lets_go.trip')),
            ],
            options={
                'indexes': [
                    models.Index(fields=['passenger', 'finalized_at'], name='lets_go_boo_passeng_b7a0f0_idx'),
                    models.Index(fields=['trip_obj', 'finalized_at'], name='lets_go_boo_trip_fin_74c21c_idx'),
                    models.Index(fields=['payment_status', 'ride_status', 'finalized_at'], name='lets_go_boo_payride_8b820f_idx'),
                ],
            },
        ),
    ]
