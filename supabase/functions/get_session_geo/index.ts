/**
 * Edge function: get_session_geo
 * 
 * Returns coarse geo dimensions from request headers (Cloudflare/Deno Deploy).
 * Privacy-first: No IP logging, only country/region/city codes.
 * 
 * Auth: Accepts apikey header (Supabase anon key) for public access.
 *       No authenticated session required.
 * 
 * Response: { ok: true, country_code, region, city_code }
 * 
 * Deploy with: supabase functions deploy get_session_geo --no-verify-jwt
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
}

function jsonResponse(body: object, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...corsHeaders,
    },
  })
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 200, headers: corsHeaders })
  }

  const headers = req.headers

  // ==========================================================================
  // AUTH CHECK: Allow requests with apikey OR Authorization header
  // This function is privacy-safe and returns only coarse geo data,
  // so we allow public access via anon key.
  // ==========================================================================
  const apikey = headers.get('apikey')
  const authorization = headers.get('authorization')

  if (!apikey && !authorization) {
    console.log('[get_session_geo] 401: Missing apikey and authorization')
    return jsonResponse({ ok: false, error: 'Missing authorization' }, 401)
  }

  try {
    // Extract geo from various header sources (Cloudflare, Deno Deploy, Vercel)
    
    // Country code (ISO 3166-1 alpha-2)
    // Cloudflare: CF-IPCountry
    // Deno Deploy: uses Cloudflare under the hood
    const country_code = 
      headers.get('cf-ipcountry') ||
      headers.get('x-vercel-ip-country') ||
      headers.get('x-country-code') ||
      null

    // Region/state code
    // Cloudflare: CF-Region (not always available)
    // Vercel: X-Vercel-IP-Country-Region
    const region = 
      headers.get('cf-region') ||
      headers.get('x-vercel-ip-country-region') ||
      headers.get('x-region') ||
      null

    // City (coarse, for analytics bucketing)
    // Cloudflare: CF-IPCity
    // Vercel: X-Vercel-IP-City
    const city_code = 
      headers.get('cf-ipcity') ||
      headers.get('x-vercel-ip-city') ||
      headers.get('x-city') ||
      null

    // Log for debugging (no IP!)
    console.log('[get_session_geo]', { country_code, region, city_code })

    return jsonResponse({
      ok: true,
      country_code: country_code?.toUpperCase() || null,
      region: region || null,
      city_code: city_code?.toLowerCase().replace(/\s+/g, '_') || null,
    })

  } catch (err) {
    console.error('[get_session_geo] Error:', err)
    return jsonResponse({ ok: false, error: 'Internal error' }, 500)
  }
})
