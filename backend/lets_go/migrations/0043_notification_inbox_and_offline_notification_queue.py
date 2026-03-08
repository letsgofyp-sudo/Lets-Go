from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ("lets_go", "0042_create_offline_message_queue_table"),
    ]

    operations = [
        migrations.RunSQL(
            sql="""
            CREATE TABLE IF NOT EXISTS notification_inbox (
                id BIGSERIAL PRIMARY KEY,
                user_id BIGINT NOT NULL REFERENCES lets_go_usersdata(id) ON DELETE CASCADE,
                notification_type VARCHAR(64) NOT NULL,
                title VARCHAR(200) NOT NULL DEFAULT '',
                body TEXT NOT NULL DEFAULT '',
                data JSONB NOT NULL DEFAULT '{}'::jsonb,
                is_read BOOLEAN NOT NULL DEFAULT FALSE,
                read_at TIMESTAMPTZ NULL,
                is_dismissed BOOLEAN NOT NULL DEFAULT FALSE,
                dismissed_at TIMESTAMPTZ NULL,
                push_sent BOOLEAN NOT NULL DEFAULT FALSE,
                push_sent_at TIMESTAMPTZ NULL,
                created_at TIMESTAMPTZ NOT NULL DEFAULT now()
            );

            CREATE INDEX IF NOT EXISTS notification_inbox_user_created_idx
                ON notification_inbox(user_id, created_at DESC);
            CREATE INDEX IF NOT EXISTS notification_inbox_user_unread_idx
                ON notification_inbox(user_id, is_read, is_dismissed);
            CREATE INDEX IF NOT EXISTS notification_inbox_user_push_idx
                ON notification_inbox(user_id, push_sent);

            CREATE TABLE IF NOT EXISTS offline_notification_queue (
                id BIGSERIAL PRIMARY KEY,
                user_id BIGINT NOT NULL REFERENCES lets_go_usersdata(id) ON DELETE CASCADE,
                is_delivered BOOLEAN NOT NULL DEFAULT FALSE,
                created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                delivered_at TIMESTAMPTZ NULL,
                payload JSONB NOT NULL DEFAULT '{}'::jsonb
            );

            CREATE INDEX IF NOT EXISTS offline_notification_queue_user_delivered_idx
                ON offline_notification_queue(user_id, is_delivered, created_at);
            """,
            reverse_sql="""
            DROP TABLE IF EXISTS offline_notification_queue;
            DROP TABLE IF EXISTS notification_inbox;
            """,
        ),
    ]
