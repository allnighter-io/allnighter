-- Let authenticated users provision their own relay JWT claims once.
-- Claims are copied into access tokens by custom_access_token_hook.

CREATE OR REPLACE FUNCTION public.provision_mac_agent_claim(p_mac_agent_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  uid uuid := auth.uid();
  existing text;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  IF p_mac_agent_id IS NULL THEN
    RAISE EXCEPTION 'mac_agent_id required';
  END IF;

  SELECT NULLIF(BTRIM(raw_app_meta_data->>'mac_agent_id'), '')
    INTO existing
  FROM auth.users
  WHERE id = uid;

  IF existing IS NOT NULL AND existing <> p_mac_agent_id::text THEN
    RAISE EXCEPTION 'mac_agent_id already provisioned';
  END IF;

  UPDATE auth.users
  SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb)
    || jsonb_build_object('mac_agent_id', p_mac_agent_id::text)
  WHERE id = uid;

  RETURN jsonb_build_object('mac_agent_id', p_mac_agent_id::text);
END;
$$;

CREATE OR REPLACE FUNCTION public.provision_remote_device_claim(p_remote_device_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  uid uuid := auth.uid();
  existing text;
  trimmed text;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  trimmed := NULLIF(BTRIM(p_remote_device_id), '');
  IF trimmed IS NULL THEN
    RAISE EXCEPTION 'remote_device_id required';
  END IF;

  SELECT NULLIF(BTRIM(raw_app_meta_data->>'remote_device_id'), '')
    INTO existing
  FROM auth.users
  WHERE id = uid;

  IF existing IS NOT NULL AND existing <> trimmed THEN
    RAISE EXCEPTION 'remote_device_id already provisioned';
  END IF;

  UPDATE auth.users
  SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb)
    || jsonb_build_object('remote_device_id', trimmed)
  WHERE id = uid;

  RETURN jsonb_build_object('remote_device_id', trimmed);
END;
$$;

REVOKE ALL ON FUNCTION public.provision_mac_agent_claim(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.provision_remote_device_claim(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.provision_mac_agent_claim(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.provision_remote_device_claim(text) TO authenticated;
