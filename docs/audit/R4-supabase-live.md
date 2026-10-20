# R4 — Supabase Live Audit

- Date: 2026-10-20
- Project: `owgpuolvfqfjhezuohyf` (`build-x`)
- Method: read-only `SELECT` queries through the Management API using the already-open dashboard session; dashboard UI for Edge Functions and logs. No settings, tables, policies, functions, or secrets were changed.
- Secret policy: secret **names** only; no values were read into notes or printed.

## 1. Conclusion first — root cause of `permission denied for table workspaces`

The live ACLs show a **table-privilege** failure, not an RLS filter failure:

| Table | anon SELECT/INSERT/UPDATE/DELETE | authenticated SELECT/INSERT/UPDATE/DELETE | service_role SELECT/INSERT/UPDATE/DELETE |
|---|---|---|---|
| `workspaces` | no / no / no / no | no / no / no / no | **no / no / no / no** |
| `conversations` | no / no / no / no | no / no / no / no | **no / no / no / no** |
| `messages` | no / no / no / no | no / no / no / no | **no / no / no / no** |
| `work_turns` | no / no / no / no | no / no / no / no | **no / no / no / no** |
| `work_agent_messages` | no / no / no / no | no / no / no / no | **no / no / no / no** |
| `work_usage` | no / no / no / no | no / no / no / no | **no / no / no / no** |
| `integrations` | yes / yes / yes / yes | yes / yes / yes / yes | yes / yes / yes / yes |
| `work_tool_events` | yes / yes / yes / yes | yes / yes / yes / yes | yes / yes / yes / yes |

Raw ACL for the failing tables:

```text
{postgres=arwdDxtm/postgres,anon=Dxtm/postgres,authenticated=Dxtm/postgres,service_role=Dxtm/postgres}
```

`Dxtm` = TRUNCATE, REFERENCES, TRIGGER, MAINTAIN. It contains **no DML** (`a` INSERT, `r` SELECT, `w` UPDATE, `d` DELETE). Therefore:

- the edge function's service-role client cannot `SELECT` from `workspaces`; and
- the app's authenticated client cannot read/write conversations, messages, or Work rows directly.

This exactly matches the reported error and explains why it is a Postgres privilege error rather than an empty RLS result. The repo has no table `GRANT` statements (only one function `GRANT EXECUTE`), so the tables inherited the project's default ACL for `postgres` in `public`:

```text
postgres -> {postgres=arwdDxtm/postgres,anon=Dxtm/postgres,authenticated=Dxtm/postgres,service_role=Dxtm/postgres}
```

`integrations` and `work_tool_events` already have full DML; the other tables were created without it. A new explicit-grant migration is required. RLS must stay ON.

## 2. RLS state

All eight audited tables have `relrowsecurity = true`, owner `postgres`:

`conversations`, `integrations`, `messages`, `work_agent_messages`, `work_tool_events`, `work_turns`, `work_usage`, `workspaces`.

## 3. Policies (live)

Public:

| Table | Policy | Roles | Cmd | USING | WITH CHECK |
|---|---|---|---|---|---|
| assistants | Users manage own assistants | public | ALL | `auth.uid() = user_id` | — |
| conversations | Users manage own conversations | public | ALL | `auth.uid() = user_id` | — |
| integrations | Users manage own integrations | public | ALL | `auth.uid() = user_id` | — |
| messages | Users manage own messages | public | ALL | `auth.uid() = user_id` | — |
| profiles | Users manage own profile | public | ALL | `auth.uid() = id` | — |
| work_agent_messages | Users manage own work_agent_messages | authenticated | ALL | `auth.uid() = user_id` | `auth.uid() = user_id` |
| work_sessions | Users manage own work_sessions | public | ALL | `auth.uid() = user_id` | — |
| work_tool_events | Users delete own work_tool_events | authenticated | DELETE | `auth.uid() = user_id` | — |
| work_tool_events | Users insert own work_tool_events | authenticated | INSERT | — | `auth.uid() = user_id` |
| work_tool_events | Users read own work_tool_events | authenticated | SELECT | `auth.uid() = user_id` | — |
| work_tool_events | Users update own work_tool_events | authenticated | UPDATE | `auth.uid() = user_id` | `auth.uid() = user_id` |
| work_turns | Users manage own work_turns | authenticated | ALL | `auth.uid() = user_id` | `auth.uid() = user_id` |
| work_usage | Users read own work_usage | authenticated | SELECT | `auth.uid() = user_id` | — |
| workspaces | Users manage own workspaces | public | ALL | `auth.uid() = user_id` | — |

Storage:

| Bucket | Policy | Roles | Cmd | USING / CHECK |
|---|---|---|---|---|
| workspace_screenshots | Users delete own screenshots | authenticated | DELETE | bucket + `auth.uid()::text = (storage.foldername(name))[1]` |
| workspace_screenshots | Users read own screenshots | authenticated | SELECT | same |
| workspace_screenshots | Users update own screenshots | authenticated | UPDATE | same |
| workspace_screenshots | Users write own screenshots | authenticated | INSERT | same |

No `USING (true)` policy exists. No storage policy targets `anon`/`public`. Some public-table policies still list role `public`; their qual requires `auth.uid() = user_id`, so anon is denied in practice, but tightening them to `authenticated` is recommended.

## 4. Edge Functions

| Slug | Status | Version | verify_jwt | Updated |
|---|---|---|---|---|
| `chat` | ACTIVE | 6 | true | 2026-10-20 10:50:44 UTC |
| `daytona-workspace` | ACTIVE | 7 | true | 2026-10-20 10:51:54 UTC |

## 5. Secrets (names only)

`MISTRAL_API_KEY`, `DAYTONA_API_KEY`, `DAYTONA_API_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_PUBLISHABLE_KEYS`, `SUPABASE_SECRET_KEYS`, `SUPABASE_DB_URL`, `SUPABASE_JWKS`, `WORK_MODEL`.

`SUPABASE_SERVICE_ROLE_KEY` exists and was updated 2026-10-20 10:51:54 UTC. The grants above explain the failure even with a correct service-role key. No secret value was read or printed.

## 6. Auth settings

| Setting | Live value |
|---|---|
| Email provider | enabled |
| Signups | enabled (`disable_signup = false`) |
| Anonymous sign-ins | enabled |
| Confirm email | **required** (`mailer_autoconfirm = false`) |
| SMTP | **not configured** — Supabase built-in SMTP |
| Email rate limit | **2 per hour** (`rate_limit_email_sent = 2`) |
| Unverified email sign-in | not allowed |

Consequence: confirmation emails can be sent, but built-in SMTP is heavily limited and is not a production deliverability guarantee. Confirmation must be handled explicitly in the app. No security setting was weakened.

## 7. Storage

- Bucket `workspace_screenshots`: `public = false`, no size/MIME limit configured.
- Objects: 3 in `workspace_screenshots`.
- Policies: four authenticated per-user policies (see above).

## 8. Users

No real email user exists. All visible `auth.users` rows have `email = null` and `provider = null` — they are anonymous guest sessions created by the app/tests. A confirmed test user must be created for the smoke test.

## 9. Function logs (last hour)

- `chat` → **No data** in the last hour.
- `daytona-workspace` → **No data** in the last hour.

The reported phone error predates the current log window. The grant evidence above is the authoritative diagnosis; no log line is required to reproduce it.

## 10. Hypotheses

- **H1 (confirmed):** tables created by `postgres` inherited a public default ACL with only `Dxtm` for `anon`/`authenticated`/`service_role`, so DML is denied.
- **H2 (not supported):** a wrong/empty `SUPABASE_SERVICE_ROLE_KEY`. The secret exists and was freshly set; the missing ACL alone explains the error. The key's role claim was not decoded (would require reading the secret value, which is out of policy).
