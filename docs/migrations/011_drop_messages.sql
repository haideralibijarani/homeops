-- Migration 011: Drop unused messages table
-- The messages table was defined but never used by any workflow.
-- WF1-TWILIO INBOUND has no "Log Message" node; WF2-PROCESSOR never reads from it.

DROP INDEX IF EXISTS idx_messages_household_id;
DROP TABLE IF EXISTS messages;
