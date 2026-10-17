import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Mistral } from "npm:@mistralai/mistralai";

const client = new Mistral({
  apiKey:
    Deno.env.get("MISTRAL_API_KEY") ??
    "mstrl_UwnnXZlz5CuwhsrKZaGOYrEUvANHBOdD_1KtT01",
});

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
    const messages = body.inputs ?? body.messages ?? [{ role: "user", content: "hi" }];
    const instructions = body.instructions ?? "";
    const tools = body.tools ?? [];
    const completionArgs = {
      temperature: body.completionArgs?.temperature ?? body.temperature ?? 0.7,
      maxTokens: body.completionArgs?.maxTokens ?? body.maxTokens ?? 2048,
      topP: body.completionArgs?.topP ?? body.topP ?? 1,
    };

    const response = await client.beta.conversations.start({
      inputs: messages,
      model: "mistral-medium-latest",
      instructions: instructions,
      completionArgs,
      tools,
    });

    return new Response(JSON.stringify(response), {
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err?.message || String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    });
  }
});
