from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('lets_go', '0028_trip_booking_history_and_actual_path_summary'),
    ]

    operations = [
        migrations.AlterField(
            model_name='triphistorysnapshot',
            name='trip_obj',
            field=models.OneToOneField(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='history_snapshot', to='lets_go.trip'),
        ),
        migrations.AlterField(
            model_name='bookinghistorysnapshot',
            name='booking_obj',
            field=models.OneToOneField(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='history_snapshot', to='lets_go.booking'),
        ),
        migrations.AlterField(
            model_name='bookinghistorysnapshot',
            name='trip_obj',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='booking_history_snapshots', to='lets_go.trip'),
        ),
        migrations.AlterField(
            model_name='tripactualpathsummary',
            name='trip_obj',
            field=models.OneToOneField(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='actual_path_summary', to='lets_go.trip'),
        ),
        migrations.AddField(
            model_name='tripactualpathsummary',
            name='trip_id',
            field=models.CharField(db_index=True, default='', max_length=50),
            preserve_default=False,
        ),
    ]
