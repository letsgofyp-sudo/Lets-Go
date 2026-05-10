/*
// supabase/functions/register-fcm-token/index.ts
// register-fcm-token (Edge Function)
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: corsHeaders,
    });
  }

  try {
    const supabaseUrl = Deno.env.get('_SUPABASE_URL') ?? '';
    const serviceRoleKey = Deno.env.get('_SUPABASE_SERVICE_ROLE_KEY') ?? '';
    console.log('[register-fcm-token] env check:', {
      hasSupabaseUrl: Boolean(supabaseUrl),
      hasServiceRoleKey: Boolean(serviceRoleKey),
    });

    const { user_id, fcm_token, platform, device_id } = await req.json();
    const idNum = typeof user_id === 'string' ? Number(user_id) : user_id;

    // Basic validation
    if (!Number.isInteger(idNum) || idNum <= 0) {
      return new Response(JSON.stringify({ error: 'Invalid user_id' }), {
        status: 400,
        headers: corsHeaders,
      });
    }
    if (!fcm_token || typeof fcm_token !== 'string' || fcm_token.trim().length < 20) {
      return new Response(JSON.stringify({ error: 'Invalid fcm_token' }), {
        status: 400,
        headers: corsHeaders,
      });
    }

    console.log('[register-fcm-token] payload:', {
      user_id: idNum,
      fcm_token_len: fcm_token.length,
      platform: platform ?? null,
      device_id: device_id ?? null,
    });

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // Ensure user exists
    const { data: existing, error: existErr } = await supabase
      .from('lets_go_usersdata')
      .select('id, fcm_token')
      .eq('id', idNum)
      .single();

    if (existErr || !existing) {
      return new Response(JSON.stringify({ error: 'User not found', user_id: idNum }), {
        status: 404,
        headers: corsHeaders,
      });
    }

    // Optional: short-circuit if unchanged token
    if (existing.fcm_token === fcm_token) {
      return new Response(JSON.stringify({ success: true, updated: { id: idNum, fcm_token } }), {
        status: 200,
        headers: corsHeaders,
      });
    }

    // Option A: Single-token per user (backward compat)
    const { data: updatedRows, error: updateErr } = await supabase
      .from('lets_go_usersdata')
      .update({ fcm_token })
      .eq('id', idNum)
      .select('id, fcm_token');

    if (updateErr) {
      return new Response(JSON.stringify({ error: 'Failed to store fcm_token' }), {
        status: 500,
        headers: corsHeaders,
      });
    }

    // Option B (recommended): Multi-device tokens (uncomment when table exists)
    // await supabase.from('user_device_tokens').upsert({
    //   user_id: idNum,
    //   token: fcm_token,
    //   platform: platform ?? null,
    //   device_id: device_id ?? null,
    //   last_seen: new Date().toISOString(),
    // }, { onConflict: 'token' });

    const status = existing.fcm_token ? 200 : 201;
    return new Response(JSON.stringify({ success: true, updated: updatedRows?.[0] ?? { id: idNum, fcm_token } }), {
      status,
      headers: corsHeaders,
    });
  } catch (err) {
    console.error('[register-fcm-token] unexpected error:', err);
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: corsHeaders,
    });
  }
});
*/
// Follows the Supabase Edge Functions template
// Docs: https://supabase.com/docs/guides/functions

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// CORS headers for the response
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};

interface RegisterTokenRequest {
  recipient_key: string;
  fcm_token: string;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

    if (!supabaseUrl || !serviceRoleKey) {
      return new Response(JSON.stringify({ error: 'Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY' }), {
        status: 500,
        headers: corsHeaders,
      });
    }

    const raw: Partial<RegisterTokenRequest> = await req.json();
    const recipient_key = (raw.recipient_key ?? '').toString().trim();
    const fcm_token = (raw.fcm_token ?? '').toString().trim();

    if (!recipient_key || !fcm_token || fcm_token === 'NO_FCM_TOKEN') {
      return new Response(JSON.stringify({ error: 'recipient_key and fcm_token are required' }), {
        status: 400,
        headers: corsHeaders,
      });
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const res = await supabase
      .from('recipient_fcm_tokens')
      .upsert(
        {
          recipient_key,
          fcm_token,
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'recipient_key' },
      )
      .select('recipient_key')
      .maybeSingle();

    if (res.error) {
      return new Response(JSON.stringify({ error: 'Failed to register token', details: res.error }), {
        status: 500,
        headers: corsHeaders,
      });
    }

    return new Response(JSON.stringify({ success: true, recipient_key }), {
      headers: corsHeaders,
    });
  } catch (error) {
    return new Response(
      JSON.stringify({
        error: 'Internal server error',
        details: error instanceof Error ? error.message : String(error),
      }),
      { status: 500, headers: corsHeaders },
    );
  }
});
