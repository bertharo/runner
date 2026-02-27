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

function isPremiumUser(_userId: string): boolean {
  // Allow all users access to Claude models for now
  return true;
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

    if (path === "/privacy" && request.method === "GET") {
      return handlePrivacyPolicy();
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

function handlePrivacyPolicy(): Response {
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>tränare — Privacy Policy</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; max-width: 720px; margin: 0 auto; padding: 24px 16px; color: #222; line-height: 1.6; }
  h1 { font-size: 1.5em; }
  h2 { font-size: 1.15em; margin-top: 1.8em; }
  a { color: #0066cc; }
  .updated { color: #666; font-size: 0.9em; }
</style>
</head>
<body>
<h1>Privacy Policy — tränare</h1>
<p class="updated">Last updated: February 26, 2026</p>

<p>tränare ("the App") is developed by bertharo. This policy describes how we collect, use, and protect your information.</p>

<h2>Information We Collect</h2>

<p><strong>1. Apple Account Information</strong><br>
When you sign in with Apple, we receive your Apple user identifier and, optionally, your name and email address. Apple may provide a private relay email address instead of your real email. This information is stored locally on your device in the iOS Keychain.</p>

<p><strong>2. Running Data</strong><br>
If you connect your Strava account, we import your running activities including distance, pace, duration, heart rate, elevation, and workout type. You may also log runs manually. All running data is stored locally on your device using Apple's SwiftData framework.</p>

<p><strong>3. Goal and Preference Data</strong><br>
Training goals (race name, target time, weekly mileage) and app preferences (units, AI model selection, week start day) are stored locally on your device.</p>

<h2>How We Use Your Information</h2>

<ul>
<li>Your Apple user identifier is sent to our proxy server solely to determine your account tier (free or premium). It is stripped from requests before forwarding to any third-party AI provider.</li>
<li>When you use the AI Coach feature, your training data and questions are sent to our proxy server, which forwards them to AI providers (Anthropic or Groq) to generate coaching responses. We do not store your training data or coaching conversations on our servers.</li>
<li>Strava OAuth tokens are exchanged through our proxy server to protect API credentials. We do not store your Strava tokens on our servers.</li>
</ul>

<h2>Third-Party Services</h2>

<p>The App uses the following third-party services:</p>
<ul>
<li><strong>Strava API</strong> — to sync your running activities (<a href="https://www.strava.com/legal/privacy">privacy policy</a>)</li>
<li><strong>Anthropic API</strong> — to provide AI coaching via Claude models (<a href="https://www.anthropic.com/privacy">privacy policy</a>)</li>
<li><strong>Groq API</strong> — to provide AI coaching via Llama models (<a href="https://groq.com/privacy-policy">privacy policy</a>)</li>
<li><strong>Cloudflare Workers</strong> — to host our proxy server (<a href="https://www.cloudflare.com/privacypolicy">privacy policy</a>)</li>
</ul>

<h2>Data Storage and Security</h2>

<p>All personal data (Apple credentials, running history, goals, coaching history) is stored locally on your device. Our proxy server does not persist any user data — it only forwards requests in real time.</p>

<h2>Your Choices</h2>

<ul>
<li>You can sign out at any time in Settings, which removes your Apple credentials from the device Keychain.</li>
<li>You can disconnect Strava at any time in Settings.</li>
<li>You can delete the app to remove all locally stored data.</li>
</ul>

<h2>Data Retention</h2>

<p>We do not retain any personal data on our servers. All data is stored on your device and is removed when you sign out or delete the app.</p>

<h2>Children's Privacy</h2>

<p>The App is not directed at children under 13. We do not knowingly collect information from children under 13.</p>

<h2>Changes to This Policy</h2>

<p>We may update this policy from time to time. Changes will be reflected in the "Last updated" date above.</p>

<h2>Contact</h2>

<p>If you have questions about this privacy policy, contact us at <a href="mailto:bertharo23@gmail.com">bertharo23@gmail.com</a>.</p>
</body>
</html>`;

  return new Response(html, {
    status: 200,
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
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
