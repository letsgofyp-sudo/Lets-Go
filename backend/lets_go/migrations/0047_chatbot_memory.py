from django.db import migrations, models
import django.db.models.deletion
from django.db.models import Q


class Migration(migrations.Migration):

    dependencies = [
        ('lets_go', '0046_alter_vehicle_plate_number_notificationinbox_and_more'),
    ]

    operations = [
        migrations.CreateModel(
            name='ChatbotMemory',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('summary', models.TextField(blank=True, default='')),
                ('preferences', models.JSONField(blank=True, default=dict)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True, db_index=True)),
                ('guest', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.CASCADE, related_name='chatbot_memory', to='lets_go.guestuser')),
                ('user', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.CASCADE, related_name='chatbot_memory', to='lets_go.usersdata')),
            ],
        ),
        migrations.AddConstraint(
            model_name='chatbotmemory',
            constraint=models.UniqueConstraint(condition=Q(user__isnull=False), fields=('user',), name='uniq_chatbotmemory_user'),
        ),
        migrations.AddConstraint(
            model_name='chatbotmemory',
            constraint=models.UniqueConstraint(condition=Q(guest__isnull=False), fields=('guest',), name='uniq_chatbotmemory_guest'),
        ),
        migrations.AddConstraint(
            model_name='chatbotmemory',
            constraint=models.CheckConstraint(
                condition=(
                    Q(user__isnull=False, guest__isnull=True)
                    | Q(user__isnull=True, guest__isnull=False)
                ),
                name='chk_chatbotmemory_owner_xor',
            ),
        ),
    ]
