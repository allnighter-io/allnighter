-- Fix custom_access_token_hook to read mac_agent_id from claims.app_metadata.

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  original_claims jsonb;
  new_claims jsonb;
  app_meta jsonb;
  mac_agent_id text;
  remote_device_id text;
BEGIN
  original_claims := event->'claims';
  app_meta := COALESCE(original_claims->'app_metadata', '{}'::jsonb);
  new_claims := original_claims;

  mac_agent_id := NULLIF(BTRIM(app_meta->>'mac_agent_id'), '');
  IF mac_agent_id IS NOT NULL
     AND mac_agent_id ~* '^[0-9a-f-]{8}-[0-9a-f-]{4}-[0-9a-f-]{4}-[0-9a-f-]{4}-[0-9a-f-]{12}$' THEN
    new_claims := jsonb_set(new_claims, '{mac_agent_id}', to_jsonb(mac_agent_id), true);
  END IF;

  remote_device_id := NULLIF(BTRIM(app_meta->>'remote_device_id'), '');
  IF remote_device_id IS NOT NULL THEN
    new_claims := jsonb_set(new_claims, '{remote_device_id}', to_jsonb(remote_device_id), true);
  END IF;

  RETURN jsonb_build_object('claims', new_claims);
END;
$$;

REVOKE ALL ON FUNCTION public.custom_access_token_hook(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) TO supabase_auth_admin;
