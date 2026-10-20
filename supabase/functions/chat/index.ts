import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Mistral } from "npm:@mistralai/mistralai";

const BUILD_ID = "2026-10-20-work-contract-1";
const apiKey = Deno.env.get("MISTRAL_API_KEY") ?? "";
const client = new Mistral({ apiKey });

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

function fail(
  message: string,
  status = 400,
  field?: string,
  code?: string,
): Response {
  return json(
    {
      error: message,
      ...(field ? { field } : {}),
      ...(code ? { code } : {}),
    },
    status,
  );
}

/**
 * The model is configuration, never a client decision. Removing the old
 * mistral-medium -> open-mistral-nemo downgrade is deliberate: a silent swap
 * makes every tool-use failure impossible to diagnose.
 */
const MODEL = Deno.env.get("WORK_MODEL")?.trim() || "mistral-medium-latest";
const MODEL_LIMITS: Record<string, number> = {
  "mistral-medium-latest": 32768,
  "mistral-large-latest": 32768,
  "mistral-small-latest": 32768,
  "open-mistral-nemo": 131072,
  "pixtral-large-latest": 32768,
};

function normalizeMaxTokens(value: unknown): number {
  const requested = typeof value === "number" && Number.isFinite(value)
    ? Math.floor(value)
    : 8192;
  const ceiling = MODEL_LIMITS[MODEL] ?? 32768;
  return Math.max(256, Math.min(requested, ceiling));
}

function mistralFailure(err: any): Response {
  const status = Number(err?.status ?? err?.statusCode ?? 0);
  const message = err?.message || String(err);
  if (status === 429) {
    return fail(
      `The configured model (${MODEL}) is rate limited by Mistral. ` +
        `Retry later or set WORK_MODEL to an allowed model. Details: ${message}`,
      429,
    );
  }
  if (status === 403 || status === 401) {
    return fail(
      `The configured model (${MODEL}) is not allowed for this Mistral plan/key. ` +
        `Set WORK_MODEL to an available model. Details: ${message}`,
      403,
    );
  }
  return fail(`Mistral request failed: ${message}`, status >= 400 && status < 600 ? status : 502);
}

function getAdminClient() {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !key) return null;
  return createClient(url, key);
}

async function consumeQuota(userId: string): Promise<boolean> {
  const admin = getAdminClient();
  if (!admin) return true; // local `functions serve` without service role
  const { data, error } = await admin.rpc("consume_work_usage", {
    p_user_id: userId,
    p_kind: "model",
    p_amount: 1,
  });
  if (error) {
    console.error(`[ChatEdge] quota check failed: ${error.message}`);
    throw new Error(`Usage quota unavailable: ${error.message}`);
  }
  return data === true;
}

serve(async (req: Request) => {
  const started = Date.now();
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

  try {
    const body = await req.json();
    if (body === null || typeof body !== "object" || Array.isArray(body)) {
      return fail("Request body must be a JSON object", 400, "body");
    }

    const isWorkRequest = body.mode === "work";
    const isAnonymous = (user as any).is_anonymous === true ||
      (user as any).isAnonymous === true;
    if (isWorkRequest && isAnonymous) {
      return fail(
        "Sign in with a real account to use Work.",
        403,
        undefined,
        "not_signed_in",
      );
    }

    const messages = body.messages ?? body.inputs;
    if (!Array.isArray(messages) || messages.length === 0) {
      return fail("Missing required field: messages", 400, "messages");
    }
    const instructions = body.instructions ?? "";
    if (typeof instructions !== "string") {
      return fail("Field instructions must be a string", 400, "instructions");
    }
    const tools = body.tools ?? [];
    if (!Array.isArray(tools)) {
      return fail("Field tools must be an array", 400, "tools");
    }
    const toolChoice = body.tool_choice ?? body.toolChoice ??
      (tools.length > 0 ? "auto" : undefined);
    const stream = body.stream === true;
    const maxTokens = normalizeMaxTokens(
      body.maxTokens ?? body.completionArgs?.maxTokens,
    );
    const temperature = body.temperature ?? body.completionArgs?.temperature ?? 0.2;

    if (!(await consumeQuota(user.id))) {
      return fail("Daily model call quota exceeded for this account.", 429);
    }

    const toolNames = tools.map((t: any) => t.function?.name ?? t.name);
    console.log(
      `[ChatEdge] start build=${BUILD_ID} user=${user.id} model=${MODEL} ` +
        `tools=${tools.length} toolChoice=${toolChoice} maxTokens=${maxTokens} stream=${stream}`,
    );

    const rawMessages = instructions
      ? [{ role: "system", content: instructions }, ...messages]
      : messages;

    // Strict normalization for the Mistral SDK.
    const formattedMessages = rawMessages.map((m: any, mIdx: number) => {
      if (m.role === "tool") {
        const callId = m.toolCallId ?? m.tool_call_id ?? m.id;
        if (!callId) {
          throw new Error(`Tool result message at index ${mIdx} missing tool_call_id`);
        }
        return {
          role: "tool",
          name: m.name ?? undefined,
          toolCallId: String(callId),
          content: typeof m.content === "string"
            ? m.content
            : JSON.stringify(m.content ?? ""),
        };
      }
      if (m.role === "assistant") {
        const rawCalls = m.toolCalls ?? m.tool_calls;
        if (rawCalls && Array.isArray(rawCalls) && rawCalls.length > 0) {
          const toolCalls = rawCalls.map((c: any, index: number) => {
            const id = c.id?.toString();
            if (!id) {
              throw new Error(`Assistant message tool call at index ${index} missing id`);
            }
            return {
              id,
              type: c.type ?? "function",
              function: {
                name: c.function?.name ?? c.name,
                arguments: typeof c.function?.arguments === "string"
                  ? c.function.arguments
                  : JSON.stringify(c.function?.arguments ?? {}),
              },
              index: c.index ?? index,
            };
          });
          return {
            role: "assistant",
            content: m.content ?? "",
            toolCalls,
            prefix: m.prefix ?? false,
          };
        }
        return {
          role: "assistant",
          content: m.content ?? "",
          prefix: m.prefix ?? false,
        };
      }
      return m;
    });

    const callModel = async (limit: number) =>
      await client.chat.complete({
        model: MODEL,
        messages: formattedMessages,
        tools: tools.length > 0 ? tools : undefined,
        toolChoice: tools.length > 0 ? toolChoice : undefined,
        temperature,
        maxTokens: limit,
        topP: body.topP ?? body.completionArgs?.topP ?? 1,
      });

    if (stream) {
      const chatStream = await client.chat.stream({
        model: MODEL,
        messages: formattedMessages,
        tools: tools.length > 0 ? tools : undefined,
        toolChoice: tools.length > 0 ? toolChoice : undefined,
        temperature,
        maxTokens,
        topP: body.topP ?? body.completionArgs?.topP ?? 1,
      });

      const encoder = new TextEncoder();
      const readable = new ReadableStream({
        async start(controller) {
          try {
            for await (const chunk of chatStream) {
              controller.enqueue(
                encoder.encode(`data: ${JSON.stringify(chunk)}\n\n`),
              );
            }
            controller.enqueue(encoder.encode("data: [DONE]\n\n"));
            controller.close();
          } catch (streamErr) {
            console.error(`[ChatEdge] stream error: ${streamErr}`);
            controller.enqueue(
              encoder.encode(
                `data: ${JSON.stringify({ error: String(streamErr) })}\n\n`,
              ),
            );
            controller.error(streamErr);
          }
        },
      });

      console.log(
        `[ChatEdge] done model=${MODEL} status=stream duration=${Date.now() - started}ms`,
      );
      return new Response(readable, {
        headers: {
          ...CORS_HEADERS,
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache",
          "Connection": "keep-alive",
          "x-build-id": BUILD_ID,
          "x-model-used": MODEL,
        },
      });
    }

    let response = await callModel(maxTokens);
    let choice = (response as any).choices?.[0];
    let finishReason = choice?.finish_reason ?? choice?.finishReason;
    let calls = choice?.message?.toolCalls ?? choice?.message?.tool_calls;

    if (finishReason === "length" && Array.isArray(calls) && calls.length > 0) {
      const retryLimit = Math.min(maxTokens * 2, MODEL_LIMITS[MODEL] ?? 32768);
      if (retryLimit > maxTokens) {
        console.log(
          `[ChatEdge] length-truncated tool call; retrying maxTokens=${retryLimit}`,
        );
        response = await callModel(retryLimit);
        choice = (response as any).choices?.[0];
        finishReason = choice?.finish_reason ?? choice?.finishReason;
        calls = choice?.message?.toolCalls ?? choice?.message?.tool_calls;
      }
      if (finishReason === "length" && Array.isArray(calls) && calls.length > 0) {
        return fail(
          `The model output hit the token limit (${MODEL_LIMITS[MODEL] ?? 32768}) ` +
            `and the tool call was truncated. Split the file or request into smaller steps.`,
          422,
        );
      }
    }

    const message = choice?.message;
    if (message) {
      if (Array.isArray(calls) && calls.length > 0) {
        for (const call of calls) {
          if (!call.id) {
            throw new Error("Upstream model returned tool call without an ID");
          }
        }
        message.toolCalls = calls;
        message.tool_calls = calls;
        console.log(
          `[ChatEdge] tool calls (${calls.length}): ` +
            calls.map((c: any) => c.function?.name ?? c.name).join(", "),
        );
      }
    }

    console.log(
      `[ChatEdge] done model=${MODEL} status=200 duration=${Date.now() - started}ms`,
    );
    return json(response);
  } catch (err: any) {
    console.error(`[ChatEdge] error model=${MODEL}: ${err?.message || String(err)}`);
    if (err?.status || err?.statusCode) return mistralFailure(err);
    return fail(err?.message || String(err), 500);
  }
});
