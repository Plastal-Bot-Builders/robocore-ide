# Cog on Cloudflare Workers

Cog, the RoboCore IDE's learning partner, on its own on Cloudflare: the same Cog as the RoboCore server
(`server/src/cog.js`: its instructions, the school-key check, the calls to the Anthropic API), without the compiler.
The AI's key then never sits next to students' builds, it is always on (no waking up), and Cloudflare's free
plan covers a classroom. Cog answers through Claude (paid per question), or, for nothing, through Cloudflare's own AI
("Without paying", below).

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

To change a secret later, from this folder: `wrangler secret put ANTHROPIC_API_KEY --env=` or
`wrangler secret put COG_KEYS --env=` (all the schools' keys, comma-separated; to shut a school out, leave its key
out). `--env=` means the top of `wrangler.jsonc`, which is Claude; `--env cloudflare` is the set-up below.

## Without paying: Cloudflare's own AI

For testing, or while there is no budget: the same Worker can get its answers from Workers AI, the models Cloudflare
runs itself, instead of Claude. Cloudflare gives every account 10,000 "Neurons" a day for nothing, which is about 50
Cog questions with the model set here, and on the free plan it stops for the day when they are used up (it does not
bill). No card and no Anthropic key are needed.

```bash
bash cog-worker/deploy.sh cloudflare
```

The first time it asks for a **Workers AI API token**: in the Cloudflare dashboard, on the Workers AI page, select
*Use REST API*, then *Create a Workers AI API Token*, then *Create API Token*, and copy it. Paste it when the script
asks (hidden; it goes straight to Cloudflare). The script also sets the account's AI address and a school key.
The settings are in `wrangler.jsonc` under `env.cloudflare`.

What to know:

- **It is enough for testing, not for a class.** Thirty students asking 20 questions each is 600 questions. A smaller
  model (`@cf/meta/llama-3.1-8b-instruct-fp8-fast`, about 300 questions a day) explains less well. When the allowance
  is gone, Cog tells students it will be back tomorrow (it resets at 00:00 UTC, 02:00 in Zambia).
- **The answers are weaker than Claude's.** Read a few real ones before students rely on them.
- **The IDE says who answers.** Its notice tells students their words go on to Cloudflare, a company in the United
  States. Cloudflare's Workers AI data page says it does not keep them or train on them.
- **Going back to Claude** is `bash cog-worker/deploy.sh` again; each device then shows the notice for Claude before
  the next question.
- This set-up is tested against a stand-in service and with `wrangler deploy --dry-run`; it has not run on a real
  Cloudflare account yet. Ask Cog a few questions after the first deploy.

## Settings

| Name | Where | What |
|---|---|---|
| `ANTHROPIC_API_KEY` | secret | Turns Cog on (with Claude; for another AI see "Without paying" above and `docs/cog.md`, "Another AI") |
| `COG_KEYS` | secret | The schools' keys, comma-separated. Cog answers only requests that carry one |
| `COG_MODEL` | `wrangler.jsonc` | Default `claude-haiku-5-5`, the cheapest Claude; `claude-sonnet-5-5` and `claude-opus-5-5` are stronger and cost 20 and 40 times as much |
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

They run the Worker in Node against a fake Anthropic API; `server/test/cog_openai.test.js` runs it with the
`env.cloudflare` settings against a fake OpenAI-format service. To try it in Cloudflare's own runtime on your computer:
`wrangler dev --var ANTHROPIC_API_KEY:… --var COG_KEYS:…` from this folder.
