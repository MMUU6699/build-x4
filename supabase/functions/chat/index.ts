import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Mistral } from "npm:@mistralai/mistralai";

const apiKey = Deno.env.get("MISTRAL_API_KEY") ?? "";
const client = new Mistral({ apiKey });

serve(async (req: Request) => {
  // CORS preflight support
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  // Strict JWT session verification (authenticates both registered users and anonymous guest sign-ins)
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
    const messages = body.inputs ?? body.messages ?? [{ role: "user", content: "hi" }];
    const instructions = body.instructions ?? "";
    const tools = body.tools ?? [];
    const toolChoice = body.tool_choice ?? body.toolChoice ?? (tools.length > 0 ? "auto" : undefined);
    const stream = body.stream === true;
    let model = body.model ?? "open-mistral-nemo";
    if (model === "mistral-medium-latest" || model === "mistral-large-latest") {
      model = "open-mistral-nemo";
    }
    const completionArgs = {
      temperature: body.completionArgs?.temperature ?? body.temperature ?? 0.2,
      maxTokens: body.completionArgs?.maxTokens ?? body.maxTokens ?? 2048,
      topP: body.completionArgs?.topP ?? body.topP ?? 1,
    };

    const toolNames = tools.map((t: any) => t.function?.name ?? t.name);
    console.log(`[ChatEdge] Request: model=${model}, tools_count=${tools.length}, toolChoice=${toolChoice}`);
    if (toolNames.length > 0) {
      console.log(`[ChatEdge] Request tool names: ${toolNames.join(", ")}`);
    }

    const rawMessages = instructions
      ? [{ role: "system", content: instructions }, ...messages]
      : messages;

    // Strict normalization for Mistral SDK (@mistralai/mistralai) compatibility
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
          content: typeof m.content === "string" ? m.content : JSON.stringify(m.content ?? ""),
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
              id: id,
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
            toolCalls: toolCalls,
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

    if (stream) {
      const chatStream = await client.chat.stream({
        model,
        messages: formattedMessages,
        tools: tools.length > 0 ? tools : undefined,
        toolChoice: tools.length > 0 ? toolChoice : undefined,
        temperature: completionArgs.temperature,
        maxTokens: completionArgs.maxTokens,
        topP: completionArgs.topP,
      });

      const encoder = new TextEncoder();
      const readable = new ReadableStream({
        async start(controller) {
          try {
            for await (const chunk of chatStream) {
              const payload = `data: ${JSON.stringify(chunk)}\n\n`;
              controller.enqueue(encoder.encode(payload));
            }
            controller.enqueue(encoder.encode("data: [DONE]\n\n"));
            controller.close();
          } catch (streamErr) {
            controller.error(streamErr);
          }
        },
      });

      return new Response(readable, {
        headers: {
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache",
          "Connection": "keep-alive",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }

    // Non-streaming completion
    const response = await client.chat.complete({
      model,
      messages: formattedMessages,
      tools: tools.length > 0 ? tools : undefined,
      toolChoice: tools.length > 0 ? toolChoice : undefined,
      temperature: completionArgs.temperature,
      maxTokens: completionArgs.maxTokens,
      topP: completionArgs.topP,
    });

    const choice = (response as any).choices?.[0];
    const message = choice?.message;
    if (message) {
      const calls = message.toolCalls ?? message.tool_calls;
      if (calls && Array.isArray(calls) && calls.length > 0) {
        for (const call of calls) {
          if (!call.id) {
            throw new Error("Upstream model returned tool call without an ID");
          }
        }
        message.toolCalls = calls;
        message.tool_calls = calls;
        const calledNames = calls.map((c: any) => c.function?.name ?? c.name);
        console.log(`[ChatEdge] Response tool calls (${calls.length}): ${calledNames.join(", ")}`);
      } else {
        console.log(`[ChatEdge] Response plain text: ${message.content?.substring(0, 100)}`);
      }
    }

    return new Response(JSON.stringify(response), {
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    });
  } catch (err: any) {
    console.error(`[ChatEdge] Error: ${err?.message || String(err)}`);
    return new Response(JSON.stringify({ error: err?.message || String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    });
  }
});
