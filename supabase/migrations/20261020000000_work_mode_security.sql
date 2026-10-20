-- Migration: 20261020000000_work_mode_security.sql
-- Purpose:
--   1. Make work_tool_events ownable and safe (text ids, user_id, strict RLS).
--   2. Persist one WorkTurn per user prompt (thread survives restarts).
--   3. Persist the agent message history per conversation.
--   4. Add per-user daily quotas for model calls and sandbox minutes.
--   5. Stop anonymous access to screenshots.

-- ---------------------------------------------------------------------------
-- 1. work_tool_events
-- ---------------------------------------------------------------------------
ALTER TABLE public.work_tool_events DROP CONSTRAINT IF EXISTS work_tool_events_pkey;
ALTER TABLE public.work_tool_events ALTER COLUMN id DROP DEFAULT;
ALTER TABLE public.work_tool_events ALTER COLUMN id TYPE text USING id::text;
ALTER TABLE public.work_tool_events ADD PRIMARY KEY (id);

ALTER TABLE public.work_tool_events
  ADD COLUMN IF NOT EXISTS user_id uuid;
ALTER TABLE public.work_tool_events
  ADD COLUMN IF NOT EXISTS tool_call_id text;
ALTER TABLE public.work_tool_events
  ADD COLUMN IF NOT EXISTS screenshot_path text;

UPDATE public.work_tool_events e
SET user_id = c.user_id
FROM public.conversations c
WHERE e.user_id IS NULL AND c.id::text = e.conversation_id;

DELETE FROM public.work_tool_events WHERE user_id IS NULL;

ALTER TABLE public.work_tool_events
  ALTER COLUMN user_id SET DEFAULT auth.uid();
ALTER TABLE public.work_tool_events
  ALTER COLUMN user_id SET NOT NULL;

UPDATE public.work_tool_events SET tool_call_id = id WHERE tool_call_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_work_tool_events_user_conversation
  ON public.work_tool_events(user_id, conversation_id, created_at ASC);

DROP POLICY IF EXISTS "Allow public work_tool_events read" ON public.work_tool_events;
DROP POLICY IF EXISTS "Allow public work_tool_events insert" ON public.work_tool_events;
DROP POLICY IF EXISTS "Allow public work_tool_events update" ON public.work_tool_events;
DROP POLICY IF EXISTS "Users read own work_tool_events" ON public.work_tool_events;
DROP POLICY IF EXISTS "Users insert own work_tool_events" ON public.work_tool_events;
DROP POLICY IF EXISTS "Users update own work_tool_events" ON public.work_tool_events;
DROP POLICY IF EXISTS "Users delete own work_tool_events" ON public.work_tool_events;

CREATE POLICY "Users read own work_tool_events" ON public.work_tool_events
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users insert own work_tool_events" ON public.work_tool_events
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users update own work_tool_events" ON public.work_tool_events
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users delete own work_tool_events" ON public.work_tool_events
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- 2. work_turns: one row per user prompt, rendered as a real thread item
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.work_turns (
  id text PRIMARY KEY,
  conversation_id text NOT NULL,
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  prompt text NOT NULL DEFAULT '',
  intro_message text NOT NULL DEFAULT '',
  question text,
  pending_tool_call_id text,
  events jsonb NOT NULL DEFAULT '[]'::jsonb,
  final_answer text,
  error text,
  attachments jsonb NOT NULL DEFAULT '[]'::jsonb,
  duration_seconds integer NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'running',
  started_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_work_turns_user_conversation
  ON public.work_turns(user_id, conversation_id, started_at ASC);

ALTER TABLE public.work_turns
  ADD COLUMN IF NOT EXISTS pending_tool_call_id text;

ALTER TABLE public.work_turns ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own work_turns" ON public.work_turns;
CREATE POLICY "Users manage own work_turns" ON public.work_turns
  FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- 3. Agent message history (memory across user messages)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.work_agent_messages (
  conversation_id text PRIMARY KEY,
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  messages jsonb NOT NULL DEFAULT '[]'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.work_agent_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own work_agent_messages" ON public.work_agent_messages;
CREATE POLICY "Users manage own work_agent_messages" ON public.work_agent_messages
  FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- 4. Daily quotas for model calls and sandbox minutes
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.work_usage (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  usage_day date NOT NULL DEFAULT CURRENT_DATE,
  model_calls integer NOT NULL DEFAULT 0,
  sandbox_minutes integer NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, usage_day)
);

ALTER TABLE public.work_usage ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own work_usage" ON public.work_usage;
CREATE POLICY "Users read own work_usage" ON public.work_usage
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.consume_work_usage(
  p_user_id uuid,
  p_kind text,
  p_amount integer DEFAULT 1
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  model_limit constant integer := 200;
  sandbox_limit constant integer := 120;
  current_model integer;
  current_sandbox integer;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_id THEN
    RAISE EXCEPTION 'cannot consume usage for another user';
  END IF;

  INSERT INTO public.work_usage (user_id, usage_day)
  VALUES (p_user_id, CURRENT_DATE)
  ON CONFLICT (user_id, usage_day) DO NOTHING;

  SELECT model_calls, sandbox_minutes
    INTO current_model, current_sandbox
    FROM public.work_usage
    WHERE user_id = p_user_id AND usage_day = CURRENT_DATE
    FOR UPDATE;

  IF p_kind = 'model' THEN
    IF current_model + p_amount > model_limit THEN
      RETURN false;
    END IF;
    UPDATE public.work_usage
      SET model_calls = model_calls + p_amount
      WHERE user_id = p_user_id AND usage_day = CURRENT_DATE;
    RETURN true;
  ELSIF p_kind = 'sandbox' THEN
    IF current_sandbox + p_amount > sandbox_limit THEN
      RETURN false;
    END IF;
    UPDATE public.work_usage
      SET sandbox_minutes = sandbox_minutes + p_amount
      WHERE user_id = p_user_id AND usage_day = CURRENT_DATE;
    RETURN true;
  END IF;

  RAISE EXCEPTION 'unknown usage kind: %', p_kind;
END;
$$;

REVOKE ALL ON FUNCTION public.consume_work_usage(uuid, text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consume_work_usage(uuid, text, integer)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Screenshot storage: no anonymous access, only the user's own folder
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users manage own screenshots" ON storage.objects;
DROP POLICY IF EXISTS "Users read own screenshots" ON storage.objects;
DROP POLICY IF EXISTS "Users write own screenshots" ON storage.objects;
DROP POLICY IF EXISTS "Users update own screenshots" ON storage.objects;
DROP POLICY IF EXISTS "Users delete own screenshots" ON storage.objects;

CREATE POLICY "Users read own screenshots" ON storage.objects
  FOR SELECT TO authenticated USING (
    bucket_id = 'workspace_screenshots'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );
CREATE POLICY "Users write own screenshots" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (
    bucket_id = 'workspace_screenshots'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );
CREATE POLICY "Users update own screenshots" ON storage.objects
  FOR UPDATE TO authenticated USING (
    bucket_id = 'workspace_screenshots'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );
CREATE POLICY "Users delete own screenshots" ON storage.objects
  FOR DELETE TO authenticated USING (
    bucket_id = 'workspace_screenshots'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );
