import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Daytona } from "npm:@daytonaio/sdk";

const daytona = new Daytona({
  apiKey: Deno.env.get("DAYTONA_API_KEY") ?? "",
  apiUrl: Deno.env.get("DAYTONA_API_URL"),
});

serve(async (req: Request) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader } } }
  );

  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Invalid session" }), {
      status: 401,
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    });
  }

  try {
    const body = await req.json();
    const action = body.action;
    const sandboxId = body.sandboxId;

    switch (action) {
      case "create_sandbox": {
        const language = body.language ?? "typescript";
        const envVars = body.envVars ?? {};
        const sandbox = await daytona.create({
          language,
          envVars,
        });
        return new Response(
          JSON.stringify({
            success: true,
            sandboxId: sandbox.id,
            status: "running",
          }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "start_sandbox": {
        const sandbox = await daytona.get(sandboxId);
        await sandbox.start();
        return new Response(
          JSON.stringify({ success: true, status: "running" }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "stop_sandbox": {
        const sandbox = await daytona.get(sandboxId);
        await sandbox.stop();
        return new Response(
          JSON.stringify({ success: true, status: "stopped" }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "delete_sandbox": {
        const sandbox = await daytona.get(sandboxId);
        await sandbox.delete();
        return new Response(
          JSON.stringify({ success: true }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "exec_command":
      case "shell": {
        const sandbox = await daytona.get(sandboxId);
        const command = body.command ?? "";
        const cwd = body.cwd;
        const env = body.env;
        const timeout = body.timeout;
        const res = await sandbox.process.executeCommand(command, cwd, env, timeout);
        return new Response(
          JSON.stringify({
            exitCode: res.exitCode,
            stdout: res.result ?? "",
            stderr: "",
          }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "read_file": {
        const sandbox = await daytona.get(sandboxId);
        const path = body.path;
        const buf = await sandbox.fs.downloadFile(path);
        const text = new TextDecoder().decode(buf);
        return new Response(
          JSON.stringify({ content: text }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "write_file": {
        const sandbox = await daytona.get(sandboxId);
        const path = body.path;
        const content = body.content ?? "";
        await sandbox.fs.uploadFile(path, new TextEncoder().encode(content));
        return new Response(
          JSON.stringify({ success: true }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "edit_file": {
        const sandbox = await daytona.get(sandboxId);
        const path = body.path;
        const targetContent = body.targetContent;
        const replacementContent = body.replacementContent;

        const buf = await sandbox.fs.downloadFile(path);
        let text = new TextDecoder().decode(buf);
        if (targetContent && !text.includes(targetContent)) {
          return new Response(
            JSON.stringify({ error: "targetContent not found in file" }),
            { status: 400, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
          );
        }
        if (targetContent) {
          text = text.replace(targetContent, replacementContent ?? "");
        } else if (body.content !== undefined) {
          text = body.content;
        }
        await sandbox.fs.uploadFile(path, new TextEncoder().encode(text));
        return new Response(
          JSON.stringify({ success: true, newContent: text }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "list_dir": {
        const sandbox = await daytona.get(sandboxId);
        const path = body.path ?? "/";
        const files = await sandbox.fs.listFiles(path);
        return new Response(
          JSON.stringify({ files }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "glob":
      case "search_files": {
        const sandbox = await daytona.get(sandboxId);
        const pattern = body.pattern ?? "*";
        const path = body.path ?? "/";
        // Search using findFiles or execute find command
        const res = await sandbox.process.executeCommand(`find "${path}" -name "${pattern}" 2>/dev/null | head -n 100`);
        const files = (res.result ?? "").split("\n").filter((l: string) => l.trim().length > 0);
        return new Response(
          JSON.stringify({ matches: files }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "grep": {
        const sandbox = await daytona.get(sandboxId);
        const query = body.query ?? "";
        const path = body.path ?? ".";
        const res = await sandbox.process.executeCommand(`grep -rn "${query}" "${path}" 2>/dev/null | head -n 100`);
        const matches = (res.result ?? "").split("\n").filter((l: string) => l.trim().length > 0);
        return new Response(
          JSON.stringify({ matches }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      default:
        return new Response(
          JSON.stringify({ error: `Unknown action: ${action}` }),
          { status: 400, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
    }
  } catch (err: any) {
    return new Response(
      JSON.stringify({ error: err?.message || String(err) }),
      { status: 500, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
    );
  }
});
