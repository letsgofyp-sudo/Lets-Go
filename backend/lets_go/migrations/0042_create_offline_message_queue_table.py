from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ("lets_go", "0041_triphistorysnapshot_actual_path"),
    ]

    operations = [
        migrations.RunSQL(
            sql="""
            CREATE TABLE IF NOT EXISTS offline_message_queue (
                id BIGSERIAL PRIMARY KEY,
                is_delivered BOOLEAN NOT NULL,
                created_at TIMESTAMPTZ NOT NULL,
                delivered_at TIMESTAMPTZ NULL,
                chat_room_id BIGINT NULL,
                message_id BIGINT NULL,
                user_id BIGINT NOT NULL REFERENCES lets_go_usersdata(id) ON DELETE CASCADE
            );
            """,
            reverse_sql="DROP TABLE IF EXISTS offline_message_queue;",
        ),
    ]
