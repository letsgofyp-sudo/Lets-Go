from django.db import models
from django.conf import settings
from django.utils import timezone


class AdminTodoItem(models.Model):
    STATUS_PENDING = 'PENDING'
    STATUS_DONE = 'DONE'
    STATUS_CHOICES = [
        (STATUS_PENDING, 'Pending'),
        (STATUS_DONE, 'Done'),
    ]

    PRIORITY_LOW = 'LOW'
    PRIORITY_MEDIUM = 'MEDIUM'
    PRIORITY_HIGH = 'HIGH'
    PRIORITY_CHOICES = [
        (PRIORITY_LOW, 'Low'),
        (PRIORITY_MEDIUM, 'Medium'),
        (PRIORITY_HIGH, 'High'),
    ]

    CATEGORY_VERIFICATION = 'VERIFICATION'
    CATEGORY_SUPPORT_USER = 'SUPPORT_USER'
    CATEGORY_SUPPORT_GUEST = 'SUPPORT_GUEST'
    CATEGORY_SOS = 'SOS'
    CATEGORY_CHANGE_REQUEST = 'CHANGE_REQUEST'
    CATEGORY_GENERAL = 'GENERAL'
    CATEGORY_CHOICES = [
        (CATEGORY_VERIFICATION, 'Verification'),
        (CATEGORY_SUPPORT_USER, 'Support (User)'),
        (CATEGORY_SUPPORT_GUEST, 'Support (Guest)'),
        (CATEGORY_SOS, 'SOS'),
        (CATEGORY_CHANGE_REQUEST, 'Change Request'),
        (CATEGORY_GENERAL, 'General'),
    ]

    SOURCE_USER_VERIFICATION = 'USER_VERIFICATION'
    SOURCE_SUPPORT_THREAD = 'SUPPORT_THREAD'
    SOURCE_SOS_INCIDENT = 'SOS_INCIDENT'
    SOURCE_CHANGE_REQUEST = 'CHANGE_REQUEST'

    source_type = models.CharField(max_length=64)
    source_id = models.BigIntegerField()

    title = models.CharField(max_length=200)
    details = models.TextField(null=True, blank=True)
    link_url = models.CharField(max_length=500, null=True, blank=True)

    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default=STATUS_PENDING)
    priority = models.CharField(max_length=16, choices=PRIORITY_CHOICES, default=PRIORITY_MEDIUM)
    category = models.CharField(max_length=32, choices=CATEGORY_CHOICES, default=CATEGORY_GENERAL)

    manual_done = models.BooleanField(default=False)

    done_at = models.DateTimeField(null=True, blank=True)
    done_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='admin_todos_done',
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=['source_type', 'source_id'], name='uniq_admin_todo_source'),
        ]
        indexes = [
            models.Index(fields=['status', 'priority', 'created_at']),
            models.Index(fields=['category', 'status', 'created_at']),
            models.Index(fields=['source_type', 'source_id']),
        ]
        ordering = ['-created_at']

    def mark_done(self, by_user=None, manual: bool = False):
        if self.status == self.STATUS_DONE and self.done_at is not None:
            if manual:
                self.manual_done = True
                self.done_by = by_user
                self.save(update_fields=['manual_done', 'done_by', 'updated_at'])
            return

        self.status = self.STATUS_DONE
        self.done_at = timezone.now()
        self.done_by = by_user
        if manual:
            self.manual_done = True
        self.save(update_fields=['status', 'done_at', 'done_by', 'manual_done', 'updated_at'])

    def reopen(self):
        self.status = self.STATUS_PENDING
        self.done_at = None
        self.done_by = None
        self.manual_done = False
        self.save(update_fields=['status', 'done_at', 'done_by', 'manual_done', 'updated_at'])


class SupportFAQ(models.Model):
    category = models.CharField(max_length=64, null=True, blank=True)
    question = models.TextField()
    answer = models.TextField()

    is_active = models.BooleanField(default=True)
    priority = models.IntegerField(default=100)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=['is_active', 'priority', 'created_at']),
            models.Index(fields=['category', 'is_active']),
        ]
        ordering = ['priority', 'id']

    def __str__(self):
        q = (self.question or '').strip().replace('\n', ' ')
        if len(q) > 80:
            q = q[:77] + '...'
        return q
