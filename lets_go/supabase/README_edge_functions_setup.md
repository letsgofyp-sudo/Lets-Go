# Supabase Edge Functions Setup (FCM Hybrid)

This project uses two Supabase Edge Functions:

- `send-ride-notification` (sends push via FCM)
- `register-fcm-token` (stores latest token for a `recipient_key`)

## 1) Create token table in Supabase

Run in Supabase SQL Editor:

```sql
create table if not exists public.recipient_fcm_tokens (
  recipient_key text primary key,
  fcm_token text null,
  updated_at timestamptz not null default now()
);

create index if not exists recipient_fcm_tokens_updated_at_idx
  on public.recipient_fcm_tokens(updated_at desc);
```

`recipient_key` format:

- `user:<id>`
- `guest:<id>`

## 2) Firebase service account

Firebase Console:

- Project settings -> Service accounts
- Generate new private key (JSON)

You will store the whole JSON in a Supabase secret as a string.

## 3) Set Supabase secrets

Using Supabase CLI:

```bash
supabase secrets set \
  SUPABASE_URL="https://YOUR_PROJECT.supabase.co" \
  SUPABASE_SERVICE_ROLE_KEY="YOUR_SERVICE_ROLE_KEY" \
  FIREBASE_PROJECT_ID="YOUR_FIREBASE_PROJECT_ID" \
  FIREBASE_SERVICE_ACCOUNT='{"type":"service_account",...}'
```

Notes:

- Use `SUPABASE_SERVICE_ROLE_KEY` (required for DB lookup + clearing stale tokens)
- `FIREBASE_SERVICE_ACCOUNT` must be the JSON string (do not base64 unless you adapt the function)

## 4) Deploy functions

From your Supabase functions folder:

```bash
supabase functions deploy send-ride-notification
supabase functions deploy register-fcm-token
```

## 5) Test token registration

```bash
curl -X POST "https://YOUR_PROJECT.functions.supabase.co/register-fcm-token" \
  -H "Content-Type: application/json" \
  -H "apikey: YOUR_SUPABASE_ANON_KEY_OR_EDGE_KEY" \
  -H "Authorization: Bearer YOUR_SUPABASE_ANON_KEY_OR_EDGE_KEY" \
  -d '{"recipient_key":"user:1","fcm_token":"AAAA..."}'
```

## 6) Test push send

```bash
curl -X POST "https://YOUR_PROJECT.functions.supabase.co/send-ride-notification" \
  -H "Content-Type: application/json" \
  -H "apikey: YOUR_SUPABASE_ANON_KEY_OR_EDGE_KEY" \
  -H "Authorization: Bearer YOUR_SUPABASE_ANON_KEY_OR_EDGE_KEY" \
  -d '{
    "recipient_id":"1",
    "recipient_key":"user:1",
    "title":"Lets Go",
    "body":"Test",
    "data":{"type":"notification_summary"}
  }'
```

## Hybrid token strategy (what happens)

1) If request payload contains `fcm_token`, the function sends using it.
2) Else, if payload contains `recipient_key`, it looks up latest token from `recipient_fcm_tokens`.
3) Else, it falls back to legacy `lets_go_usersdata.fcm_token` lookup.

If FCM replies with `UNREGISTERED`, the function clears:

- `recipient_fcm_tokens.fcm_token` for that recipient_key
- `lets_go_usersdata.fcm_token`
- `user_profiles.fcm_token`
