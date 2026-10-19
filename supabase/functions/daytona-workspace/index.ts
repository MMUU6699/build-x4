import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Daytona } from "npm:@daytonaio/sdk";

const daytona = new Daytona({
  apiKey: Deno.env.get("DAYTONA_API_KEY") ?? "",
  apiUrl: Deno.env.get("DAYTONA_API_URL"),
});

function escapeShellArg(arg: string): string {
  return `'${arg.replace(/'/g, "'\\''")}'`;
}

async function getActiveSandbox(sandboxId: string) {
  const sandbox = await daytona.get(sandboxId);
  const state = (sandbox as any).state;
  if (state === "stopped" || state === "archived") {
    console.log(`[DaytonaEdge] Sandbox ${sandboxId} is in '${state}' state. Auto-restarting sandbox before action...`);
    await sandbox.start();
    await new Promise((r) => setTimeout(r, 2000));
  }
  return sandbox;
}

const BROWSER_SERVICE_SCRIPT = `
const fs = require('fs');
const puppeteer = require('/usr/local/share/nvm/versions/node/v25.9.0/lib/node_modules/puppeteer-core');

async function getBrowser() {
  try {
    return await puppeteer.connect({ browserURL: 'http://127.0.0.1:9222', defaultViewport: { width: 1280, height: 800 } });
  } catch (e) {
    const { execSync } = require('child_process');
    execSync("export DISPLAY=:0; nohup chromium --no-sandbox --disable-gpu --disable-quic --disable-dev-shm-usage --remote-debugging-port=9222 --user-data-dir=/home/daytona/.chrome-profile --window-size=1280,800 about:blank >/tmp/chrome.log 2>&1 & sleep 2");
    return await puppeteer.connect({ browserURL: 'http://127.0.0.1:9222', defaultViewport: { width: 1280, height: 800 } });
  }
}

async function getPage(browser) {
  const pages = await browser.pages();
  return pages.length > 0 ? pages[0] : await browser.newPage();
}

async function extractElements(page) {
  return await page.evaluate(() => {
    const selector = 'button, a[href], input, textarea, select, [role="button"], [role="link"], [role="tab"], [role="checkbox"], [contenteditable="true"]';
    const nodes = Array.from(document.querySelectorAll(selector));
    const items = [];
    let idx = 0;
    for (const el of nodes) {
      const rect = el.getBoundingClientRect();
      const style = window.getComputedStyle(el);
      if (rect.width <= 0 || rect.height <= 0 || style.visibility === 'hidden' || style.display === 'none') continue;
      
      const tag = el.tagName.toLowerCase();
      const text = (el.innerText || el.value || el.getAttribute('placeholder') || el.getAttribute('aria-label') || '').trim().replace(/\\s+/g, ' ').substring(0, 80);
      const type = el.getAttribute('type') || '';
      const href = el.getAttribute('href') || '';
      
      el.setAttribute('data-buildx-idx', String(idx));
      items.push({
        index: idx,
        tag,
        type: type ? \` type="\${type}"\` : '',
        href: href ? \` href="\${href.substring(0, 40)}"\` : '',
        text: text ? \` "\${text}"\` : '',
      });
      idx++;
      if (idx >= 60) break;
    }
    const tree = items.map(i => \`[\${i.index}] <\${i.tag}\${i.type}\${i.href}>\${i.text}\`).join('\\n');
    return { count: items.length, tree };
  });
}

const action = process.argv[2] || 'view';
const argVal = process.argv[3] || '';

(async () => {
  const browser = await getBrowser();
  const page = await getPage(browser);
  await page.setViewport({ width: 1280, height: 800 });

  let result = {};

  if (action === 'navigate') {
    const targetUrl = argVal || 'https://www.google.com';
    try {
      await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 15000 });
    } catch (e) {
      result.navError = e.message;
    }
  } else if (action === 'click') {
    const idx = parseInt(argVal, 10);
    const clicked = await page.evaluate((targetIdx) => {
      const el = document.querySelector(\`[data-buildx-idx="\${targetIdx}"]\`);
      if (el) {
        el.scrollIntoView({ behavior: 'instant', block: 'center' });
        el.click();
        return true;
      }
      return false;
    }, idx);
    result.clicked = clicked;
    await new Promise(r => setTimeout(r, 1500));
  } else if (action === 'input') {
    const idx = parseInt(argVal, 10);
    const textToType = process.argv[4] || '';
    const pressEnter = process.argv[5] === 'true';
    const typed = await page.evaluate((targetIdx, text) => {
      const el = document.querySelector(\`[data-buildx-idx="\${targetIdx}"]\`);
      if (el) {
        el.scrollIntoView({ behavior: 'instant', block: 'center' });
        el.focus();
        if ('value' in el) el.value = '';
        return true;
      }
      return false;
    }, idx, textToType);
    if (typed) {
      await page.keyboard.type(textToType);
      if (pressEnter) {
        await page.keyboard.press('Enter');
      }
    }
    result.typed = typed;
    await new Promise(r => setTimeout(r, 800));
  } else if (action === 'press_key') {
    await page.keyboard.press(argVal || 'Enter');
    await new Promise(r => setTimeout(r, 1200));
  } else if (action === 'scroll') {
    const dir = argVal === 'up' ? -500 : 500;
    await page.evaluate((y) => window.scrollBy(0, y), dir);
    await new Promise(r => setTimeout(r, 500));
  } else if (action === 'restart') {
    const { execSync } = require('child_process');
    try {
      execSync("pkill -f chromium || true");
    } catch (_) {}
    execSync("export DISPLAY=:0; nohup chromium --no-sandbox --disable-gpu --disable-quic --disable-dev-shm-usage --remote-debugging-port=9222 --user-data-dir=/home/daytona/.chrome-profile --window-size=1280,800 about:blank >/tmp/chrome.log 2>&1 & sleep 2");
    if (argVal) {
      const newPage = await getPage(await getBrowser());
      try {
        await newPage.goto(argVal, { waitUntil: 'domcontentloaded', timeout: 15000 });
      } catch (_) {}
    }
  }

  const currentUrl = page.url();
  const title = await page.title();
  const screenshotPath = '/tmp/browser_screenshot.png';
  try {
    await page.screenshot({ path: screenshotPath });
  } catch (_) {}

  const elementsData = await extractElements(page);

  result = {
    ...result,
    url: currentUrl,
    title,
    interactive_elements: elementsData.tree,
    elements_count: elementsData.count,
    screenshot_path: screenshotPath,
  };

  console.log('BUILDX_BROWSER_RESULT_START');
  console.log(JSON.stringify(result));
  console.log('BUILDX_BROWSER_RESULT_END');
  process.exit(0);
})();
`;

async function runSandboxBrowserCommand(
  sandbox: any,
  subAction: string,
  arg1?: string,
  arg2?: string,
  arg3?: string,
) {
  const nodePath = "/usr/local/share/nvm/versions/node/v25.9.0/lib/node_modules";
  
  // Ensure browser script exists
  try {
    const checkScript = await sandbox.process.executeCommand("[ -f /home/daytona/.build_x/browser_service.js ] && echo 'EXISTS' || echo 'MISSING'");
    if (!checkScript.result?.includes("EXISTS")) {
      await sandbox.process.executeCommand("mkdir -p /home/daytona/.build_x");
      await sandbox.fs.uploadFile("/home/daytona/.build_x/browser_service.js", new TextEncoder().encode(BROWSER_SERVICE_SCRIPT));
    }
  } catch (_) {}

  const cmd = `NODE_PATH=${nodePath} node /home/daytona/.build_x/browser_service.js ${escapeShellArg(subAction)} ${arg1 ? escapeShellArg(arg1) : "''"} ${arg2 ? escapeShellArg(arg2) : "''"} ${arg3 ? escapeShellArg(arg3) : "''"}`;
  
  const res = await sandbox.process.executeCommand(cmd, undefined, undefined, 45);
  const output = res.result ?? "";
  
  let resultJson: any = null;
  const startMarker = "BUILDX_BROWSER_RESULT_START";
  const endMarker = "BUILDX_BROWSER_RESULT_END";
  if (output.includes(startMarker) && output.includes(endMarker)) {
    const jsonStr = output.substring(
      output.indexOf(startMarker) + startMarker.length,
      output.indexOf(endMarker),
    ).trim();
    try {
      resultJson = JSON.parse(jsonStr);
    } catch (_) {}
  }

  // Download real screenshot PNG and upload to Supabase Storage
  let screenshotUrl = "";
  let byteSize = 0;
  try {
    const imgBytes = await sandbox.fs.downloadFile("/tmp/browser_screenshot.png");
    if (imgBytes && imgBytes.length > 0) {
      byteSize = imgBytes.length;
      const filename = `${Date.now()}_browser.png`;
      const supabaseAdmin = createClient(
        Deno.env.get("SUPABASE_URL") ?? "",
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      );
      const { data: uploadData, error: uploadErr } = await supabaseAdmin.storage
        .from("workspace_screenshots")
        .upload(filename, imgBytes, { contentType: "image/png", upsert: true });

      if (!uploadErr && uploadData) {
        const { data: signedData } = await supabaseAdmin.storage
          .from("workspace_screenshots")
          .createSignedUrl(filename, 3600);
        screenshotUrl = signedData?.signedUrl ?? "";
      }

      if (!screenshotUrl) {
        const b64 = btoa(String.fromCharCode(...new Uint8Array(imgBytes)));
        screenshotUrl = `data:image/png;base64,${b64}`;
      }
    }
  } catch (e) {
    console.error(`[runSandboxBrowserCommand] Screenshot upload error:`, e);
  }

  return {
    url: resultJson?.url ?? arg1 ?? "",
    title: resultJson?.title ?? "",
    interactive_elements: resultJson?.interactive_elements ?? "",
    elements_count: resultJson?.elements_count ?? 0,
    screenshot_url: screenshotUrl,
    file_path: "/tmp/browser_screenshot.png",
    byte_size: byteSize,
    raw_output: output,
  };
}

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

  // Strict JWT session verification
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ error: "Unauthorized: Missing Authorization header" }), {
      status: 401,
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader } } }
  );

  const { data: authData, error: authError } = await supabase.auth.getUser();
  const user = authData?.user;
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized: Invalid or expired JWT token" }), {
      status: 401,
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    });
  }

  try {
    const body = await req.json();
    const action = body.action;
    let sandboxId = body.sandboxId;

    // Auto-resolve sandboxId from database or Daytona if not explicitly provided
    if (!sandboxId && action !== "create_sandbox" && action !== "health") {
      try {
        const supabaseAdmin = createClient(
          Deno.env.get("SUPABASE_URL") ?? "",
          Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "",
        );
        const { data: ws } = await supabaseAdmin
          .from("workspaces")
          .select("daytona_sandbox_id")
          .eq("user_id", user.id)
          .not("daytona_sandbox_id", "is", null)
          .order("last_used_at", { ascending: false })
          .limit(1)
          .maybeSingle();

        if (ws?.daytona_sandbox_id) {
          sandboxId = ws.daytona_sandbox_id;
        }
      } catch (_) {}

      if (!sandboxId) {
        try {
          const list = await daytona.list();
          if (list && list.length > 0) {
            const active = list.find((s: any) => s.state === "started" || s.state === "running") ||
                           list.find((s: any) => s.state === "stopped") ||
                           list[0];
            if (active) {
              sandboxId = active.id;
            }
          }
        } catch (_) {}
      }
    }

    // Sandbox ownership check
    if (sandboxId && action !== "create_sandbox" && action !== "health") {
      try {
        const supabaseAdmin = createClient(
          Deno.env.get("SUPABASE_URL") ?? "",
          Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "",
        );
        const { data: ws } = await supabaseAdmin
          .from("workspaces")
          .select("id, user_id, daytona_sandbox_id")
          .eq("daytona_sandbox_id", sandboxId)
          .maybeSingle();

        if (ws && ws.user_id !== user.id) {
          return new Response(
            JSON.stringify({ error: "Unauthorized access to this sandbox" }),
            { status: 403, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
          );
        }
      } catch (_) {}
    }

    switch (action) {
      case "health": {
        let daytonaOk = false;
        let details = "";
        try {
          const sandboxes = await daytona.list();
          daytonaOk = true;
          details = `Connected. Active sandboxes: ${sandboxes?.length ?? 0}`;
        } catch (err: any) {
          details = err?.message || String(err);
        }

        if (user) {
          try {
            const supabaseAdmin = createClient(
              Deno.env.get("SUPABASE_URL") ?? "",
              Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "",
            );
            await supabaseAdmin.from("integrations").upsert({
              user_id: user.id,
              provider: "daytona",
              status: daytonaOk ? "connected" : "error",
              details: details,
              last_checked_at: new Date().toISOString(),
            }, { onConflict: "user_id,provider" });
          } catch (_) {}
        }

        return new Response(
          JSON.stringify({
            status: daytonaOk ? "connected" : "error",
            provider: "daytona",
            details,
            timestamp: new Date().toISOString(),
          }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "create_sandbox": {
        const language = body.language ?? "typescript";
        const envVars = body.envVars ?? {};
        const snapshot = body.snapshot ?? "daytona-medium";
        const sandbox = await daytona.create({
          language,
          envVars,
          snapshot,
          autoStopInterval: 30,
        });

        if (user && body.workspaceId) {
          try {
            const supabaseAdmin = createClient(
              Deno.env.get("SUPABASE_URL") ?? "",
              Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "",
            );
            await supabaseAdmin.from("workspaces").update({
              daytona_sandbox_id: sandbox.id,
              status: "ready",
            }).eq("id", body.workspaceId).eq("user_id", user.id);
          } catch (_) {}
        }

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
        const sandbox = await getActiveSandbox(sandboxId);
        const command = body.command ?? "";
        const cwd = body.cwd;
        const env = body.env;
        const timeout = body.timeout ?? 60;
        const res = await sandbox.process.executeCommand(command, cwd, env, timeout);
        const exitCode = res.exitCode ?? 0;
        const output = res.result ?? "";

        return new Response(
          JSON.stringify({
            exitCode,
            stdout: exitCode === 0 ? output : "",
            stderr: exitCode !== 0 ? output : "",
            output,
          }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "read_file": {
        const sandbox = await getActiveSandbox(sandboxId);
        const path = body.path ?? body.file_path;
        if (!path) {
          return new Response(JSON.stringify({ error: "Missing required parameter: path or file_path" }), { status: 400, headers: { "Content-Type": "application/json" } });
        }
        const buf = await sandbox.fs.downloadFile(path);
        const text = new TextDecoder().decode(buf);
        return new Response(
          JSON.stringify({ content: text }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "write_file": {
        const sandbox = await getActiveSandbox(sandboxId);
        const path = body.path ?? body.file_path;
        if (!path) {
          return new Response(JSON.stringify({ error: "Missing required parameter: path or file_path" }), { status: 400, headers: { "Content-Type": "application/json" } });
        }
        const content = body.content ?? "";
        const append = body.append === true;

        let originalContent = "";
        try {
          const oldBuf = await sandbox.fs.downloadFile(path);
          originalContent = new TextDecoder().decode(oldBuf);
        } catch (_) {
          originalContent = "";
        }

        const finalContent = append ? originalContent + content : content;
        await sandbox.fs.uploadFile(path, new TextEncoder().encode(finalContent));

        return new Response(
          JSON.stringify({
            success: true,
            originalContent: originalContent,
            modifiedContent: finalContent,
          }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "edit_file":
      case "str_replace": {
        const sandbox = await getActiveSandbox(sandboxId);
        const path = body.path ?? body.file_path;
        if (!path) {
          return new Response(JSON.stringify({ error: "Missing required parameter: path or file_path" }), { status: 400, headers: { "Content-Type": "application/json" } });
        }
        const oldStr = body.old_str ?? body.targetContent;
        const newStr = body.new_str ?? body.replacementContent ?? "";

        const buf = await sandbox.fs.downloadFile(path);
        const originalContent = new TextDecoder().decode(buf);

        if (oldStr && !originalContent.includes(oldStr)) {
          return new Response(
            JSON.stringify({ error: `String '${oldStr}' not found in ${path}` }),
            { status: 400, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
          );
        }

        const modifiedContent = oldStr ? originalContent.replace(oldStr, newStr) : (body.content ?? originalContent);
        await sandbox.fs.uploadFile(path, new TextEncoder().encode(modifiedContent));

        return new Response(
          JSON.stringify({
            success: true,
            originalContent: originalContent,
            modifiedContent: modifiedContent,
          }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "list_dir": {
        const sandbox = await getActiveSandbox(sandboxId);
        const path = body.path ?? body.file_path ?? body.dir_path ?? "/";
        const files = await sandbox.fs.listFiles(path);
        return new Response(
          JSON.stringify({ files }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "glob":
      case "search_files": {
        const sandbox = await getActiveSandbox(sandboxId);
        const pattern = escapeShellArg(body.pattern ?? "*");
        const path = escapeShellArg(body.path ?? body.file_path ?? body.dir_path ?? "/");
        const res = await sandbox.process.executeCommand(`find ${path} -name ${pattern} 2>/dev/null | head -n 100`);
        const files = (res.result ?? "").split("\n").filter((l: string) => l.trim().length > 0);
        return new Response(
          JSON.stringify({ matches: files }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "grep": {
        const sandbox = await getActiveSandbox(sandboxId);
        const query = escapeShellArg(body.query ?? body.regex ?? "");
        const path = escapeShellArg(body.path ?? body.file_path ?? body.dir_path ?? ".");
        const res = await sandbox.process.executeCommand(`grep -rn ${query} ${path} 2>/dev/null | head -n 100`);
        const matches = (res.result ?? "").split("\n").filter((l: string) => l.trim().length > 0);
        return new Response(
          JSON.stringify({ matches }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "search_web": {
        const query = (body.query ?? "").trim();
        const limit = body.limit ?? 5;
        const searchUrl = `https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}`;
        const searchResp = await fetch(searchUrl, {
          headers: {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
          },
        });
        if (!searchResp.ok) {
          throw new Error(`Web search failed with status ${searchResp.status}: ${searchResp.statusText}`);
        }
        const html = await searchResp.text();
        
        const results: Array<{ title: string; url: string; snippet: string; favicon: string }> = [];
        const regex = /<a class="result__url" href="([^"]+)">[\s\S]*?<a class="result__snippet[^>]*>([\s\S]*?)<\/a>/g;
        let match;
        while ((match = regex.exec(html)) !== null && results.length < limit) {
          const rawUrl = match[1];
          let cleanUrl = rawUrl;
          if (rawUrl.includes("uddg=")) {
            const u = new URL("https://duckduckgo.com" + rawUrl).searchParams.get("uddg");
            if (u) cleanUrl = decodeURIComponent(u);
          }
          const snippet = match[2].replace(/<[^>]+>/g, "").trim();
          let host = cleanUrl;
          try {
            host = new URL(cleanUrl).hostname;
          } catch (_) {}
          results.push({
            title: host,
            url: cleanUrl,
            snippet: snippet,
            favicon: `https://s2.googleusercontent.com/s2/favicons?domain=${encodeURIComponent(host)}&sz=32`,
          });
        }

        return new Response(
          JSON.stringify({ results }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      // =========================================================================
      // REAL SANDBOX BROWSER ACTIONS (Chrome DevTools Protocol via Puppeteer)
      // =========================================================================
      case "browser_navigate": {
        const targetUrl = body.url;
        if (!targetUrl) {
          throw new Error("Missing url parameter for browser_navigate");
        }
        if (!sandboxId) {
          throw new Error("No active sandbox available for browser_navigate");
        }
        const sandbox = await getActiveSandbox(sandboxId);
        const browserRes = await runSandboxBrowserCommand(sandbox, "navigate", targetUrl);

        return new Response(
          JSON.stringify({
            success: true,
            url: browserRes.url || targetUrl,
            title: browserRes.title,
            interactive_elements: browserRes.interactive_elements,
            elements_count: browserRes.elements_count,
            screenshot_url: browserRes.screenshot_url,
            file_path: browserRes.file_path,
            byte_size: browserRes.byte_size,
          }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "browser_view":
      case "browser_screenshot": {
        if (!sandboxId) {
          throw new Error("No active sandbox available for browser action");
        }
        const sandbox = await getActiveSandbox(sandboxId);
        const browserRes = await runSandboxBrowserCommand(sandbox, "view");

        return new Response(
          JSON.stringify({
            success: true,
            url: browserRes.url,
            title: browserRes.title,
            interactive_elements: browserRes.interactive_elements,
            elements_count: browserRes.elements_count,
            screenshot_url: browserRes.screenshot_url,
            file_path: browserRes.file_path,
            byte_size: browserRes.byte_size,
          }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "browser_click": {
        if (!sandboxId) {
          throw new Error("No active sandbox available for browser_click");
        }
        const indexStr = String(body.index ?? body.coordinate_x ?? "0");
        const sandbox = await getActiveSandbox(sandboxId);
        const browserRes = await runSandboxBrowserCommand(sandbox, "click", indexStr);

        return new Response(
          JSON.stringify({
            success: true,
            clicked_index: indexStr,
            url: browserRes.url,
            title: browserRes.title,
            interactive_elements: browserRes.interactive_elements,
            elements_count: browserRes.elements_count,
            screenshot_url: browserRes.screenshot_url,
            file_path: browserRes.file_path,
            byte_size: browserRes.byte_size,
          }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "browser_input": {
        if (!sandboxId) {
          throw new Error("No active sandbox available for browser_input");
        }
        const indexStr = String(body.index ?? "0");
        const text = body.text ?? "";
        const pressEnter = body.press_enter === true ? "true" : "false";
        const sandbox = await getActiveSandbox(sandboxId);
        const browserRes = await runSandboxBrowserCommand(sandbox, "input", indexStr, text, pressEnter);

        return new Response(
          JSON.stringify({
            success: true,
            typed_index: indexStr,
            url: browserRes.url,
            title: browserRes.title,
            interactive_elements: browserRes.interactive_elements,
            elements_count: browserRes.elements_count,
            screenshot_url: browserRes.screenshot_url,
            file_path: browserRes.file_path,
            byte_size: browserRes.byte_size,
          }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "browser_scroll": {
        if (!sandboxId) {
          throw new Error("No active sandbox available for browser_scroll");
        }
        const direction = body.direction ?? "down";
        const sandbox = await getActiveSandbox(sandboxId);
        const browserRes = await runSandboxBrowserCommand(sandbox, "scroll", direction);

        return new Response(
          JSON.stringify({
            success: true,
            direction,
            url: browserRes.url,
            title: browserRes.title,
            interactive_elements: browserRes.interactive_elements,
            elements_count: browserRes.elements_count,
            screenshot_url: browserRes.screenshot_url,
            file_path: browserRes.file_path,
            byte_size: browserRes.byte_size,
          }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "browser_press_key": {
        if (!sandboxId) {
          throw new Error("No active sandbox available for browser_press_key");
        }
        const key = body.key ?? "Enter";
        const sandbox = await getActiveSandbox(sandboxId);
        const browserRes = await runSandboxBrowserCommand(sandbox, "press_key", key);

        return new Response(
          JSON.stringify({
            success: true,
            key,
            url: browserRes.url,
            title: browserRes.title,
            interactive_elements: browserRes.interactive_elements,
            elements_count: browserRes.elements_count,
            screenshot_url: browserRes.screenshot_url,
            file_path: browserRes.file_path,
            byte_size: browserRes.byte_size,
          }),
          { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
        );
      }

      case "browser_restart": {
        if (!sandboxId) {
          throw new Error("No active sandbox available for browser_restart");
        }
        const targetUrl = body.url ?? "https://www.google.com";
        const sandbox = await getActiveSandbox(sandboxId);
        const browserRes = await runSandboxBrowserCommand(sandbox, "restart", targetUrl);

        return new Response(
          JSON.stringify({
            success: true,
            url: browserRes.url || targetUrl,
            title: browserRes.title,
            interactive_elements: browserRes.interactive_elements,
            elements_count: browserRes.elements_count,
            screenshot_url: browserRes.screenshot_url,
            file_path: browserRes.file_path,
            byte_size: browserRes.byte_size,
          }),
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
