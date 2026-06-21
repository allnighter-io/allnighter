


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."command_acks" (
    "request_id" "text" NOT NULL,
    "mac_agent_id" "uuid" NOT NULL,
    "accepted" boolean NOT NULL,
    "reason" "text",
    "outcome" "text" NOT NULL,
    "sig" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."command_acks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."command_inbox" (
    "request_id" "text" NOT NULL,
    "account_id" "uuid" NOT NULL,
    "mac_agent_id" "uuid" NOT NULL,
    "from_device_id" "text" NOT NULL,
    "kind" "text" NOT NULL,
    "payload" "jsonb" NOT NULL,
    "signature" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL
);


ALTER TABLE "public"."command_inbox" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."event_envelopes" (
    "id" "text" NOT NULL,
    "seq" bigint NOT NULL,
    "ts" timestamp with time zone NOT NULL,
    "account_id" "uuid" NOT NULL,
    "mac_agent_id" "uuid" NOT NULL,
    "run_id" "text",
    "kind" "text" NOT NULL,
    "light_payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "sealed_ref" "text",
    "sig" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."event_envelopes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mac_agents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "account_id" "uuid" NOT NULL,
    "display_name" "text" NOT NULL,
    "agent_signing_pubkey" "text" NOT NULL,
    "agent_sealing_pubkey" "text" NOT NULL,
    "last_seen_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."mac_agents" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."media_keys" (
    "ref" "text" NOT NULL,
    "device_id" "text" NOT NULL,
    "sealed_key" "jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."media_keys" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."media_refs" (
    "ref" "text" NOT NULL,
    "mac_agent_id" "uuid" NOT NULL,
    "r2_key" "text" NOT NULL,
    "content_type" "text" NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."media_refs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pair_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "account_id" "uuid" NOT NULL,
    "mac_agent_id" "uuid" NOT NULL,
    "device_id" "text" NOT NULL,
    "display_name" "text" NOT NULL,
    "device_signing_pubkey" "text" NOT NULL,
    "device_sealing_pubkey" "text" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "approved_at" timestamp with time zone,
    "rejected_at" timestamp with time zone
);


ALTER TABLE "public"."pair_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."trusted_devices" (
    "device_id" "text" NOT NULL,
    "account_id" "uuid" NOT NULL,
    "mac_agent_id" "uuid" NOT NULL,
    "display_name" "text" NOT NULL,
    "device_signing_pubkey" "text" NOT NULL,
    "device_sealing_pubkey" "text" NOT NULL,
    "paired_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "valid_until" timestamp with time zone NOT NULL,
    "revoked" boolean DEFAULT false NOT NULL,
    "revoked_at" timestamp with time zone,
    "last_seen_at" timestamp with time zone,
    "capabilities" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL
);


ALTER TABLE "public"."trusted_devices" OWNER TO "postgres";


ALTER TABLE ONLY "public"."command_acks"
    ADD CONSTRAINT "command_acks_pkey" PRIMARY KEY ("request_id");



ALTER TABLE ONLY "public"."command_inbox"
    ADD CONSTRAINT "command_inbox_pkey" PRIMARY KEY ("request_id");



ALTER TABLE ONLY "public"."event_envelopes"
    ADD CONSTRAINT "event_envelopes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mac_agents"
    ADD CONSTRAINT "mac_agents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."media_keys"
    ADD CONSTRAINT "media_keys_pkey" PRIMARY KEY ("ref", "device_id");



ALTER TABLE ONLY "public"."media_refs"
    ADD CONSTRAINT "media_refs_pkey" PRIMARY KEY ("ref");



ALTER TABLE ONLY "public"."pair_requests"
    ADD CONSTRAINT "pair_requests_mac_agent_id_device_id_key" UNIQUE ("mac_agent_id", "device_id");



ALTER TABLE ONLY "public"."pair_requests"
    ADD CONSTRAINT "pair_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."trusted_devices"
    ADD CONSTRAINT "trusted_devices_pkey" PRIMARY KEY ("device_id");



CREATE INDEX "event_envelopes_mac_seq_idx" ON "public"."event_envelopes" USING "btree" ("mac_agent_id", "seq");



CREATE INDEX "pair_requests_mac_status_idx" ON "public"."pair_requests" USING "btree" ("mac_agent_id", "status");



ALTER TABLE ONLY "public"."command_acks"
    ADD CONSTRAINT "command_acks_mac_agent_id_fkey" FOREIGN KEY ("mac_agent_id") REFERENCES "public"."mac_agents"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."command_acks"
    ADD CONSTRAINT "command_acks_request_id_fkey" FOREIGN KEY ("request_id") REFERENCES "public"."command_inbox"("request_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."command_inbox"
    ADD CONSTRAINT "command_inbox_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."command_inbox"
    ADD CONSTRAINT "command_inbox_from_device_id_fkey" FOREIGN KEY ("from_device_id") REFERENCES "public"."trusted_devices"("device_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."command_inbox"
    ADD CONSTRAINT "command_inbox_mac_agent_id_fkey" FOREIGN KEY ("mac_agent_id") REFERENCES "public"."mac_agents"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."event_envelopes"
    ADD CONSTRAINT "event_envelopes_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."event_envelopes"
    ADD CONSTRAINT "event_envelopes_mac_agent_id_fkey" FOREIGN KEY ("mac_agent_id") REFERENCES "public"."mac_agents"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."mac_agents"
    ADD CONSTRAINT "mac_agents_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."media_keys"
    ADD CONSTRAINT "media_keys_device_id_fkey" FOREIGN KEY ("device_id") REFERENCES "public"."trusted_devices"("device_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."media_keys"
    ADD CONSTRAINT "media_keys_ref_fkey" FOREIGN KEY ("ref") REFERENCES "public"."media_refs"("ref") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."media_refs"
    ADD CONSTRAINT "media_refs_mac_agent_id_fkey" FOREIGN KEY ("mac_agent_id") REFERENCES "public"."mac_agents"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."pair_requests"
    ADD CONSTRAINT "pair_requests_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."pair_requests"
    ADD CONSTRAINT "pair_requests_mac_agent_id_fkey" FOREIGN KEY ("mac_agent_id") REFERENCES "public"."mac_agents"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."trusted_devices"
    ADD CONSTRAINT "trusted_devices_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."trusted_devices"
    ADD CONSTRAINT "trusted_devices_mac_agent_id_fkey" FOREIGN KEY ("mac_agent_id") REFERENCES "public"."mac_agents"("id") ON DELETE CASCADE;



ALTER TABLE "public"."command_acks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."command_inbox" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."event_envelopes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."mac_agents" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."media_keys" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."media_refs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pair_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."trusted_devices" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "users insert own command acks" ON "public"."command_acks" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."mac_agents" "m"
  WHERE (("m"."id" = "command_acks"."mac_agent_id") AND ("m"."account_id" = "auth"."uid"())))));



CREATE POLICY "users insert own command inbox" ON "public"."command_inbox" FOR INSERT TO "authenticated" WITH CHECK (("account_id" = "auth"."uid"()));



CREATE POLICY "users insert own event envelopes" ON "public"."event_envelopes" FOR INSERT TO "authenticated" WITH CHECK (("account_id" = "auth"."uid"()));



CREATE POLICY "users insert own mac agents" ON "public"."mac_agents" FOR INSERT TO "authenticated" WITH CHECK (("account_id" = "auth"."uid"()));



CREATE POLICY "users insert own media keys" ON "public"."media_keys" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."trusted_devices" "d"
  WHERE (("d"."device_id" = "media_keys"."device_id") AND ("d"."account_id" = "auth"."uid"())))));



CREATE POLICY "users insert own media refs" ON "public"."media_refs" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."mac_agents" "m"
  WHERE (("m"."id" = "media_refs"."mac_agent_id") AND ("m"."account_id" = "auth"."uid"())))));



CREATE POLICY "users insert own pair requests" ON "public"."pair_requests" FOR INSERT TO "authenticated" WITH CHECK (("account_id" = "auth"."uid"()));



CREATE POLICY "users insert own trusted devices" ON "public"."trusted_devices" FOR INSERT TO "authenticated" WITH CHECK (("account_id" = "auth"."uid"()));



CREATE POLICY "users select own command acks" ON "public"."command_acks" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."mac_agents" "m"
  WHERE (("m"."id" = "command_acks"."mac_agent_id") AND ("m"."account_id" = "auth"."uid"())))));



CREATE POLICY "users select own command inbox" ON "public"."command_inbox" FOR SELECT TO "authenticated" USING (("account_id" = "auth"."uid"()));



CREATE POLICY "users select own event envelopes" ON "public"."event_envelopes" FOR SELECT TO "authenticated" USING (("account_id" = "auth"."uid"()));



CREATE POLICY "users select own mac agents" ON "public"."mac_agents" FOR SELECT TO "authenticated" USING (("account_id" = "auth"."uid"()));



CREATE POLICY "users select own media keys" ON "public"."media_keys" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."trusted_devices" "d"
  WHERE (("d"."device_id" = "media_keys"."device_id") AND ("d"."account_id" = "auth"."uid"())))));



CREATE POLICY "users select own media refs" ON "public"."media_refs" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."mac_agents" "m"
  WHERE (("m"."id" = "media_refs"."mac_agent_id") AND ("m"."account_id" = "auth"."uid"())))));



CREATE POLICY "users select own pair requests" ON "public"."pair_requests" FOR SELECT TO "authenticated" USING (("account_id" = "auth"."uid"()));



CREATE POLICY "users select own trusted devices" ON "public"."trusted_devices" FOR SELECT TO "authenticated" USING (("account_id" = "auth"."uid"()));



CREATE POLICY "users update own command inbox" ON "public"."command_inbox" FOR UPDATE TO "authenticated" USING (("account_id" = "auth"."uid"())) WITH CHECK (("account_id" = "auth"."uid"()));



CREATE POLICY "users update own mac agents" ON "public"."mac_agents" FOR UPDATE TO "authenticated" USING (("account_id" = "auth"."uid"())) WITH CHECK (("account_id" = "auth"."uid"()));



CREATE POLICY "users update own pair requests" ON "public"."pair_requests" FOR UPDATE TO "authenticated" USING (("account_id" = "auth"."uid"())) WITH CHECK (("account_id" = "auth"."uid"()));



CREATE POLICY "users update own trusted devices" ON "public"."trusted_devices" FOR UPDATE TO "authenticated" USING (("account_id" = "auth"."uid"())) WITH CHECK (("account_id" = "auth"."uid"()));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";






















































































































































GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "anon";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "service_role";


















GRANT ALL ON TABLE "public"."command_acks" TO "anon";
GRANT ALL ON TABLE "public"."command_acks" TO "authenticated";
GRANT ALL ON TABLE "public"."command_acks" TO "service_role";



GRANT ALL ON TABLE "public"."command_inbox" TO "anon";
GRANT ALL ON TABLE "public"."command_inbox" TO "authenticated";
GRANT ALL ON TABLE "public"."command_inbox" TO "service_role";



GRANT ALL ON TABLE "public"."event_envelopes" TO "anon";
GRANT ALL ON TABLE "public"."event_envelopes" TO "authenticated";
GRANT ALL ON TABLE "public"."event_envelopes" TO "service_role";



GRANT ALL ON TABLE "public"."mac_agents" TO "anon";
GRANT ALL ON TABLE "public"."mac_agents" TO "authenticated";
GRANT ALL ON TABLE "public"."mac_agents" TO "service_role";



GRANT ALL ON TABLE "public"."media_keys" TO "anon";
GRANT ALL ON TABLE "public"."media_keys" TO "authenticated";
GRANT ALL ON TABLE "public"."media_keys" TO "service_role";



GRANT ALL ON TABLE "public"."media_refs" TO "anon";
GRANT ALL ON TABLE "public"."media_refs" TO "authenticated";
GRANT ALL ON TABLE "public"."media_refs" TO "service_role";



GRANT ALL ON TABLE "public"."pair_requests" TO "anon";
GRANT ALL ON TABLE "public"."pair_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."pair_requests" TO "service_role";



GRANT ALL ON TABLE "public"."trusted_devices" TO "anon";
GRANT ALL ON TABLE "public"."trusted_devices" TO "authenticated";
GRANT ALL ON TABLE "public"."trusted_devices" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";



































drop extension if exists "pg_net";


