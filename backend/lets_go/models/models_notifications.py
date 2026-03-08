from django.db import models
from django.utils import timezone


class NotificationInbox(models.Model):
    id = models.BigAutoField(primary_key=True)
    recipient_key = models.CharField(max_length=128, db_index=True)
    user = models.ForeignKey('UsersData', on_delete=models.CASCADE, null=True, blank=True, db_index=True)
    guest = models.ForeignKey('GuestUser', on_delete=models.CASCADE, null=True, blank=True, db_index=True)
    notification_type = models.CharField(max_length=64, db_index=True)
    title = models.CharField(max_length=200, blank=True)
    body = models.TextField(blank=True)
    data = models.JSONField(default=dict, blank=True)

    is_read = models.BooleanField(default=False, db_index=True)
    read_at = models.DateTimeField(null=True, blank=True)
    is_dismissed = models.BooleanField(default=False, db_index=True)
    dismissed_at = models.DateTimeField(null=True, blank=True)

    push_sent = models.BooleanField(default=False, db_index=True)
    push_sent_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = 'notification_inbox'
        indexes = [
            models.Index(fields=['recipient_key', '-created_at']),
            models.Index(fields=['recipient_key', 'is_read', 'is_dismissed']),
            models.Index(fields=['recipient_key', 'push_sent']),
        ]


class OfflineNotificationQueue(models.Model):
    id = models.BigAutoField(primary_key=True)
    recipient_key = models.CharField(max_length=128, db_index=True)
    user = models.ForeignKey('UsersData', on_delete=models.CASCADE, null=True, blank=True, db_index=True)
    guest = models.ForeignKey('GuestUser', on_delete=models.CASCADE, null=True, blank=True, db_index=True)
    is_delivered = models.BooleanField(default=False, db_index=True)
    created_at = models.DateTimeField(default=timezone.now, db_index=True)
    delivered_at = models.DateTimeField(null=True, blank=True)
    payload = models.JSONField(default=dict, blank=True)

    class Meta:
        db_table = 'offline_notification_queue'
        indexes = [
            models.Index(fields=['recipient_key', 'is_delivered', 'created_at']),
        ]
        managed = True
