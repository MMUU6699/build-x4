-- Migration: 20261018000000_add_work_mode_tables.sql
-- Description: Add mode and work plan state to conversations, work_tool_events, work_sessions, and integrations tables

-- 1. Extend conversations table with work mode columns
ALTER TABLE public.conversations 
ADD COLUMN IF NOT EXISTS mode text NOT NULL DEFAULT 'chat',
ADD COLUMN IF NOT EXISTS plan_state jsonb DEFAULT NULL,
ADD COLUMN IF NOT EXISTS attachments jsonb DEFAULT '[]'::jsonb;

-- 2. Create work_sessions table to manage agent execution lifecycle
CREATE TABLE IF NOT EXISTS public.work_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    workspace_id uuid REFERENCES public.workspaces(id) ON DELETE SET NULL,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    phase text NOT NULL DEFAULT 'idle', -- 'idle', 'pending', 'running', 'waiting', 'completed', 'error'
    started_at timestamptz DEFAULT now(),
    ended_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    CONSTRAINT uq_work_sessions_conversation UNIQUE(conversation_id)
);

-- 3. Create work_tool_events table to persist all tool steps for timeline scrubber & computer viewport
CREATE TABLE IF NOT EXISTS public.work_tool_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id text NOT NULL,
    step_id text NOT NULL,
    tool_name text NOT NULL,
    tool_category text NOT NULL DEFAULT 'mcp', -- 'shell', 'file', 'browser', 'search', 'mcp', 'plan', 'message'
    brief text NOT NULL DEFAULT '',
    arguments jsonb DEFAULT '{}'::jsonb,
    result text DEFAULT '',
    original_file_content text,
    modified_file_content text,
    browser_url text,
    screenshot_url text,
    status text NOT NULL DEFAULT 'completed', -- 'calling', 'running', 'completed', 'failed'
    created_at timestamptz DEFAULT now()
);

-- Index for fast timeline queries by conversation
CREATE INDEX IF NOT EXISTS idx_work_tool_events_conversation_id 
ON public.work_tool_events(conversation_id, created_at ASC);

-- 4. Create integrations table to track provider health and connectivity
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    provider text NOT NULL, -- 'daytona', 'supabase'
    status text NOT NULL DEFAULT 'disconnected', -- 'connected', 'disconnected', 'error'
    details text DEFAULT '',
    last_checked_at timestamptz DEFAULT now(),
    created_at timestamptz DEFAULT now(),
    CONSTRAINT uq_user_provider UNIQUE(user_id, provider)
);

-- 5. Row Level Security
ALTER TABLE public.work_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_tool_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;

-- Policies for work_sessions
DROP POLICY IF EXISTS "Users manage own work_sessions" ON public.work_sessions;
CREATE POLICY "Users manage own work_sessions" ON public.work_sessions
FOR ALL USING (auth.uid() = user_id);

-- Policies for work_tool_events
DROP POLICY IF EXISTS "Allow public work_tool_events read" ON public.work_tool_events;
DROP POLICY IF EXISTS "Allow public work_tool_events insert" ON public.work_tool_events;
DROP POLICY IF EXISTS "Allow public work_tool_events update" ON public.work_tool_events;

CREATE POLICY "Allow public work_tool_events read" ON public.work_tool_events 
FOR SELECT USING (true);

CREATE POLICY "Allow public work_tool_events insert" ON public.work_tool_events 
FOR INSERT WITH CHECK (true);

CREATE POLICY "Allow public work_tool_events update" ON public.work_tool_events 
FOR UPDATE USING (true);

-- Policies for integrations
DROP POLICY IF EXISTS "Users manage own integrations" ON public.integrations;
CREATE POLICY "Users manage own integrations" ON public.integrations
FOR ALL USING (auth.uid() = user_id);

-- 6. Storage Bucket for workspace screenshots
INSERT INTO storage.buckets (id, name, public)
VALUES ('workspace_screenshots', 'workspace_screenshots', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Users manage own screenshots" ON storage.objects;
CREATE POLICY "Users manage own screenshots" ON storage.objects
FOR ALL USING (
    bucket_id = 'workspace_screenshots' AND
    (auth.uid()::text = (storage.foldername(name))[1] OR auth.role() = 'anon')
);
