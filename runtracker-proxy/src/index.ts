interface Env {
  STRAVA_CLIENT_ID: string;
  STRAVA_CLIENT_SECRET: string;
  ANTHROPIC_API_KEY: string;
  GROQ_API_KEY: string;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

const PREMIUM_USER_IDS = new Set([
  // Add Apple userIdentifiers here after signing in
  // e.g. "001234.abcdef1234567890abcdef1234567890.1234"
]);

function isGroqModel(model: string): boolean {
  return !model.startsWith("claude-");
}

function isPremiumUser(userId: string): boolean {
  return PREMIUM_USER_IDS.has(userId);
}

function translateToGroqRequest(body: Record<string, unknown>): Record<string, unknown> {
  const messages: Array<Record<string, string>> = [];

  // Convert Claude's top-level "system" field to an OpenAI-style system message
  if (body.system) {
    messages.push({ role: "system", content: String(body.system) });
  }

  // Forward the messages array as-is (already role/content format)
  const inputMessages = body.messages as Array<Record<string, string>> | undefined;
  if (inputMessages) {
    for (const msg of inputMessages) {
      messages.push({ role: msg.role, content: msg.content });
    }
  }

  return {
    model: body.model,
    max_tokens: body.max_tokens,
    messages,
  };
}

function translateFromGroqResponse(groqData: Record<string, unknown>): Record<string, unknown> {
  // Convert OpenAI-style response back to Claude format so the iOS app parses it unchanged
  const choices = groqData.choices as Array<Record<string, unknown>> | undefined;
  if (choices && choices.length > 0) {
    const message = choices[0].message as Record<string, string> | undefined;
    const text = message?.content ?? "";
    return {
      content: [{ type: "text", text }],
      model: groqData.model,
      role: "assistant",
    };
  }

  // If the response has an error, pass it through
  return groqData;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/strava/config" && request.method === "GET") {
      return handleStravaConfig(env);
    }

    if (path === "/strava/token" && request.method === "POST") {
      return handleStravaToken(request, env);
    }

    if (path === "/coach/messages" && request.method === "POST") {
      return handleCoachMessages(request, env);
    }

    return jsonResponse({ error: "Not found" }, 404);
  },
};

function handleStravaConfig(env: Env): Response {
  return jsonResponse({ client_id: env.STRAVA_CLIENT_ID });
}

async function handleStravaToken(request: Request, env: Env): Promise<Response> {
  let body: Record<string, string>;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const forwardBody: Record<string, string> = {
    client_id: env.STRAVA_CLIENT_ID,
    client_secret: env.STRAVA_CLIENT_SECRET,
    grant_type: body.grant_type,
  };

  if (body.code) {
    forwardBody.code = body.code;
  }
  if (body.refresh_token) {
    forwardBody.refresh_token = body.refresh_token;
  }

  const stravaResponse = await fetch("https://www.strava.com/oauth/token", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(forwardBody),
  });

  const data = await stravaResponse.json();
  return jsonResponse(data, stravaResponse.status);
}

async function handleCoachMessages(request: Request, env: Env): Promise<Response> {
  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const model = String(body.model ?? "");
  const userId = String(body.user_id ?? "");

  // Gate Claude models to premium users only
  if (!isGroqModel(model) && !isPremiumUser(userId)) {
    return jsonResponse({
      content: [{ type: "text", text: "Premium models require a paid account. Please switch to Llama 3.3 70B (free) in Settings, or contact support to upgrade." }],
      model,
      role: "assistant",
    }, 200);
  }

  // Strip user_id before forwarding to any provider
  delete body.user_id;

  if (isGroqModel(model)) {
    // Route to Groq
    const groqBody = translateToGroqRequest(body);
    const groqResponse = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${env.GROQ_API_KEY}`,
      },
      body: JSON.stringify(groqBody),
    });

    const groqData: Record<string, unknown> = await groqResponse.json();

    if (!groqResponse.ok) {
      return jsonResponse(groqData, groqResponse.status);
    }

    const translated = translateFromGroqResponse(groqData);
    return jsonResponse(translated, 200);
  }

  // Route to Anthropic (Claude)
  const anthropicResponse = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify(body),
  });

  const data = await anthropicResponse.json();
  return jsonResponse(data, anthropicResponse.status);
}
