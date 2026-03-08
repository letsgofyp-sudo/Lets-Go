from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ("lets_go", "0043_notification_inbox_and_offline_notification_queue"),
    ]

    operations = [
        migrations.RunSQL(
            sql="""
            ALTER TABLE notification_inbox
                ADD COLUMN IF NOT EXISTS recipient_key VARCHAR(128);
            ALTER TABLE notification_inbox
                ADD COLUMN IF NOT EXISTS guest_id BIGINT NULL;
            ALTER TABLE notification_inbox
                ADD CONSTRAINT notification_inbox_guest_fk
                    FOREIGN KEY (guest_id) REFERENCES lets_go_guestuser(id) ON DELETE CASCADE;

            UPDATE notification_inbox
                SET recipient_key = 'user:' || user_id::text
                WHERE recipient_key IS NULL;

            ALTER TABLE notification_inbox
                ALTER COLUMN recipient_key SET NOT NULL;

            CREATE INDEX IF NOT EXISTS notification_inbox_recipient_created_idx
                ON notification_inbox(recipient_key, created_at DESC);
            CREATE INDEX IF NOT EXISTS notification_inbox_recipient_unread_idx
                ON notification_inbox(recipient_key, is_read, is_dismissed);
            CREATE INDEX IF NOT EXISTS notification_inbox_recipient_push_idx
                ON notification_inbox(recipient_key, push_sent);

            ALTER TABLE offline_notification_queue
                ADD COLUMN IF NOT EXISTS recipient_key VARCHAR(128);
            ALTER TABLE offline_notification_queue
                ADD COLUMN IF NOT EXISTS guest_id BIGINT NULL;
            ALTER TABLE offline_notification_queue
                ADD CONSTRAINT offline_notification_queue_guest_fk
                    FOREIGN KEY (guest_id) REFERENCES lets_go_guestuser(id) ON DELETE CASCADE;

            UPDATE offline_notification_queue
                SET recipient_key = 'user:' || user_id::text
                WHERE recipient_key IS NULL;

            ALTER TABLE offline_notification_queue
                ALTER COLUMN recipient_key SET NOT NULL;

            CREATE INDEX IF NOT EXISTS offline_notification_queue_recipient_delivered_idx
                ON offline_notification_queue(recipient_key, is_delivered, created_at);
            """,
            reverse_sql="""
            DROP INDEX IF EXISTS offline_notification_queue_recipient_delivered_idx;
            DROP INDEX IF EXISTS notification_inbox_recipient_push_idx;
            DROP INDEX IF EXISTS notification_inbox_recipient_unread_idx;
            DROP INDEX IF EXISTS notification_inbox_recipient_created_idx;

            ALTER TABLE offline_notification_queue DROP CONSTRAINT IF EXISTS offline_notification_queue_guest_fk;
            ALTER TABLE notification_inbox DROP CONSTRAINT IF EXISTS notification_inbox_guest_fk;

            ALTER TABLE offline_notification_queue DROP COLUMN IF EXISTS guest_id;
            ALTER TABLE offline_notification_queue DROP COLUMN IF EXISTS recipient_key;

            ALTER TABLE notification_inbox DROP COLUMN IF EXISTS guest_id;
            ALTER TABLE notification_inbox DROP COLUMN IF EXISTS recipient_key;
            """,
        ),
    ]
