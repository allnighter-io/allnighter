-- Pending queue on thread snapshots + remote command kinds for iOS pending control.
-- Idempotent against remotes that predate parts of 20260621020800_remote_schema.sql.

ALTER TABLE "public"."command_inbox" DROP CONSTRAINT IF EXISTS "command_inbox_kind_check";
ALTER TABLE "public"."command_inbox"
    ADD CONSTRAINT "command_inbox_kind_check" CHECK (("kind" = ANY (ARRAY['startRun'::"text", 'stopRun'::"text", 'thread.mark_read'::"text", 'stopAll'::"text", 'pending.cancel'::"text", 'pending.edit'::"text", 'pending.submit'::"text"])));

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'command_acks'
          AND column_name = 'audit_command_kind'
    ) THEN
        ALTER TABLE "public"."command_acks" DROP CONSTRAINT IF EXISTS "command_acks_audit_command_kind_check";
        ALTER TABLE "public"."command_acks"
            ADD CONSTRAINT "command_acks_audit_command_kind_check" CHECK (("audit_command_kind" = ANY (ARRAY['startRun'::"text", 'stopRun'::"text", 'thread.mark_read'::"text", 'stopAll'::"text", 'pending.cancel'::"text", 'pending.edit'::"text", 'pending.submit'::"text"])));
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS "public"."thread_snapshot_envelopes" (
    "account_id" "uuid" NOT NULL,
    "mac_agent_id" "uuid" NOT NULL,
    "threads" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "server_time" timestamp with time zone NOT NULL DEFAULT "now"(),
    "protocol_version" integer NOT NULL DEFAULT 1,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE "public"."thread_snapshot_envelopes"
    ADD COLUMN IF NOT EXISTS "pending_queue" jsonb;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'thread_snapshot_envelopes_pkey'
    ) THEN
        ALTER TABLE ONLY "public"."thread_snapshot_envelopes"
            ADD CONSTRAINT "thread_snapshot_envelopes_pkey" PRIMARY KEY ("account_id", "mac_agent_id");
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'thread_snapshot_envelopes_protocol_version_check'
    ) THEN
        ALTER TABLE ONLY "public"."thread_snapshot_envelopes"
            ADD CONSTRAINT "thread_snapshot_envelopes_protocol_version_check" CHECK (("protocol_version" = 1));
    END IF;

    IF to_regclass('public.mac_agents') IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM pg_constraint WHERE conname = 'thread_snapshot_envelopes_mac_agent_id_fkey'
       ) THEN
        ALTER TABLE ONLY "public"."thread_snapshot_envelopes"
            ADD CONSTRAINT "thread_snapshot_envelopes_mac_agent_id_fkey"
            FOREIGN KEY ("mac_agent_id") REFERENCES "public"."mac_agents"("id") ON DELETE CASCADE;
    END IF;

    IF to_regnamespace('auth') IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM pg_constraint WHERE conname = 'thread_snapshot_envelopes_account_id_fkey'
       ) THEN
        ALTER TABLE ONLY "public"."thread_snapshot_envelopes"
            ADD CONSTRAINT "thread_snapshot_envelopes_account_id_fkey"
            FOREIGN KEY ("account_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
    END IF;
END $$;

ALTER TABLE "public"."thread_snapshot_envelopes" ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF to_regprocedure('public.mac_agent_claim_matches(uuid,uuid)') IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM pg_policies
           WHERE schemaname = 'public'
             AND tablename = 'thread_snapshot_envelopes'
             AND policyname = 'mac agents insert thread snapshot envelopes'
       ) THEN
        CREATE POLICY "mac agents insert thread snapshot envelopes"
            ON "public"."thread_snapshot_envelopes"
            FOR INSERT TO "authenticated"
            WITH CHECK ("public"."mac_agent_claim_matches"("account_id", "mac_agent_id"));
    END IF;

    IF to_regprocedure('public.mac_agent_claim_matches(uuid,uuid)') IS NOT NULL
       AND to_regprocedure('public.approved_remote_device(uuid,text)') IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM pg_policies
           WHERE schemaname = 'public'
             AND tablename = 'thread_snapshot_envelopes'
             AND policyname = 'approved devices select thread snapshot envelopes'
       ) THEN
        CREATE POLICY "approved devices select thread snapshot envelopes"
            ON "public"."thread_snapshot_envelopes"
            FOR SELECT TO "authenticated"
            USING ((
                "public"."mac_agent_claim_matches"("account_id", "mac_agent_id")
                OR "public"."approved_remote_device"("mac_agent_id", "public"."remote_device_id"())
            ));
    END IF;

    IF to_regprocedure('public.mac_agent_claim_matches(uuid,uuid)') IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM pg_policies
           WHERE schemaname = 'public'
             AND tablename = 'thread_snapshot_envelopes'
             AND policyname = 'mac agents update thread snapshot envelopes'
       ) THEN
        CREATE POLICY "mac agents update thread snapshot envelopes"
            ON "public"."thread_snapshot_envelopes"
            FOR UPDATE TO "authenticated"
            USING ("public"."mac_agent_claim_matches"("account_id", "mac_agent_id"))
            WITH CHECK ("public"."mac_agent_claim_matches"("account_id", "mac_agent_id"));
    END IF;
END $$;

GRANT ALL ON TABLE "public"."thread_snapshot_envelopes" TO "anon";
GRANT ALL ON TABLE "public"."thread_snapshot_envelopes" TO "authenticated";
GRANT ALL ON TABLE "public"."thread_snapshot_envelopes" TO "service_role";
