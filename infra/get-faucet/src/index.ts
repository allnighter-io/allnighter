/**
 * get.allnighter.io — install faucet only (OPC-S05).
 *
 * URL shape (canonical):
 *   GET /                              → install/get-alln.sh  (curl | sh)
 *   GET /latest.json                   → latest.json            (short TTL)
 *   GET /v<version>/alln-macos-universal → immutable release assets
 *   GET /v<version>/Allnighter.dmg
 *   GET /v<version>/*.sha256
 *
 * R2 object keys mirror the URL path (no leading slash).
 * Upload via scripts/upload-release-to-r2.sh after publish-release.sh.
 */

export interface Env {
  RELEASES: R2Bucket;
}

const INSTALL_KEY = "install/get-alln.sh";

function cacheControlForKey(key: string): string | null {
  if (key === "latest.json") {
    return "public, max-age=60";
  }
  if (/^v[^/]+\//.test(key)) {
    return "public, max-age=31536000, immutable";
  }
  if (key === INSTALL_KEY) {
    return "public, max-age=300";
  }
  return null;
}

function contentTypeForKey(key: string): string | null {
  if (key === INSTALL_KEY || key.endsWith(".sh")) {
    return "text/plain; charset=utf-8";
  }
  if (key.endsWith(".json")) {
    return "application/json; charset=utf-8";
  }
  if (key.endsWith(".sha256")) {
    return "text/plain; charset=utf-8";
  }
  if (key.endsWith(".dmg")) {
    return "application/octet-stream";
  }
  return "application/octet-stream";
}

function objectKey(pathname: string): string {
  const trimmed = pathname.replace(/^\/+/, "").replace(/\/+$/, "");
  if (trimmed === "") {
    return INSTALL_KEY;
  }
  return trimmed;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", { status: 405 });
    }

    const url = new URL(request.url);
    const key = objectKey(url.pathname);
    const object = await env.RELEASES.get(key);

    if (!object) {
      return new Response(`not found: ${key}`, {
        status: 404,
        headers: { "content-type": "text/plain; charset=utf-8" },
      });
    }

    const headers = new Headers();
    object.writeHttpMetadata(headers);

    const contentType = contentTypeForKey(key);
    if (contentType) {
      headers.set("content-type", contentType);
    }

    const cacheControl = cacheControlForKey(key);
    if (cacheControl) {
      headers.set("cache-control", cacheControl);
    }

    if (request.method === "HEAD") {
      return new Response(null, { status: 200, headers });
    }

    return new Response(object.body, { status: 200, headers });
  },
};
