interface Env {
  STRAVA_CLIENT_ID: string;
  STRAVA_CLIENT_SECRET: string;
  ANTHROPIC_API_KEY: string;
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
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

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
