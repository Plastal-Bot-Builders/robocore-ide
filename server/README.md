# RoboCore compile server

Turns a sketch from the RoboCore IDE (typed C++ or code made from blocks) into a program the board can run.
It runs the official **arduino-cli** with the **esp32 by Espressif 3.3.12** core, the RoboCore library
and the optional libraries the IDE lists (ESP32Servo, Adafruit NeoPixel, NewPing, LiquidCrystal I2C).
The IDE then flashes the result over USB-C with esptool-js.

It also runs **Cog**, the IDE's learning partner, through the Anthropic API (below). Compiling uses only Node 22's
built-in modules; Cog uses the official Anthropic SDK (`@anthropic-ai/sdk`, pinned in `package-lock.json`; `npm ci`).

## API

### `POST /compile`

```json
{
  "board": "v2",
  "main": "Blink.ino",
  "files": [
    { "name": "Blink.ino", "content": "void setup() {}\nvoid loop() {}\n" },
    { "name": "config.h", "content": "#pragma once\n" }
  ]
}
```

| Field | Rules |
|---|---|
| `board` | `v2` (RoboCore V2), `devkit`, `nodemcu`, `uno` |
| `files` | 1–20 files, names `letters/numbers/_/-` ending `.ino .h .hpp .c .cpp`, 200 KB each, 400 KB total |
| `main` | Optional. The main `.ino`; defaults to the first `.ino` |

Success (`ok: true`) for ESP32 boards:

```json
{
  "ok": true,
  "board": "v2",
  "problems": [ { "severity": "warning", "file": "Blink.ino", "line": 7, "column": 3, "message": "..." } ],
  "sizes": { "flash": { "used": 289306, "max": 3145728 }, "ram": { "used": 20118, "max": 327680 } },
  "log": "Sketch uses 289306 bytes ...",
  "image": {
    "format": "esp32", "chip": "esp32s3", "flashSize": "8MB",
    "parts": [
      { "name": "bootloader", "offset": 0,     "size": 15104,  "data": "<base64>" },
      { "name": "partitions", "offset": 32768, "size": 3072,   "data": "<base64>" },
      { "name": "boot_app0",  "offset": 57344, "size": 8192,   "data": "<base64>" },
      { "name": "app",        "offset": 65536, "size": 289456, "data": "<base64>" }
    ]
  },
  "elapsedMs": 8123
}
```

Pass `image.parts` straight to esptool-js `writeFlash({ fileArray: parts.map(p => ({ address: p.offset, data })) })`.
Uno builds return `"image": { "format": "hex", "data": ":10000000..." }`, which the IDE writes through the Uno's Optiboot
bootloader (`web/robocore_usb.js`, `flashAvr`).

Compile errors return HTTP 200 with `ok: false` and `problems` pointing at the user's file and line
(`"file": "library"` plus `"source"` when the error is inside a library). Server paths are removed from all output.

Other errors return `{ "error": "message" }` with HTTP 400 (bad request), 403 (site not allowed),
413 (too big), 415 (not JSON), 429 (too many compiles: 20 a minute per client), 503 (busy) or 504 (took over 2 minutes).

### `GET /health`, `GET /boards`

Health shows the arduino-cli and core versions, the queue, and `cog: {ready, model}`. Boards lists ids, names and FQBNs.

### Cog: `POST /cog/chat`, `/cog/fix`, `/cog/check`

The IDE sends the help style (`hints`, `explain`, `write`), the task (`chat`, `explain_error`, `hint`, `explain_block`,
`challenge`, `review_try`), the conversation so far, and what Cog may see (`context`: files, problems, the end of the
Output and the Serial Monitor, the selected block; `{"read": false}` when the student turned reading off).

- `/cog/chat` streams server-sent events: `{"t":"text","v":"…"}` pieces, then `{"t":"done"}`, `{"t":"refusal"}` or `{"t":"error"}`.
- `/cog/fix` returns `{explanation, file, newContent}` (structured output): the smallest change to one file.
- `/cog/check` returns `{question, options, answer, explanation, concept}`: one multiple-choice question after a fix.

The wording of every task and the system prompt live on the server (`src/cog.js`), so the IDE can't change what Cog is
asked to do. Requests use adaptive thinking with the effort below, prompt caching for the system prompt, and
`fallbacks: "default"` (beta `server-side-fallback-2026-07-01`), which re-runs a request on Anthropic's recommended
model if the first one declines it. Without `ANTHROPIC_API_KEY`, `/health` says `cog.ready: false` and the Cog routes
answer 503; compiling keeps working.

## Settings (environment variables)

| Variable | Default | |
|---|---|---|
| `PORT` | 8080 | |
| `ALLOWED_ORIGINS` | `https://plastal-bot-builders.github.io,http://localhost:*,http://127.0.0.1:*` | Sites allowed to call the server from a browser |
| `MAX_RUNNING` / `MAX_QUEUED` | 1 / 8 | Compiles at once / waiting |
| `COMPILE_JOBS` | 2 | Compiler threads per build |
| `COMPILE_TIMEOUT_MS` | 120000 | |
| `RATE_PER_MIN` | 20 | Per client |
| `ANTHROPIC_API_KEY` | (none) | Turns Cog on. Keep it secret: set it in the host's dashboard, never in the repo |
| `COG_MODEL` | `claude-opus-5-5` | The model Cog uses. See `docs/cog.md` for cost |
| `COG_EFFORT` / `COG_FIX_EFFORT` | `low` / `medium` | How much the model thinks for chat / for suggested fixes |
| `COG_RATE_PER_MIN` | 12 | Cog requests per client per minute |

## Run it

```bash
# from the repo root
docker build -f server/Dockerfile -t robocore-compile .
docker run --rm -p 8080:8080 robocore-compile
node server/test/smoke.mjs http://localhost:8080      # compiles every example for real
```

Without Docker (arduino-cli and the cores installed locally): `cd server && npm ci && npm start`
(add `ANTHROPIC_API_KEY=…` in front of `npm start` for Cog). `npm test` runs the unit tests with a fake arduino-cli and a
fake Anthropic API.

## Put it online

**Render (free):** New → Blueprint → pick this repo. `render.yaml` sets everything up.
The free plan sleeps after 15 minutes idle, so the first compile after a pause waits about a minute while it wakes,
and it has 512 MB of memory (enough with one compile at a time).

**Google Cloud Run** (more memory, also has a free tier):
```bash
gcloud run deploy robocore-compile --source . --region europe-west1 --memory 2Gi --cpu 2 \
  --allow-unauthenticated --set-env-vars ALLOWED_ORIGINS=https://plastal-bot-builders.github.io
```
(Cloud Run needs the Dockerfile at the root for `--source`; or build with `docker build -f server/Dockerfile` and deploy the image.)

Then put the server's address in the IDE (Settings → Compile server).

## Safety

- Sketches are only compiled, never run, on the server.
- Builds run as an unprivileged user in a throwaway folder that is deleted afterwards, with a minimal environment.
  Keep secrets out of this container: a sketch can `#include` any file the build user can read, and
  its contents could appear in an error message.
- Size, time, queue and rate limits stop one user from hogging the server.
- Only the IDE's site (and localhost) may call it from a browser.
