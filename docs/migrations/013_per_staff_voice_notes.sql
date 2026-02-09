-- Migration 013: Per-staff voice notes opt-in
-- Voice notes become a premium per-staff add-on (PKR 5,000/staff/month).
-- Existing staff default to OFF (admin enables via WhatsApp or signup).

ALTER TABLE staff ADD COLUMN IF NOT EXISTS voice_notes_enabled BOOLEAN DEFAULT false;

COMMENT ON COLUMN staff.voice_notes_enabled IS 'Per-staff premium opt-in for voice note delivery. false=text only, true=audio+text. PKR 5,000/staff/month.';
