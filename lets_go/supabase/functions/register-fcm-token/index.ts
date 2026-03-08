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
