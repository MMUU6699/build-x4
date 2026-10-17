-- 1. جدول الملفات الشخصية وإعدادات المستخدم
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'User',
  avatar_url text,
  theme_mode text not null default 'system',
  theme_palette text not null default 'default',
  locale text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 2. جدول المساعدين (Assistants)
create table public.assistants (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  avatar text,
  system_prompt text not null default '',
  temperature double precision not null default 0.7,
  max_tokens integer not null default 2048,
  top_p double precision not null default 1.0,
  default_workspace_id uuid,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 3. جدول مساحات عمل Daytona (Workspaces)
create table public.workspaces (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  daytona_sandbox_id text,
  status text not null default 'stopped', -- 'running' | 'stopped' | 'creating' | 'error'
  language text not null default 'typescript', -- 'typescript' | 'python' | 'go'
  env_vars jsonb not null default '{}'::jsonb,
  last_used_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- 4. جدول المحادثات (Conversations)
create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  assistant_id uuid references public.assistants(id) on delete set null,
  workspace_id uuid references public.workspaces(id) on delete set null,
  mistral_conversation_id text,
  title text not null default 'New Chat',
  is_pinned boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 5. جدول الرسائل وأجزائها (Messages & Parts)
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('user', 'assistant', 'system', 'tool')),
  content text not null default '',
  parts jsonb not null default '[]'::jsonb,
  prompt_tokens integer,
  completion_tokens integer,
  total_tokens integer,
  duration_ms integer,
  message_order integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.assistants enable row level security;
alter table public.workspaces enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;

create policy "Users manage own profile" on public.profiles for all using (auth.uid() = id);
create policy "Users manage own assistants" on public.assistants for all using (auth.uid() = user_id);
create policy "Users manage own workspaces" on public.workspaces for all using (auth.uid() = user_id);
create policy "Users manage own conversations" on public.conversations for all using (auth.uid() = user_id);
create policy "Users manage own messages" on public.messages for all using (auth.uid() = user_id);
