-- Extend remote command kinds for iOS pending queue control.
ALTER TABLE "public"."command_inbox" DROP CONSTRAINT IF EXISTS "command_inbox_kind_check";
ALTER TABLE "public"."command_inbox"
    ADD CONSTRAINT "command_inbox_kind_check" CHECK (("kind" = ANY (ARRAY['startRun'::"text", 'stopRun'::"text", 'thread.mark_read'::"text", 'stopAll'::"text", 'pending.cancel'::"text", 'pending.edit'::"text", 'pending.submit'::"text"])));

ALTER TABLE "public"."command_acks" DROP CONSTRAINT IF EXISTS "command_acks_audit_command_kind_check";
ALTER TABLE "public"."command_acks"
    ADD CONSTRAINT "command_acks_audit_command_kind_check" CHECK (("audit_command_kind" = ANY (ARRAY['startRun'::"text", 'stopRun'::"text", 'thread.mark_read'::"text", 'stopAll'::"text", 'pending.cancel'::"text", 'pending.edit'::"text", 'pending.submit'::"text"])));

-- Thread snapshot relay may carry the Mac pending queue alongside thread summaries.
ALTER TABLE "public"."thread_snapshot_envelopes"
    ADD COLUMN IF NOT EXISTS "pending_queue" jsonb;
