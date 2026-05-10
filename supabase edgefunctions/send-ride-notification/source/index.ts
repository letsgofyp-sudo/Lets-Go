/*
// Follows the Supabase Edge Functions template
// Docs: https://supabase.com/docs/guides/functions

// @deno-types="npm:@types/node"
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { SignJWT } from 'https://deno.land/x/jose@v4.14.4/jwt/sign.ts';
import { importPKCS8 } from 'https://deno.land/x/jose@v4.14.4/key/import.ts';

// Add type declarations for Deno
declare const Deno: {
  env: {
    get(key: string): string | undefined;
  };
  exit(code?: number): never;
};

// CORS headers for the response
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
}

async function getAccessToken(serviceAccount: any): Promise<string> {
  const privateKey = await importPKCS8(serviceAccount.private_key, 'RS256');
  const jwt = await new SignJWT({
    // Prefer the specific FCM scope. If your org requires broader scopes you can
    // switch back to cloud-platform.
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
  })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(serviceAccount.client_email)
    .setAudience('https://oauth2.googleapis.com/token')
    .setIssuedAt()
    .setExpirationTime('1h')
    .setSubject(serviceAccount.client_email)
    .sign(privateKey);

  const resp = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });

  const text = await resp.text();
  console.log('[send-ride-notification] Google token resp:', { status: resp.status, text });
  if (!resp.ok) throw new Error(`Google token fetch failed: ${resp.status} ${text}`);

  const parsed = JSON.parse(text);
  if (!parsed.access_token) throw new Error('No access_token in Google response');
  return parsed.access_token;
}

// Define types for the request body
interface NotificationRequest {
  recipient_id: string;
  sender_id?: string;
  // Backward compatibility with older payloads
  user_id?: string;
  driver_id?: string;
  title: string;
  body: string;
  data?: Record<string, any>;
}

// Define types for the user profile
interface UserProfile {
  fcm_token?: string;
}

// Main function to handle HTTP requests
serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const serviceAccountRaw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT') || '{}';

    const serviceAccount = JSON.parse(serviceAccountRaw);
    const envProjectId = Deno.env.get('FIREBASE_PROJECT_ID');
    const saProjectId = serviceAccount?.project_id;
    const projectId = envProjectId || saProjectId;

    console.log('[send-ride-notification] env check:', {
      hasSupabaseUrl: Boolean(supabaseUrl),
      hasServiceRoleKey: Boolean(serviceRoleKey),
      hasServiceAccount: serviceAccountRaw !== '{}',
      envProjectId,
      saProjectId,
      projectId,
    });

    if (!projectId) {
      return new Response(
        JSON.stringify({
          error: 'Missing Firebase project id',
          details: 'Set FIREBASE_PROJECT_ID or include project_id in FIREBASE_SERVICE_ACCOUNT',
        }),
        { status: 500, headers: corsHeaders },
      );
    }

    const rawPayload: Partial<NotificationRequest> = await req.json();
    const title = rawPayload.title;
    const body = rawPayload.body;
    const data = rawPayload.data;

    const recipient_id = rawPayload.recipient_id ?? rawPayload.user_id ?? rawPayload.driver_id;
    const sender_id = rawPayload.sender_id ?? rawPayload.driver_id;

    console.log('[send-ride-notification] incoming payload:', {
      recipient_id,
      sender_id,
      title,
      body,
      dataKeys: Object.keys(data || {}),
    });

    if (!recipient_id || !title || !body) {
      return new Response(JSON.stringify({ error: 'Missing required fields: recipient_id, title, body' }), {
        status: 400,
        headers: corsHeaders,
      });
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const recipientIdStr = String(recipient_id);
    const idNum = Number(recipientIdStr);
    const recipientIdEq: any = Number.isFinite(idNum) ? idNum : recipientIdStr;
    console.log('[send-ride-notification] coerced recipient:', { recipientIdEq, type: typeof recipientIdEq });

    let userData: UserProfile | null = null;
    let tokenErr: any = null;
    {
      const res = await supabase
        .from('lets_go_usersdata')
        .select('fcm_token')
        .eq('id', recipientIdEq)
        .single();
      userData = (res.data as any) ?? null;
      tokenErr = res.error;
    }
    if (tokenErr) {
      const res2 = await supabase
        .from('user_profiles')
        .select('fcm_token')
        .eq('id', recipientIdStr)
        .single();
      userData = (res2.data as any) ?? null;
      tokenErr = res2.error;
    }

    console.log('[send-ride-notification] token fetch result:', { userData, tokenErr });

    if (tokenErr || !userData?.fcm_token) {
      return new Response(JSON.stringify({ error: 'Failed to get recipient FCM token', details: tokenErr }), {
        status: 400,
        headers: corsHeaders,
      });
    }

    const accessToken = await getAccessToken(serviceAccount);

    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    const inputData = data || {};
    const stringData: Record<string, string> = {};
    for (const [k, v] of Object.entries(inputData)) {
      if (v === null || v === undefined) continue;
      stringData[k] = typeof v === 'string' ? v : JSON.stringify(v);
    }
    // Always include title/body in data so the client can render local notifications
    // (especially when sending data-only messages).
    stringData['title'] = String(title);
    stringData['body'] = String(body);
    stringData['recipient_id'] = recipientIdStr;
    if (sender_id !== undefined && sender_id !== null) {
      stringData['sender_id'] = String(sender_id);
    }

    const fcmBody = {
      message: {
        token: userData.fcm_token,
        // IMPORTANT: Send data-only messages so the Flutter app can always
        // generate interactive notifications (actions/inline reply) via
        // flutter_local_notifications, even when the app is in background.
        data: stringData,
        android: {
          priority: 'HIGH',
        },
      },
    };

    console.log('[send-ride-notification] FCM request:', {
      fcmUrl,
      projectId,
      tokenLen: userData.fcm_token?.length,
      payloadKeys: Object.keys(stringData),
    });

    const fcmResp = await fetch(fcmUrl, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(fcmBody),
    });

    const fcmText = await fcmResp.text();
    console.log('[send-ride-notification] FCM response:', { status: fcmResp.status, body: fcmText });

    if (!fcmResp.ok) {
      // If the device token is stale (common after reinstall), FCM responds with
      // errorCode=UNREGISTERED. Clear the stored token so the system can recover
      // once the client re-registers a fresh token.
      try {
        const parsed = JSON.parse(fcmText);
        const errorCode = parsed?.error?.details?.[0]?.errorCode;
        if (errorCode === 'UNREGISTERED') {
          console.log('[send-ride-notification] token UNREGISTERED; clearing token for recipient', {
            recipientIdEq,
            recipientIdStr,
          });
          const clear1 = await supabase
            .from('lets_go_usersdata')
            .update({ fcm_token: null })
            .eq('id', recipientIdEq);
          console.log('[send-ride-notification] cleared lets_go_usersdata token:', { error: clear1.error });

          const clear2 = await supabase
            .from('user_profiles')
            .update({ fcm_token: null })
            .eq('id', recipientIdStr);
          console.log('[send-ride-notification] cleared user_profiles token:', { error: clear2.error });
        }
      } catch (_) {}

      return new Response(JSON.stringify({ error: 'Failed to send notification', details: fcmText }), {
        status: fcmResp.status,
        headers: corsHeaders,
      });
    }

    return new Response(JSON.stringify({ success: true, message: 'Notification sent', raw: fcmText }), {
      headers: corsHeaders,
    });
  } catch (error) {
    console.error('Error in send-ride-notification:', error);
    return new Response(
      JSON.stringify({ 
        error: 'Internal server error',
        details: error instanceof Error ? error.message : String(error)
      }),
      { status: 500, headers: { ...corsHeaders } }
    );
  }
});
*/

// Follows the Supabase Edge Functions template
// Docs: https://supabase.com/docs/guides/functions

// @deno-types="npm:@types/node"
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { SignJWT } from 'https://deno.land/x/jose@v4.14.4/jwt/sign.ts';
import { importPKCS8 } from 'https://deno.land/x/jose@v4.14.4/key/import.ts';

// Add type declarations for Deno
declare const Deno: {
  env: {
    get(key: string): string | undefined;
  };
  exit(code?: number): never;
};

// CORS headers for the response
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
}

async function getAccessToken(serviceAccount: any): Promise<string> {
  const privateKey = await importPKCS8(serviceAccount.private_key, 'RS256');
  const jwt = await new SignJWT({
    // Prefer the specific FCM scope. If your org requires broader scopes you can
    // switch back to cloud-platform.
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
  })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(serviceAccount.client_email)
    .setAudience('https://oauth2.googleapis.com/token')
    .setIssuedAt()
    .setExpirationTime('1h')
    .setSubject(serviceAccount.client_email)
    .sign(privateKey);

  const resp = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });

  const text = await resp.text();
  console.log('[send-ride-notification] Google token resp:', { status: resp.status, text });
  if (!resp.ok) throw new Error(`Google token fetch failed: ${resp.status} ${text}`);

  const parsed = JSON.parse(text);
  if (!parsed.access_token) throw new Error('No access_token in Google response');
  return parsed.access_token;
}

// Define types for the request body
interface NotificationRequest {
  recipient_id: string;
  sender_id?: string;
  // Backward compatibility with older payloads
  user_id?: string;
  driver_id?: string;
  guest_user_id?: string;
  recipient_key?: string;
  fcm_token?: string;
  title: string;
  body: string;
  data?: Record<string, any>;
}

// Define types for the user profile
interface UserProfile {
  fcm_token?: string;
}

interface RecipientTokenRow {
  recipient_key?: string;
  fcm_token?: string;
}

// Main function to handle HTTP requests
serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const serviceAccountRaw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT') || '{}';

    const serviceAccount = JSON.parse(serviceAccountRaw);
    const envProjectId = Deno.env.get('FIREBASE_PROJECT_ID');
    const saProjectId = serviceAccount?.project_id;
    const projectId = envProjectId || saProjectId;

    console.log('[send-ride-notification] env check:', {
      hasSupabaseUrl: Boolean(supabaseUrl),
      hasServiceRoleKey: Boolean(serviceRoleKey),
      hasServiceAccount: serviceAccountRaw !== '{}',
      envProjectId,
      saProjectId,
      projectId,
    });

    if (!projectId) {
      return new Response(
        JSON.stringify({
          error: 'Missing Firebase project id',
          details: 'Set FIREBASE_PROJECT_ID or include project_id in FIREBASE_SERVICE_ACCOUNT',
        }),
        { status: 500, headers: corsHeaders },
      );
    }

    const rawPayload: Partial<NotificationRequest> = await req.json();
    const title = rawPayload.title;
    const body = rawPayload.body;
    const data = rawPayload.data;

    const payloadToken = (rawPayload.fcm_token ?? (data as any)?.fcm_token ?? '').toString().trim();

    const payloadRecipientKeyRaw =
      rawPayload.recipient_key ??
      (data as any)?.recipient_key ??
      ((data as any)?.guest_user_id ? `guest:${String((data as any).guest_user_id)}` : undefined);
    const payloadRecipientKey = (payloadRecipientKeyRaw ?? '').toString().trim();

    const recipient_id = rawPayload.recipient_id ?? rawPayload.user_id ?? rawPayload.driver_id;
    const sender_id = rawPayload.sender_id ?? rawPayload.driver_id;

    console.log('[send-ride-notification] incoming payload:', {
      recipient_id,
      sender_id,
      title,
      body,
      dataKeys: Object.keys(data || {}),
    });

    if (!recipient_id || !title || !body) {
      return new Response(JSON.stringify({ error: 'Missing required fields: recipient_id, title, body' }), {
        status: 400,
        headers: corsHeaders,
      });
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const recipientIdStr = String(recipient_id);
    const idNum = Number(recipientIdStr);
    const recipientIdEq: any = Number.isFinite(idNum) ? idNum : recipientIdStr;
    console.log('[send-ride-notification] coerced recipient:', { recipientIdEq, type: typeof recipientIdEq });

    let fcmTokenToUse: string | null = payloadToken || null;
    let lookupDetails: any = null;

    if (!fcmTokenToUse && payloadRecipientKey) {
      const res = await supabase
        .from('recipient_fcm_tokens')
        .select('recipient_key,fcm_token')
        .eq('recipient_key', payloadRecipientKey)
        .order('updated_at', { ascending: false })
        .limit(1)
        .maybeSingle();

      const row = (res.data as RecipientTokenRow | null) ?? null;
      lookupDetails = { method: 'recipient_fcm_tokens', recipient_key: payloadRecipientKey, error: res.error };
      if (row?.fcm_token) fcmTokenToUse = String(row.fcm_token).trim();
    }

    // Legacy fallback for old payloads that only have numeric recipient_id
    if (!fcmTokenToUse) {
      let userData: UserProfile | null = null;
      let tokenErr: any = null;
      {
        const res = await supabase
          .from('lets_go_usersdata')
          .select('fcm_token')
          .eq('id', recipientIdEq)
          .single();
        userData = (res.data as any) ?? null;
        tokenErr = res.error;
        lookupDetails = { method: 'lets_go_usersdata', error: tokenErr };
      }
      if (tokenErr) {
        const res2 = await supabase
          .from('user_profiles')
          .select('fcm_token')
          .eq('id', recipientIdStr)
          .single();
        userData = (res2.data as any) ?? null;
        tokenErr = res2.error;
        lookupDetails = { method: 'user_profiles', error: tokenErr };
      }
      if (userData?.fcm_token) fcmTokenToUse = String(userData.fcm_token).trim();
    }

    console.log('[send-ride-notification] token resolved:', {
      hasPayloadToken: Boolean(payloadToken),
      payloadRecipientKey,
      lookupDetails,
      tokenLen: fcmTokenToUse?.length,
    });

    if (!fcmTokenToUse) {
      return new Response(
        JSON.stringify({
          error: 'Failed to get recipient FCM token',
          details: lookupDetails,
        }),
        { status: 400, headers: corsHeaders },
      );
    }

    const accessToken = await getAccessToken(serviceAccount);

    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    const inputData = data || {};
    const stringData: Record<string, string> = {};
    for (const [k, v] of Object.entries(inputData)) {
      if (v === null || v === undefined) continue;
      stringData[k] = typeof v === 'string' ? v : JSON.stringify(v);
    }
    // Always include title/body in data so the client can render local notifications
    // (especially when sending data-only messages).
    stringData['title'] = String(title);
    stringData['body'] = String(body);
    stringData['recipient_id'] = recipientIdStr;
    if (sender_id !== undefined && sender_id !== null) {
      stringData['sender_id'] = String(sender_id);
    }

    const fcmBody = {
      message: {
        token: fcmTokenToUse,
        // IMPORTANT: Send data-only messages so the Flutter app can always
        // generate interactive notifications (actions/inline reply) via
        // flutter_local_notifications, even when the app is in background.
        data: stringData,
        android: {
          priority: 'HIGH',
        },
      },
    };

    console.log('[send-ride-notification] FCM request:', {
      fcmUrl,
      projectId,
      tokenLen: fcmTokenToUse?.length,
      payloadKeys: Object.keys(stringData),
    });

    const fcmResp = await fetch(fcmUrl, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(fcmBody),
    });

    const fcmText = await fcmResp.text();
    console.log('[send-ride-notification] FCM response:', { status: fcmResp.status, body: fcmText });

    if (!fcmResp.ok) {
      // If the device token is stale (common after reinstall), FCM responds with
      // errorCode=UNREGISTERED. Clear the stored token so the system can recover
      // once the client re-registers a fresh token.
      try {
        const parsed = JSON.parse(fcmText);
        const errorCode = parsed?.error?.details?.[0]?.errorCode;
        if (errorCode === 'UNREGISTERED') {
          console.log('[send-ride-notification] token UNREGISTERED; clearing token for recipient', {
            recipientIdEq,
            recipientIdStr,
            payloadRecipientKey,
          });

          if (payloadRecipientKey) {
            const clearTok = await supabase
              .from('recipient_fcm_tokens')
              .update({ fcm_token: null })
              .eq('recipient_key', payloadRecipientKey);
            console.log('[send-ride-notification] cleared recipient_fcm_tokens token:', { error: clearTok.error });
          }

          const clear1 = await supabase
            .from('lets_go_usersdata')
            .update({ fcm_token: null })
            .eq('id', recipientIdEq);
          console.log('[send-ride-notification] cleared lets_go_usersdata token:', { error: clear1.error });

          const clear2 = await supabase
            .from('user_profiles')
            .update({ fcm_token: null })
            .eq('id', recipientIdStr);
          console.log('[send-ride-notification] cleared user_profiles token:', { error: clear2.error });
        }
      } catch (_) {}

      return new Response(JSON.stringify({ error: 'Failed to send notification', details: fcmText }), {
        status: fcmResp.status,
        headers: corsHeaders,
      });
    }

    return new Response(JSON.stringify({ success: true, message: 'Notification sent', raw: fcmText }), {
      headers: corsHeaders,
    });
  } catch (error) {
    console.error('Error in send-ride-notification:', error);
    return new Response(
      JSON.stringify({ 
        error: 'Internal server error',
        details: error instanceof Error ? error.message : String(error)
      }),
      { status: 500, headers: { ...corsHeaders } }
    );
  }
});
