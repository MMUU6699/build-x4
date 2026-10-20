-- Round 6: explicit table privileges.
--
-- Root cause of `permission denied for table workspaces`: the tables were
-- created by `postgres` and inherited a default ACL that only contained
-- Dxtm (TRUNCATE, REFERENCES, TRIGGER, MAINTAIN) for anon/authenticated/
-- service_role. RLS was ON, but no role had SELECT/INSERT/UPDATE/DELETE.
--
-- Keep RLS enabled. Grant only what each role needs:
--   service_role : all DML for the edge functions
--   authenticated: DML for the signed-in app, always filtered by RLS
--   anon         : DML only on Chat tables (own rows via auth.uid() RLS);
--                  no Work tables, no profiles.

begin;

grant usage on schema public to anon, authenticated, service_role;

-- Chat works for guests: conversations/messages/assistants are still
-- protected by the per-user RLS policies (auth.uid() = user_id).
grant select, insert, update, delete on table
  public.conversations,
  public.messages,
  public.assistants
to anon;

-- Signed-in app: Chat + Work + profile.
grant select, insert, update, delete on table
  public.profiles,
  public.assistants,
  public.conversations,
  public.messages,
  public.workspaces,
  public.work_sessions,
  public.work_turns,
  public.work_agent_messages,
  public.integrations,
  public.work_tool_events
to authenticated;

grant select on table public.work_usage to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- Edge functions use the service role; it must be able to read and write
-- every app table. RLS is bypassed for service_role by design.
grant all privileges on table
  public.profiles,
  public.assistants,
  public.conversations,
  public.messages,
  public.workspaces,
  public.work_sessions,
  public.work_turns,
  public.work_agent_messages,
  public.integrations,
  public.work_tool_events,
  public.work_usage
to service_role;

grant usage, select on all sequences in schema public to service_role;

-- Guests must never touch Work-owned data or profiles directly.
revoke all on table
  public.profiles,
  public.workspaces,
  public.work_sessions,
  public.work_turns,
  public.work_agent_messages,
  public.work_usage,
  public.integrations,
  public.work_tool_events
from anon;

-- Future tables created by postgres should not repeat the missing-grant bug.
alter default privileges for role postgres in schema public
  grant select, insert, update, delete on tables to authenticated, service_role;

alter default privileges for role postgres in schema public
  grant all privileges on tables to service_role;

commit;
