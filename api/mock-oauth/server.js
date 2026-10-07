const crypto = require("node:crypto");
const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");

const port = Number(process.env.MOCK_OAUTH_PORT || 5001);
const issuer = process.env.MOCK_OAUTH_ISSUER || `http://localhost:${port}/issuer1`;
const oauthConfig = JSON.parse(fs.readFileSync(path.join(__dirname, "config.json"), "utf8"));
const configuredEmail = oauthConfig.tokenCallbacks
  ?.flatMap((callback) => callback.requestMappings || [])
  .find((mapping) => mapping.claims?.email)?.claims.email;
const { privateKey, publicKey } = crypto.generateKeyPairSync("rsa", { modulusLength: 2048 });
const keyId = "local-mock-oauth";
const publicJwk = {
  ...publicKey.export({ format: "jwk" }),
  alg: "RS256",
  kid: keyId,
  use: "sig",
};
const authorizationCodes = new Map();

function respondJson(response, status, body) {
  response.writeHead(status, { "Content-Type": "application/json" });
  response.end(JSON.stringify(body));
}

function signIdToken(claims) {
  const header = Buffer.from(JSON.stringify({ alg: "RS256", kid: keyId, typ: "JWT" })).toString(
    "base64url",
  );
  const payload = Buffer.from(JSON.stringify(claims)).toString("base64url");
  const data = `${header}.${payload}`;
  const signature = crypto.sign("RSA-SHA256", Buffer.from(data), privateKey).toString("base64url");
  return `${data}.${signature}`;
}

function redirectAfterAuthorization(response, params, username) {
  const code = crypto.randomUUID();
  authorizationCodes.set(code, {
    clientId: params.get("client_id"),
    nonce: params.get("nonce"),
    redirectUri: params.get("redirect_uri"),
    username,
  });

  const callback = new URL(params.get("redirect_uri"));
  callback.searchParams.set("code", code);
  callback.searchParams.set("state", params.get("state"));
  response.writeHead(302, { Location: callback.toString() });
  response.end();
}

function escapeHtml(value) {
  return value.replaceAll("&", "&amp;").replaceAll('"', "&quot;").replaceAll("<", "&lt;");
}

function readForm(request) {
  return new Promise((resolve, reject) => {
    let body = "";
    request.on("data", (chunk) => {
      body += chunk;
    });
    request.on("end", () => resolve(new URLSearchParams(body)));
    request.on("error", reject);
  });
}

const server = http.createServer(async (request, response) => {
  const url = new URL(request.url, `http://${request.headers.host}`);

  if (request.method === "GET" && url.pathname === "/issuer1/jwks") {
    return respondJson(response, 200, { keys: [publicJwk] });
  }

  if (
    (request.method === "GET" || request.method === "POST") &&
    url.pathname === "/issuer1/authorize"
  ) {
    const params = new URLSearchParams(url.search);
    if (request.method === "POST") {
      for (const [key, value] of await readForm(request)) {
        params.set(key, value);
      }
    }

    const username = params.get("login") || params.get("username");
    if (username) {
      return redirectAfterAuthorization(response, params, username);
    }

    const hiddenParams = [...params.entries()]
      .map(
        ([key, value]) =>
          `<input type="hidden" name="${escapeHtml(key)}" value="${escapeHtml(value)}">`,
      )
      .join("");
    response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    response.end(
      `<!doctype html><html><body><form method="post" action="${escapeHtml(url.pathname)}">` +
        `${hiddenParams}<label>Login <input name="login" autofocus></label>` +
        `<button type="submit">Sign in</button></form></body></html>`,
    );
    return;
  }

  if (request.method === "POST" && url.pathname === "/issuer1/token") {
    const params = await readForm(request);
    const code = params.get("code");
    const authorization = authorizationCodes.get(code);
    if (!authorization) {
      return respondJson(response, 400, {
        error: "invalid_grant",
        error_description: "Authorization code is invalid or already used",
      });
    }
    authorizationCodes.delete(code);

    const now = Math.floor(Date.now() / 1000);
    const idToken = signIdToken({
      iss: issuer,
      sub: authorization.username,
      aud: authorization.clientId,
      iat: now,
      exp: now + (oauthConfig.tokenCallbacks?.[0]?.tokenExpiry || 120),
      nonce: authorization.nonce,
      email: configuredEmail || `${authorization.username}@example.test`,
      email_verified: true,
    });
    return respondJson(response, 200, {
      access_token: crypto.randomBytes(24).toString("base64url"),
      token_type: "Bearer",
      expires_in: 120,
      id_token: idToken,
    });
  }

  if (request.method === "GET" && url.pathname === "/issuer1/endsession") {
    const redirectUri =
      url.searchParams.get("post_logout_redirect_uri") || url.searchParams.get("redirect_uri");
    if (redirectUri) {
      response.writeHead(302, { Location: redirectUri });
      return response.end();
    }
    return respondJson(response, 200, { message: "Signed out" });
  }

  if (request.method === "GET" && url.pathname === "/issuer1") {
    return respondJson(response, 200, { issuer });
  }

  return respondJson(response, 404, { error: "not_found" });
});

server.listen(port, "0.0.0.0", () => {
  process.stdout.write(`Local login.gov-compatible mock listening on http://localhost:${port}\n`);
});
