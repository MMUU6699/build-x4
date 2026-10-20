import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Daytona } from "npm:@daytonaio/sdk";

const BUILD_ID = "2026-10-20-work-contract-1";
const BROWSER_SCRIPT_VERSION = "v3-2026-10-20";
const daytona = new Daytona({
  apiKey: Deno.env.get("DAYTONA_API_KEY") ?? "",
  apiUrl: Deno.env.get("DAYTONA_API_URL"),
});

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json",
      "x-build-id": BUILD_ID,
    },
  });
}

function fail(message: string, status = 400, field?: string): Response {
  return json(field ? { error: message, field } : { error: message }, status);
}

function logAction(
  action: string,
  sandboxId: string | null,
  status: string,
  started: number,
  extra = "",
) {
  console.log(
    `[DaytonaEdge] action=${action} sandbox=${sandboxId ?? "-"} status=${status} ` +
      `duration=${Date.now() - started}ms ${extra}`.trim(),
  );
}

function escapeShellArg(arg: string): string {
  return `'${arg.replace(/'/g, "'\\''")}'`;
}

function toBase64(bytes: Uint8Array): string {
  // Chunked: String.fromCharCode(...bytes) overflows the stack for a real PNG.
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    const slice = bytes.subarray(i, i + chunk);
    binary += String.fromCharCode.apply(null, Array.from(slice));
  }
  return btoa(binary);
}

function sanitizeSegment(value: unknown, fallback: string): string {
  const raw = (value ?? "").toString().trim();
  if (!raw) return fallback;
  return raw.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 120) || fallback;
}

async function withTimeout<T>(
  label: string,
  ms: number,
  task: Promise<T>,
): Promise<T> {
  let timer: number | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(
      () => reject(new Error(`${label} timed out after ${Math.round(ms / 1000)}s`)),
      ms,
    );
  });
  try {
    return await Promise.race([task, timeout]);
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}

async function shell(
  sandbox: any,
  command: string,
  timeout = 120,
  cwd?: string,
  env?: Record<string, string>,
) {
  return await sandbox.process.executeCommand(command, cwd, env, timeout);
}

async function readSandboxFile(sandbox: any, path: string): Promise<string> {
  try {
    const bytes = await sandbox.fs.downloadFile(path);
    return new TextDecoder().decode(bytes);
  } catch (_) {
    return "";
  }
}

async function getOwnedWorkspace(
  admin: any,
  userId: string,
  sandboxId: string,
) {
  const { data, error } = await admin
    .from("workspaces")
    .select("id, user_id, daytona_sandbox_id, status")
    .eq("user_id", userId)
    .eq("daytona_sandbox_id", sandboxId)
    .maybeSingle();
  if (error) throw new Error(`Ownership lookup failed: ${error.message}`);
  return data;
}

async function getActiveSandbox(sandboxId: string) {
  const sandbox = await daytona.get(sandboxId);
  const state = (sandbox as any).state;
  if (state === "stopped" || state === "archived") {
    logAction("start_sandbox", sandboxId, "restarting", Date.now());
    await sandbox.start();
    await new Promise((r) => setTimeout(r, 2000));
  }
  return sandbox;
}

function isSandboxMissing(err: any): boolean {
  const status =
    err?.status ?? err?.statusCode ?? err?.response?.status ?? err?.cause?.status;
  const text = `${err?.name ?? ""} ${err?.message ?? err}`.toLowerCase();
  return status === 404 || text.includes("404") || text.includes("not found") ||
    text.includes("does not exist");
}

const BROWSER_SCRIPT = String.raw`
const fs = require('fs');
const puppeteer = require('puppeteer-core');

const CDP = 'http://127.0.0.1:9222';

async function connect() {
  return await puppeteer.connect({
    browserURL: CDP,
    defaultViewport: { width: 1280, height: 800 },
  });
}

function clean(text) {
  return String(text || '').replace(/\s+/g, ' ').trim();
}

async function extractElements(page) {
  return await page.evaluate(() => {
    const selector =
      'button, a[href], input, textarea, select, [role="button"], ' +
      '[role="link"], [role="tab"], [role="checkbox"], [contenteditable="true"]';
    const nodes = Array.from(document.querySelectorAll(selector));
    const items = [];
    let idx = 0;
    for (const el of nodes) {
      const rect = el.getBoundingClientRect();
      const style = window.getComputedStyle(el);
      if (
        rect.width <= 0 ||
        rect.height <= 0 ||
        style.visibility === 'hidden' ||
        style.display === 'none'
      ) {
        continue;
      }
      const tag = el.tagName.toLowerCase();
      const text = (el.innerText || el.value || el.getAttribute('placeholder') ||
        el.getAttribute('aria-label') || '').trim().replace(/\s+/g, ' ').slice(0, 120);
      const type = el.getAttribute('type') || '';
      const href = el.getAttribute('href') || '';
      el.setAttribute('data-buildx-idx', String(idx));
      let line = '[' + idx + '] <' + tag;
      if (type) line += ' type="' + type + '"';
      if (href) line += ' href="' + href.slice(0, 60) + '"';
      line += '>';
      if (text) line += ' "' + text + '"';
      items.push(line);
      idx++;
      if (idx >= 80) break;
    }
    return { items: items, count: items.length };
  });
}

async function visibleText(page) {
  try {
    const text = await page.evaluate(() => {
      const body = document.body ? document.body.innerText : '';
      return String(body || '');
    });
    return text.replace(/\s+/g, ' ').trim().slice(0, 6000);
  } catch (_) {
    return '';
  }
}

async function elementCenter(page, index) {
  return await page.evaluate((targetIdx) => {
    const el = document.querySelector('[data-buildx-idx="' + targetIdx + '"]');
    if (!el) return null;
    el.scrollIntoView({ block: 'center', inline: 'center' });
    const rect = el.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return null;
    return { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
  }, index);
}

(async () => {
  const action = process.argv[2] || 'view';
  const arg1 = process.argv[3] || '';
  const arg2 = process.argv[4] || '';
  const arg3 = process.argv[5] || '';

  const browser = await connect();
  const pages = await browser.pages();
  const page = pages.length > 0 ? pages[0] : await browser.newPage();
  await page.setViewport({ width: 1280, height: 800 });

  const result = {};

  if (action === 'navigate') {
    if (!arg1) throw new Error('browser_navigate requires a url');
    await page.goto(arg1, { waitUntil: 'domcontentloaded', timeout: 20000 });
  } else if (action === 'click') {
    let x = Number(arg2);
    let y = Number(arg3);
    if (!Number.isFinite(x) || !Number.isFinite(y)) {
      const idx = parseInt(arg1, 10);
      if (!Number.isFinite(idx)) {
        throw new Error('browser_click requires an index or coordinates');
      }
      const center = await elementCenter(page, idx);
      if (!center) throw new Error('No interactive element with index ' + idx);
      x = center.x;
      y = center.y;
    }
    await page.mouse.move(x, y);
    await page.mouse.click(x, y);
    await new Promise((r) => setTimeout(r, 1500));
    result.clicked = { x: x, y: y };
  } else if (action === 'input') {
    const idx = parseInt(arg1, 10);
    const text = arg2;
    const pressEnter = arg3 === 'true';
    if (!Number.isFinite(idx)) throw new Error('browser_input requires an index');
    if (!text) throw new Error('browser_input requires text');
    const center = await elementCenter(page, idx);
    if (!center) throw new Error('No interactive element with index ' + idx);
    await page.mouse.click(center.x, center.y);
    await page.keyboard.down('Control');
    await page.keyboard.press('A');
    await page.keyboard.up('Control');
    await page.keyboard.press('Backspace');
    await page.keyboard.type(text, { delay: 10 });
    if (pressEnter) await page.keyboard.press('Enter');
    await new Promise((r) => setTimeout(r, 1000));
    result.typed_index = idx;
  } else if (action === 'press_key') {
    if (!arg1) throw new Error('browser_press_key requires a key');
    await page.keyboard.press(arg1);
    await new Promise((r) => setTimeout(r, 1200));
  } else if (action === 'scroll') {
    const delta = arg1 === 'up' ? -600 : 600;
    await page.mouse.move(640, 400);
    await page.mouse.wheel({ deltaY: delta });
    await new Promise((r) => setTimeout(r, 700));
  } else if (action !== 'view' && action !== 'get_text') {
    throw new Error('Unknown browser action: ' + action);
  }

  const url = page.url();
  const title = await page.title();
  const text = await visibleText(page);
  const elements = await extractElements(page);

  let screenshotPath = null;
  let byteSize = 0;
  if (action !== 'get_text') {
    screenshotPath = '/tmp/buildx_browser_' + Date.now() + '_' +
      Math.random().toString(36).slice(2) + '.png';
    await page.screenshot({ path: screenshotPath });
    const stat = fs.statSync(screenshotPath);
    if (!stat || stat.size <= 0) {
      throw new Error('Screenshot file is empty: ' + screenshotPath);
    }
    byteSize = stat.size;
  }

  console.log('BUILDX_BROWSER_RESULT_START');
  console.log(JSON.stringify({
    url: url,
    title: title,
    page_text: text,
    interactive_elements: elements.items,
    elements_count: elements.count,
    screenshot_path: screenshotPath,
    byte_size: byteSize,
    clicked: result.clicked || null,
    typed_index: result.typed_index || null,
  }));
  console.log('BUILDX_BROWSER_RESULT_END');
  process.exit(0);
})().catch((err) => {
  console.error('BUILDX_BROWSER_ERROR: ' + (err && err.message ? err.message : err));
  process.exit(1);
});
`;

const PUPPETEER_DIR = "/home/daytona/.build_x/node";
const BROWSER_SCRIPT_PATH =
  `/home/daytona/.build_x/browser_service_${BROWSER_SCRIPT_VERSION}.js`;

/**
 * Idempotent bootstrap. A fresh Daytona sandbox has no Chromium, no Xvfb and
 * no puppeteer-core; the previous code assumed a hand-prepared sandbox.
 */
async function ensureComputerReady(sandbox: any, sandboxId: string) {
  const binary = await shell(
    sandbox,
    "command -v chromium || command -v chromium-browser || command -v google-chrome || true",
    30,
  );
  let chromium = (binary.result ?? "").trim().split("\n").filter(Boolean)[0] ?? "";
  if (!chromium) {
    logAction("bootstrap", sandboxId, "installing-chromium", Date.now());
    await shell(
      sandbox,
      "(command -v apt-get >/dev/null 2>&1 && " +
        "(apt-get update -qq && apt-get install -y -qq chromium xvfb curl) || " +
        "(sudo apt-get update -qq && sudo apt-get install -y -qq chromium xvfb curl)) " +
        "|| true",
      420,
    );
    const retry = await shell(
      sandbox,
      "command -v chromium || command -v chromium-browser || command -v google-chrome || true",
      30,
    );
    chromium = (retry.result ?? "").trim().split("\n").filter(Boolean)[0] ?? "";
  }
  if (!chromium) {
    throw new Error(
      "Chromium is not installed in this sandbox and could not be installed. " +
        "Build a Daytona snapshot with chromium, xvfb, node and puppeteer-core.",
    );
  }

  await shell(sandbox, "mkdir -p /home/daytona/.build_x", 30);
  await shell(
    sandbox,
    `rm -f /home/daytona/.build_x/browser_service_*.js && ` +
      `cat > ${escapeShellArg(BROWSER_SCRIPT_PATH)} <<'BUILDX_BROWSER_EOF'\n` +
      BROWSER_SCRIPT +
      "\nBUILDX_BROWSER_EOF",
    60,
  );

  const puppeteerCheck = await shell(
    sandbox,
    `NODE_PATH=${PUPPETEER_DIR}/node_modules node -e "require('puppeteer-core')" ` +
      ">/dev/null 2>&1 && echo OK || echo MISSING",
    30,
  );
  if (!(puppeteerCheck.result ?? "").includes("OK")) {
    logAction("bootstrap", sandboxId, "installing-puppeteer", Date.now());
    await shell(
      sandbox,
      `mkdir -p ${PUPPETEER_DIR} && cd ${PUPPETEER_DIR} && ` +
        "(npm init -y >/dev/null 2>&1 || true) && " +
        "npm install puppeteer-core@23 --no-audit --no-fund",
      420,
    );
  }

  await shell(
    sandbox,
    "pgrep -f 'Xvfb :99' >/dev/null 2>&1 || " +
      "(nohup Xvfb :99 -screen 0 1280x800x24 >/tmp/xvfb.log 2>&1 &) ; sleep 1",
    30,
  );

  const cdp = await shell(
    sandbox,
    "curl -fsS http://127.0.0.1:9222/json/version >/dev/null 2>&1 && echo UP || echo DOWN",
    15,
  );
  if (!(cdp.result ?? "").includes("UP")) {
    await shell(
      sandbox,
      "pkill -f 'chromium.*remote-debugging-port=9222' 2>/dev/null || true; " +
        `DISPLAY=:99 nohup ${escapeShellArg(chromium)} --no-sandbox --disable-gpu ` +
        "--disable-dev-shm-usage --remote-debugging-port=9222 " +
        "--user-data-dir=/home/daytona/.chrome-profile --window-size=1280,800 " +
        "about:blank >/tmp/chrome.log 2>&1 &",
      30,
    );
    for (let i = 0; i < 20; i++) {
      await new Promise((r) => setTimeout(r, 500));
      const check = await shell(
        sandbox,
        "curl -fsS http://127.0.0.1:9222/json/version >/dev/null 2>&1 && echo UP || echo DOWN",
        10,
      );
      if ((check.result ?? "").includes("UP")) break;
      if (i === 19) {
        throw new Error(
          "Chromium did not open its DevTools port 9222. Check /tmp/chrome.log in the sandbox.",
        );
      }
    }
  }

  return { chromium, nodePath: `${PUPPETEER_DIR}/node_modules` };
}

async function uploadScreenshot(
  admin: any,
  userId: string,
  conversationId: string,
  eventId: string,
  bytes: Uint8Array,
) {
  const conversation = sanitizeSegment(conversationId, "unknown-conversation");
  const event = sanitizeSegment(eventId, `browser-${Date.now()}`);
  const path = `${userId}/${conversation}/${event}.png`;
  const { error } = await admin.storage
    .from("workspace_screenshots")
    .upload(path, bytes, { contentType: "image/png", upsert: true });
  if (error) throw new Error(`Screenshot upload failed: ${error.message}`);
  const { data } = await admin.storage
    .from("workspace_screenshots")
    .createSignedUrl(path, 3600);
  return { path, signedUrl: data?.signedUrl ?? "" };
}

async function runSandboxBrowserCommand(
  sandbox: any,
  sandboxId: string,
  action: string,
  args: string[],
  userId: string,
  conversationId: string,
  eventId: string,
) {
  const env = await ensureComputerReady(sandbox, sandboxId);
  const script = escapeShellArg(BROWSER_SCRIPT_PATH);
  const quoted = args.map((a) => escapeShellArg(a)).join(" ");
  const cmd =
    `NODE_PATH=${escapeShellArg(env.nodePath)} DISPLAY=:99 node ${script} ` +
    `${escapeShellArg(action)} ${quoted}`;

  const res = await shell(sandbox, cmd, 120);
  const output = `${res.result ?? ""}\n${res.stderr ?? ""}`;
  if (output.includes("BUILDX_BROWSER_ERROR")) {
    const line = output
      .split("\n")
      .find((l) => l.includes("BUILDX_BROWSER_ERROR")) ?? "Browser action failed";
    throw new Error(line.replace("BUILDX_BROWSER_ERROR:", "").trim());
  }

  const startMarker = "BUILDX_BROWSER_RESULT_START";
  const endMarker = "BUILDX_BROWSER_RESULT_END";
  if (!output.includes(startMarker) || !output.includes(endMarker)) {
    throw new Error(
      `Browser helper produced no result. Output: ${output.slice(-1200)}`,
    );
  }
  const raw = output.substring(
    output.indexOf(startMarker) + startMarker.length,
    output.indexOf(endMarker),
  ).trim();
  const parsed = JSON.parse(raw);

  let screenshotUrl = "";
  let screenshotPath = "";
  let screenshotError: string | null = null;
  let byteSize = Number(parsed.byte_size ?? 0);
  if (parsed.screenshot_path) {
    try {
      const bytes = await sandbox.fs.downloadFile(parsed.screenshot_path);
      if (!bytes || bytes.length === 0) {
        throw new Error("Downloaded screenshot is empty");
      }
      byteSize = bytes.length;
      const admin = createClient(
        Deno.env.get("SUPABASE_URL") ?? "",
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      );
      const uploaded = await uploadScreenshot(
        admin,
        userId,
        conversationId,
        eventId,
        bytes,
      );
      screenshotPath = uploaded.path;
      screenshotUrl = uploaded.signedUrl;
    } catch (e) {
      screenshotError = e instanceof Error ? e.message : String(e);
      // Do not return a stale file. The data URL is this exact capture only.
      try {
        const bytes = await sandbox.fs.downloadFile(parsed.screenshot_path);
        screenshotUrl = `data:image/png;base64,${toBase64(bytes)}`;
      } catch (_) {
        screenshotUrl = "";
      }
    }
  }

  return {
    success: true,
    url: parsed.url ?? "",
    title: parsed.title ?? "",
    page_text: parsed.page_text ?? "",
    interactive_elements: Array.isArray(parsed.interactive_elements)
      ? parsed.interactive_elements
      : [],
    elements_count: Number(parsed.elements_count ?? 0),
    screenshot_url: screenshotUrl,
    screenshot_path: screenshotPath,
    screenshot_error: screenshotError,
    byte_size: byteSize,
    clicked: parsed.clicked ?? null,
    typed_index: parsed.typed_index ?? null,
  };
}

async function execWithStreams(
  sandbox: any,
  command: string,
  cwd?: string,
  env?: Record<string, string>,
  timeout = 60,
) {
  const token = crypto.randomUUID().replace(/-/g, "");
  const out = `/tmp/buildx_${token}.out`;
  const err = `/tmp/buildx_${token}.err`;
  const code = `/tmp/buildx_${token}.code`;
  const wrapped =
    `bash -lc ${escapeShellArg(command)} > ${out} 2> ${err}; echo $? > ${code}`;
  const res = await shell(sandbox, wrapped, timeout, cwd, env);
  const stdout = await readSandboxFile(sandbox, out);
  const stderr = await readSandboxFile(sandbox, err);
  const codeText = await readSandboxFile(sandbox, code);
  const parsedCode = Number.parseInt(codeText.trim(), 10);
  const exitCode = Number.isFinite(parsedCode)
    ? parsedCode
    : Number(res.exitCode ?? 0);
  await shell(sandbox, `rm -f ${out} ${err} ${code}`, 15);
  return {
    stdout,
    stderr,
    exitCode,
    output: `${stdout}${stderr}`,
  };
}

serve(async (req: Request) => {
  const started = Date.now();
  let action = "unknown";
  let sandboxId: string | null = null;

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: { ...CORS_HEADERS, "x-build-id": BUILD_ID } });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return fail("Unauthorized: Missing Authorization header", 401);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: authData, error: authError } = await supabase.auth.getUser();
  const user = authData?.user;
  if (authError || !user) {
    return fail("Unauthorized: Invalid or expired JWT token", 401);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  try {
    const body = await req.json();
    if (body === null || typeof body !== "object" || Array.isArray(body)) {
      return fail("Request body must be a JSON object", 400, "body");
    }
    action = (body.action ?? "").toString();
    if (!action) return fail("Missing required field: action", 400, "action");

    const needsSandbox = action !== "health" && action !== "ensure_sandbox";
    sandboxId = body.sandboxId ? body.sandboxId.toString() : null;

    if (needsSandbox) {
      if (!sandboxId) {
        const { data: ws, error } = await admin
          .from("workspaces")
          .select("daytona_sandbox_id")
          .eq("user_id", user.id)
          .not("daytona_sandbox_id", "is", null)
          .order("last_used_at", { ascending: false })
          .limit(1)
          .maybeSingle();
        if (error) throw new Error(`Sandbox lookup failed: ${error.message}`);
        sandboxId = ws?.daytona_sandbox_id ?? null;
      }
      if (!sandboxId) {
        return fail(
          "No sandbox exists for this user. Call ensure_sandbox first.",
          409,
          "sandboxId",
        );
      }
      const owned = await getOwnedWorkspace(admin, user.id, sandboxId);
      if (!owned) {
        logAction(action, sandboxId, "forbidden", started, `user=${user.id}`);
        return fail("Unauthorized access to this sandbox", 403, "sandboxId");
      }
    }

    const conversationId =
      (body.conversationId ?? "unknown-conversation").toString();
    const eventId = (body.eventId ?? `browser-${Date.now()}`).toString();

    switch (action) {
      case "health": {
        let ok = false;
        let details = "";
        try {
          const sandboxes = await daytona.list();
          ok = true;
          details = `Connected. Sandboxes visible to this key: ${sandboxes?.length ?? 0}`;
        } catch (err: any) {
          details = err?.message || String(err);
        }
        await admin.from("integrations").upsert({
          user_id: user.id,
          provider: "daytona",
          status: ok ? "connected" : "error",
          details,
          last_checked_at: new Date().toISOString(),
        }, { onConflict: "user_id,provider" });
        logAction(action, null, ok ? "ok" : "error", started, details);
        return json({
          status: ok ? "connected" : "error",
          provider: "daytona",
          details,
          timestamp: new Date().toISOString(),
        });
      }

      case "ensure_sandbox": {
        const { data: existing, error: findError } = await admin
          .from("workspaces")
          .select("id, daytona_sandbox_id")
          .eq("user_id", user.id)
          .not("daytona_sandbox_id", "is", null)
          .order("last_used_at", { ascending: false })
          .limit(1)
          .maybeSingle();
        if (findError) throw new Error(`Workspace lookup failed: ${findError.message}`);

        if (existing?.daytona_sandbox_id) {
          try {
            const sandbox = await getActiveSandbox(existing.daytona_sandbox_id);
            await admin.from("workspaces").update({
              status: "ready",
              last_used_at: new Date().toISOString(),
            }).eq("id", existing.id).eq("user_id", user.id);
            logAction(action, existing.daytona_sandbox_id, "reused", started);
            return json({
              success: true,
              sandboxId: sandbox.id ?? existing.daytona_sandbox_id,
              status: "running",
              created: false,
            });
          } catch (err) {
            if (!isSandboxMissing(err)) throw err;
            // The stored sandbox no longer exists (Daytona deleted it). Clear
            // the stale id and create a fresh sandbox for this user.
            await admin.from("workspaces").update({
              daytona_sandbox_id: null,
              status: "missing",
            }).eq("id", existing.id).eq("user_id", user.id);
            logAction(action, existing.daytona_sandbox_id, "stale", started);
          }
        }

        // Charge quota only when a new sandbox is created. Reusing an existing
        // sandbox must not burn a 30-minute block on every prompt.
        const { data: allowed, error: quotaError } = await admin.rpc(
          "consume_work_usage",
          { p_user_id: user.id, p_kind: "sandbox", p_amount: 30 },
        );
        if (quotaError) {
          throw new Error(`Sandbox quota unavailable: ${quotaError.message}`);
        }
        if (allowed !== true) {
          return fail("Daily sandbox minute quota exceeded for this account.", 429);
        }

        const workspaceId = crypto.randomUUID();
        const language = (body.language ?? "typescript").toString();
        const { error: insertError } = await admin.from("workspaces").insert({
          id: workspaceId,
          user_id: user.id,
          name: "Build X Work",
          status: "creating",
          language,
          last_used_at: new Date().toISOString(),
        });
        if (insertError) {
          throw new Error(`Workspace creation failed: ${insertError.message}`);
        }

        try {
          const createArgs: Record<string, unknown> = {
            language,
            autoStopInterval: 30,
          };
          const snapshot = body.snapshot ?? Deno.env.get("DAYTONA_SNAPSHOT");
          if (snapshot) createArgs.snapshot = snapshot;
          if (body.envVars && typeof body.envVars === "object") {
            createArgs.envVars = body.envVars;
          }
          const sandbox = await withTimeout(
            "create_sandbox",
            240_000,
            daytona.create(createArgs),
          );
          await admin.from("workspaces").update({
            daytona_sandbox_id: sandbox.id,
            status: "ready",
            last_used_at: new Date().toISOString(),
          }).eq("id", workspaceId).eq("user_id", user.id);
          logAction(action, sandbox.id, "created", started);
          return json({
            success: true,
            sandboxId: sandbox.id,
            status: "running",
            created: true,
          });
        } catch (err) {
          await admin.from("workspaces").update({ status: "error" })
            .eq("id", workspaceId).eq("user_id", user.id);
          throw err;
        }
      }

      case "start_sandbox": {
        const sandbox = await daytona.get(sandboxId);
        await sandbox.start();
        logAction(action, sandboxId, "ok", started);
        return json({ success: true, status: "running" });
      }

      case "stop_sandbox": {
        const sandbox = await daytona.get(sandboxId);
        await sandbox.stop();
        logAction(action, sandboxId, "ok", started);
        return json({ success: true, status: "stopped" });
      }

      case "delete_sandbox": {
        const sandbox = await daytona.get(sandboxId);
        await sandbox.delete();
        await admin.from("workspaces").update({
          daytona_sandbox_id: null,
          status: "stopped",
        }).eq("daytona_sandbox_id", sandboxId).eq("user_id", user.id);
        logAction(action, sandboxId, "ok", started);
        return json({ success: true });
      }

      case "exec_command": {
        const command = body.command;
        if (typeof command !== "string" || !command.trim()) {
          return fail("Missing required field: command", 400, "command");
        }
        const timeout = Math.max(1, Math.min(Number(body.timeout ?? 60), 300));
        const sandbox = await getActiveSandbox(sandboxId!);
        const result = await execWithStreams(
          sandbox,
          command,
          body.cwd,
          body.env,
          timeout,
        );
        logAction(action, sandboxId, `exit=${result.exitCode}`, started);
        return json(result);
      }

      case "read_file": {
        const path = body.path;
        if (typeof path !== "string" || !path) {
          return fail("Missing required field: path", 400, "path");
        }
        const sandbox = await getActiveSandbox(sandboxId!);
        const bytes = await sandbox.fs.downloadFile(path);
        let text = new TextDecoder().decode(bytes);
        const offset = Number(body.offset ?? 0);
        const limit = Number(body.limit ?? 0);
        if (offset > 0 || limit > 0) {
          const lines = text.split("\n");
          const start = offset > 0 ? Math.max(0, offset - 1) : 0;
          const end = limit > 0 ? start + limit : lines.length;
          text = lines.slice(start, end).join("\n");
        }
        logAction(action, sandboxId, "ok", started, `bytes=${bytes.length}`);
        return json({ content: text, byteSize: bytes.length });
      }

      case "write_file": {
        const path = body.path;
        if (typeof path !== "string" || !path) {
          return fail("Missing required field: path", 400, "path");
        }
        if (typeof body.content !== "string") {
          return fail("Missing required field: content", 400, "content");
        }
        const sandbox = await getActiveSandbox(sandboxId!);
        let originalContent = "";
        try {
          const old = await sandbox.fs.downloadFile(path);
          originalContent = new TextDecoder().decode(old);
        } catch (_) {
          originalContent = "";
        }
        const finalContent = body.append === true
          ? originalContent + body.content
          : body.content;
        const bytes = new TextEncoder().encode(finalContent);
        await sandbox.fs.uploadFile(path, bytes);
        logAction(action, sandboxId, "ok", started, `bytes=${bytes.length}`);
        return json({
          success: true,
          originalContent,
          modifiedContent: finalContent,
          byteSize: bytes.length,
        });
      }

      case "edit_file": {
        const path = body.path;
        if (typeof path !== "string" || !path) {
          return fail("Missing required field: path", 400, "path");
        }
        if (typeof body.old_str !== "string" || body.old_str.length === 0) {
          return fail("Missing required field: old_str", 400, "old_str");
        }
        if (typeof body.new_str !== "string") {
          return fail("Missing required field: new_str", 400, "new_str");
        }
        const sandbox = await getActiveSandbox(sandboxId!);
        const originalContent = new TextDecoder().decode(
          await sandbox.fs.downloadFile(path),
        );
        const occurrences = originalContent.split(body.old_str).length - 1;
        if (occurrences === 0) {
          return fail(`old_str was not found in ${path}`, 409, "old_str");
        }
        if (occurrences > 1) {
          return fail(
            `old_str occurs ${occurrences} times in ${path}; it must be unique`,
            409,
            "old_str",
          );
        }
        const modifiedContent = originalContent.replace(body.old_str, body.new_str);
        const bytes = new TextEncoder().encode(modifiedContent);
        await sandbox.fs.uploadFile(path, bytes);
        logAction(action, sandboxId, "ok", started, `bytes=${bytes.length}`);
        return json({
          success: true,
          originalContent,
          modifiedContent,
          byteSize: bytes.length,
        });
      }

      case "list_dir": {
        const path = (body.path ?? "/").toString();
        const sandbox = await getActiveSandbox(sandboxId!);
        const files = await sandbox.fs.listFiles(path);
        logAction(action, sandboxId, "ok", started, `count=${files?.length ?? 0}`);
        return json({ files });
      }

      case "glob": {
        const pattern = (body.pattern ?? "").toString();
        if (!pattern) return fail("Missing required field: pattern", 400, "pattern");
        const base = (body.path ?? ".").toString();
        const sandbox = await getActiveSandbox(sandboxId!);
        const res = await shell(
          sandbox,
          `find ${escapeShellArg(base)} -name ${escapeShellArg(pattern)} 2>/dev/null | head -n 200`,
          45,
        );
        const matches = (res.result ?? "").split("\n").filter((l: string) => l.trim());
        logAction(action, sandboxId, "ok", started, `count=${matches.length}`);
        return json({ matches });
      }

      case "grep": {
        const query = (body.query ?? "").toString();
        if (!query) return fail("Missing required field: query", 400, "query");
        const base = (body.path ?? ".").toString();
        const sandbox = await getActiveSandbox(sandboxId!);
        const res = await shell(
          sandbox,
          `grep -rn ${escapeShellArg(query)} ${escapeShellArg(base)} 2>/dev/null | head -n 200`,
          45,
        );
        const matches = (res.result ?? "").split("\n").filter((l: string) => l.trim());
        logAction(action, sandboxId, "ok", started, `count=${matches.length}`);
        return json({ matches });
      }

      case "search_web": {
        const query = (body.query ?? "").toString().trim();
        if (!query) return fail("Missing required field: query", 400, "query");
        const limit = Math.max(1, Math.min(Number(body.limit ?? 5), 20));
        const searchResp = await fetch(
          `https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}`,
          {
            headers: {
              "User-Agent":
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            },
          },
        );
        if (!searchResp.ok) {
          return fail(
            `Web search failed with status ${searchResp.status}`,
            502,
          );
        }
        const html = await searchResp.text();
        const results: Array<{
          title: string;
          url: string;
          snippet: string;
          favicon: string;
        }> = [];
        const regex =
          /<a class="result__url" href="([^"]+)">[\s\S]*?<a class="result__snippet[^>]*>([\s\S]*?)<\/a>/g;
        let match: RegExpExecArray | null;
        while ((match = regex.exec(html)) !== null && results.length < limit) {
          const rawUrl = match[1];
          let cleanUrl = rawUrl;
          if (rawUrl.includes("uddg=")) {
            const u = new URL("https://duckduckgo.com" + rawUrl).searchParams.get("uddg");
            if (u) cleanUrl = decodeURIComponent(u);
          }
          let host = cleanUrl;
          try {
            host = new URL(cleanUrl).hostname;
          } catch (_) { /* keep raw */ }
          results.push({
            title: host,
            url: cleanUrl,
            snippet: match[2].replace(/<[^>]+>/g, "").trim(),
            favicon:
              `https://s2.googleusercontent.com/s2/favicons?domain=${encodeURIComponent(host)}&sz=32`,
          });
        }
        logAction(action, sandboxId, "ok", started, `count=${results.length}`);
        return json({ results });
      }

      case "browser_navigate": {
        const url = (body.url ?? "").toString().trim();
        if (!url) return fail("Missing required field: url", 400, "url");
        const sandbox = await getActiveSandbox(sandboxId!);
        const result = await withTimeout(
          "browser_navigate",
          180_000,
          runSandboxBrowserCommand(
            sandbox, sandboxId!, "navigate", [url], user.id, conversationId, eventId,
          ),
        );
        logAction(action, sandboxId, "ok", started, `bytes=${result.byte_size}`);
        return json(result);
      }

      case "browser_view": {
        const sandbox = await getActiveSandbox(sandboxId!);
        const result = await withTimeout(
          "browser_view",
          180_000,
          runSandboxBrowserCommand(
            sandbox, sandboxId!, "view", [], user.id, conversationId, eventId,
          ),
        );
        logAction(action, sandboxId, "ok", started, `bytes=${result.byte_size}`);
        return json(result);
      }

      case "browser_get_text": {
        const sandbox = await getActiveSandbox(sandboxId!);
        const result = await withTimeout(
          "browser_get_text",
          120_000,
          runSandboxBrowserCommand(
            sandbox, sandboxId!, "get_text", [], user.id, conversationId, eventId,
          ),
        );
        logAction(action, sandboxId, "ok", started);
        return json(result);
      }

      case "browser_click": {
        const index = body.index;
        const x = body.coordinate_x;
        const y = body.coordinate_y;
        const hasIndex = index !== undefined && index !== null && `${index}` !== "";
        const hasCoords = x !== undefined && x !== null && y !== undefined && y !== null;
        if (!hasIndex && !hasCoords) {
          return fail(
            "browser_click requires index or coordinate_x + coordinate_y",
            400,
            "index",
          );
        }
        const args = hasCoords
          ? ["", `${x}`, `${y}`]
          : [`${index}`, "", ""];
        const sandbox = await getActiveSandbox(sandboxId!);
        const result = await withTimeout(
          "browser_click",
          180_000,
          runSandboxBrowserCommand(
            sandbox, sandboxId!, "click", args, user.id, conversationId, eventId,
          ),
        );
        logAction(action, sandboxId, "ok", started);
        return json(result);
      }

      case "browser_input": {
        const text = body.text;
        if (typeof text !== "string" || !text) {
          return fail("Missing required field: text", 400, "text");
        }
        const index = body.index;
        if (index === undefined || index === null || `${index}` === "") {
          return fail("Missing required field: index", 400, "index");
        }
        const sandbox = await getActiveSandbox(sandboxId!);
        const result = await withTimeout(
          "browser_input",
          180_000,
          runSandboxBrowserCommand(
            sandbox,
            sandboxId!,
            "input",
            [`${index}`, text, body.press_enter === true ? "true" : "false"],
            user.id,
            conversationId,
            eventId,
          ),
        );
        logAction(action, sandboxId, "ok", started);
        return json(result);
      }

      case "browser_scroll": {
        const direction = (body.direction ?? "down").toString();
        if (direction !== "up" && direction !== "down") {
          return fail("direction must be 'up' or 'down'", 400, "direction");
        }
        const sandbox = await getActiveSandbox(sandboxId!);
        const result = await withTimeout(
          "browser_scroll",
          120_000,
          runSandboxBrowserCommand(
            sandbox, sandboxId!, "scroll", [direction], user.id, conversationId, eventId,
          ),
        );
        logAction(action, sandboxId, "ok", started);
        return json(result);
      }

      case "browser_press_key": {
        const key = (body.key ?? "").toString();
        if (!key) return fail("Missing required field: key", 400, "key");
        const sandbox = await getActiveSandbox(sandboxId!);
        const result = await withTimeout(
          "browser_press_key",
          120_000,
          runSandboxBrowserCommand(
            sandbox, sandboxId!, "press_key", [key], user.id, conversationId, eventId,
          ),
        );
        logAction(action, sandboxId, "ok", started);
        return json(result);
      }

      case "browser_restart": {
        const url = body.url ? body.url.toString().trim() : "";
        const sandbox = await getActiveSandbox(sandboxId!);
        await shell(
          sandbox,
          "pkill -f 'chromium.*remote-debugging-port=9222' 2>/dev/null || true",
          30,
        );
        await new Promise((r) => setTimeout(r, 1500));
        // ensureComputerReady (inside runSandboxBrowserCommand) relaunches the
        // real browser because the DevTools port is now down.
        const result = await withTimeout(
          "browser_restart",
          180_000,
          runSandboxBrowserCommand(
            sandbox,
            sandboxId!,
            url ? "navigate" : "view",
            url ? [url] : [],
            user.id,
            conversationId,
            eventId,
          ),
        );
        logAction(action, sandboxId, "ok", started, url ? `url=${url}` : "blank");
        return json(result);
      }

      default:
        return fail(`Unknown action: ${action}`, 400, "action");
    }
  } catch (err: any) {
    const message = err?.message || String(err);
    logAction(action, sandboxId, "error", started, message);
    return fail(message, 500);
  }
});
