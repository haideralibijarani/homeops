# HomeOps Workflow Analysis

**Date:** 2026-01-26
**Analyzed by:** Claude (n8n MCP)
**Workflows:** WF1-TWILIO INBOUND + WF2-PROCESSOR

---

## Current Architecture

### WF1-TWILIO INBOUND (4 nodes)
```
Webhook → Normalise Input → Respond to Webhook → Execute WF2-PROCESSOR
```

**Purpose:** Receives Twilio WhatsApp webhooks and delegates processing

**Strengths:**
- ✅ Immediate webhook response (prevents Twilio retries)
- ✅ Clean separation of concerns (receiver vs processor)
- ✅ Proper input normalization

---

### WF2-PROCESSOR (26 nodes)

**Current Flow:**
```
Trigger
  ↓
IF (is Audio?)
  ├─ Yes → Download Media → Transcribe → Transcript Text
  └─ No → Body Text
         ↓
    Unify Input
         ↓
  Pending Lookup
         ↓
  IF (Pending Found?)
  ├─ Yes → Merge Reply Into Payload
  └─ No → Member Lookup → Pick Household
                ↓
          IF (Household Found?)
          ├─ Yes → OpenAI Classify Intent → Extract JSON
          │          ↓
          │    IF (Needs Clarification?)
          │    ├─ Yes → Pending State → Twilio Send
          │    └─ No → Switch Intent
          │              ├─ create_task → Insert Task → Twilio Send
          │              ├─ complete_task → (not implemented)
          │              ├─ list_tasks → (not implemented)
          │              └─ unknown → Twilio Send Error
          │
          └─ No → Twilio Send Onboarding
```

---

## Alignment with HomeOps Architecture

### ✅ Implemented Components

1. **Normalize Input** - WF1 extracts all Twilio fields correctly
2. **Audio Handling** - WF2 checks for audio, downloads, transcribes via OpenAI Whisper
3. **Intent Classification** - WF2 uses OpenAI to classify intents
4. **Clarification Gate** - WF2 stores pending state and asks questions
5. **Action Execution** - WF2 creates tasks in Supabase
6. **User Feedback** - WF2 sends confirmations via Twilio

### ⚠️ Missing/Incomplete Components

#### 1. **Message Audit Logging**
- **Gap:** No logging to `messages` table
- **Impact:** No audit trail of inbound/outbound messages
- **Required Fields:** household_id, direction, from_number, to_number, msg_type, media_url, transcript, payload_json

#### 2. **Staff Lookup**
- **Gap:** Only `Member Lookup` exists, no `Staff` table integration
- **Impact:** Cannot assign tasks to household staff
- **Required:** Add staff lookup and assignee resolution logic

#### 3. **Task Completion Flow**
- **Gap:** `complete_task` intent has no implementation
- **Impact:** Users cannot mark tasks complete via WhatsApp
- **Required:** Update task status in Supabase, notify assignee

#### 4. **Task List Flow**
- **Gap:** `list_tasks` intent has no implementation
- **Impact:** Users cannot query pending tasks
- **Required:** Query Supabase tasks, format response

#### 5. **Assignee Resolution**
- **Gap:** No logic to resolve assignee_name → assignee_id
- **Impact:** Tasks created without proper assignment
- **Required:** Lookup member/staff by name, store assignee_id

#### 6. **Error Handling**
- **Gap:** Limited error handling for API failures
- **Impact:** Silent failures, no retry logic
- **Required:** Try-catch nodes, error notifications

#### 7. **WhatsApp Prefix Removal**
- **Issue:** Current normalization uses `$json.body.From` directly
- **Problem:** May include `whatsapp:+` prefix
- **Fix:** Strip prefix in WF1 normalization

---

## Proposed Improvements

### Priority 1: Critical Gaps

1. **Add Message Logging**
   - Location: After WF1 normalization
   - Action: Insert to `messages` table with all fields
   - Node: Supabase Insert

2. **Fix WhatsApp Prefix Removal**
   - Location: WF1 "Normalise Input" node
   - Current: `{{$json.body.From}}`
   - Fixed: `{{$json.body.From.replace('whatsapp:', '')}}`

3. **Add Staff Lookup**
   - Location: After Member Lookup in WF2
   - Logic: If member not found, lookup in staff table
   - Node: Supabase Select (staff table)

4. **Implement Assignee Resolution**
   - Location: Before Insert Task
   - Logic: Match assignee_name against members/staff
   - Node: Code node to resolve ID

### Priority 2: Missing Intents

5. **Complete Task Flow**
   - Location: Switch node (complete_task case)
   - Nodes:
     - Supabase: Find task by title/ID
     - Supabase: Update task.status = 'completed'
     - Supabase: Set task.completed_at = now()
     - Twilio: Send confirmation

6. **List Tasks Flow**
   - Location: Switch node (list_tasks case)
   - Nodes:
     - Supabase: Query tasks WHERE household_id + status='pending'
     - Code: Format task list as WhatsApp message
     - Twilio: Send task list

### Priority 3: Production Hardening

7. **Add Error Handling**
   - Location: Around all external API calls
   - Nodes: Error Workflow trigger, logging, fallback responses

8. **Add Idempotency Check**
   - Location: Start of WF2
   - Logic: Check if MessageSid already processed
   - Node: Supabase lookup on messages table

9. **Add Retry Logic**
   - Location: OpenAI nodes
   - Logic: Retry on rate limit / timeout
   - Node: Loop with delay

---

## Data Model Validation

### Required Supabase Tables

#### ✅ Implemented
- `members` - Member lookup exists
- `tasks` - Insert Task exists
- `pending_actions` - Pending State exists

#### ❌ Missing Integration
- `households` - Referenced but no explicit lookup
- `staff` - Not integrated
- `messages` - Not being written

#### Recommended Schema Checks
```sql
-- Verify tables exist
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
AND table_name IN ('households', 'members', 'staff', 'tasks', 'pending_actions', 'messages');

-- Check messages table structure
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'messages';
```

---

## Next Steps

### Immediate Actions (Do First)

1. **Fix WhatsApp prefix removal** in WF1
2. **Add message logging** after normalization
3. **Validate Supabase schema** matches docs/schema.sql

### Short-term (This Week)

4. **Add staff lookup** to WF2
5. **Implement assignee resolution**
6. **Build complete_task flow**
7. **Build list_tasks flow**

### Medium-term (Next Sprint)

8. **Add comprehensive error handling**
9. **Implement idempotency checks**
10. **Add monitoring/alerting**

---

## Testing Checklist

### Scenarios to Test

- [ ] Text message → Create task (member assignment)
- [ ] Text message → Create task (staff assignment)
- [ ] Voice note → Transcribe → Create task
- [ ] Incomplete request → Clarification question
- [ ] Multi-turn clarification → Task creation
- [ ] Complete task via WhatsApp
- [ ] List tasks via WhatsApp
- [ ] Unknown member → Onboarding flow
- [ ] Audio transcription failure → Fallback
- [ ] OpenAI API failure → Error handling

---

## Workflow Efficiency Metrics

**Current Node Count:** 30 total (4 + 26)
**Estimated Execution Time:** 3-8 seconds (depending on audio/LLM)
**External API Calls:** 2-4 per message (Twilio, OpenAI x1-2, Supabase x2-4)

**Optimization Opportunities:**
- Parallel execution of member/staff lookup
- Cache household context
- Batch Supabase operations

---

## Conclusion

**Overall Assessment:** 70% aligned with HomeOps architecture

**Strengths:**
- Core flow is sound
- Audio handling works
- Intent classification functional
- Clarification logic implemented

**Critical Gaps:**
- No message logging (audit trail missing)
- Staff not integrated
- Task completion/listing not implemented

**Recommendation:** Focus on Priority 1 fixes first, then implement missing intents. Current architecture is solid foundation - just needs completion.
