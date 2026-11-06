# Cog on Cloudflare Workers

Cog, the RoboCore IDE's learning partner, on its own on Cloudflare: the same Cog as the RoboCore server
(`server/src/cog.js`: its instructions, the school-key check, the calls to the Anthropic API), without the compiler.
The Anthropic API key then never sits next to students' builds, it is always on (no waking up), and Cloudflare's free
plan covers a classroom.

The IDE talks to it as it would to the RoboCore server: the same routes (`GET /health`, `GET /cog/key`,
`POST /cog/chat`, `/cog/fix`, `/cog/check`) and the same answers. The macOS app compiles on the Mac, so the Worker's
address is all it needs. For the web IDE, set `COMPILE_SERVER` and the Worker passes every other request (compiles)
on to that server.

## Put it online

You need a Cloudflare account and an Anthropic API key (console.anthropic.com → API Keys; add credit and set a monthly
spending limit there).

```bash
bash cog-worker/deploy.sh
```

The first time it opens Cloudflare's sign-in page, uploads the Worker (about 130 KB), asks for the API key (hidden; it
goes straight to Cloudflare) and sets a school key, which it prints. Later runs only upload the new code. It prints the
Worker's address, `https://robocore-cog.<your subdomain>.workers.dev`.

Then in RoboCore, Settings:

- **Real board and upload → Compile server**: the Worker's address.
- **Cog → School key**: the school key. Then **Test Cog**.

To change a secret later, from this folder: `wrangler secret put ANTHROPIC_API_KEY` or `wrangler secret put COG_KEYS`
(all the schools' keys, comma-separated; to shut a school out, leave its key out).

## Settings

| Name | Where | What |
|---|---|---|
| `ANTHROPIC_API_KEY` | secret | Turns Cog on |
| `COG_KEYS` | secret | The schools' keys, comma-separated. Cog answers only requests that carry one |
| `COG_MODEL` | `wrangler.jsonc` | Default `claude-opus-5-5`; `claude-haiku-5-5` costs far less |
| `COG_EFFORT`, `COG_FIX_EFFORT` | `wrangler.jsonc` (optional) | How hard it thinks for chat and for fixes (`low`, `medium`, `high`) |
| `COG_RATE_PER_MIN` | `wrangler.jsonc` | Requests per minute from one address (12) |
| `COG_KEY_RATE_PER_MIN` | `wrangler.jsonc` | Requests per minute with one school key, all its classrooms together (60) |
| `ALLOWED_ORIGINS` | `wrangler.jsonc` | Web pages that may call it (the desktop apps send no Origin and are let in) |
| `COMPILE_SERVER` | `wrangler.jsonc` (optional) | Where other requests go, such as `/compile` from the web IDE |

The limits count per Worker instance: they stop one client or one school from running away with the credit, but they
are not an exact count across Cloudflare. The address limit uses `CF-Connecting-IP`, which Cloudflare sets itself.

## Tests

```bash
(cd server && npm ci) && node --test cog-worker/test/worker.test.mjs
```

They run the Worker in Node against a fake Anthropic API. To try it in Cloudflare's own runtime on your computer:
`wrangler dev --var ANTHROPIC_API_KEY:… --var COG_KEYS:…` from this folder.
