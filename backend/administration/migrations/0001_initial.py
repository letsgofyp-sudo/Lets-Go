from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='AdminTodoItem',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('source_type', models.CharField(max_length=64)),
                ('source_id', models.BigIntegerField()),
                ('title', models.CharField(max_length=200)),
                ('details', models.TextField(blank=True, null=True)),
                ('link_url', models.CharField(blank=True, max_length=500, null=True)),
                ('status', models.CharField(choices=[('PENDING', 'Pending'), ('DONE', 'Done')], default='PENDING', max_length=16)),
                ('priority', models.CharField(choices=[('LOW', 'Low'), ('MEDIUM', 'Medium'), ('HIGH', 'High')], default='MEDIUM', max_length=16)),
                ('category', models.CharField(choices=[('VERIFICATION', 'Verification'), ('SUPPORT_USER', 'Support (User)'), ('SUPPORT_GUEST', 'Support (Guest)'), ('SOS', 'SOS'), ('CHANGE_REQUEST', 'Change Request'), ('GENERAL', 'General')], default='GENERAL', max_length=32)),
                ('manual_done', models.BooleanField(default=False)),
                ('done_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('done_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='admin_todos_done', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'ordering': ['-created_at'],
            },
        ),
        migrations.AddIndex(
            model_name='admintodoitem',
            index=models.Index(fields=['status', 'priority', 'created_at'], name='admin_todo_status_priority_created'),
        ),
        migrations.AddIndex(
            model_name='admintodoitem',
            index=models.Index(fields=['category', 'status', 'created_at'], name='admin_todo_category_status_created'),
        ),
        migrations.AddIndex(
            model_name='admintodoitem',
            index=models.Index(fields=['source_type', 'source_id'], name='admin_todo_source'),
        ),
        migrations.AddConstraint(
            model_name='admintodoitem',
            constraint=models.UniqueConstraint(fields=('source_type', 'source_id'), name='uniq_admin_todo_source'),
        ),
    ]
