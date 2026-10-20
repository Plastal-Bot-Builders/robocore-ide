# Cog, the learning partner

Cog is the IDE's AI helper, built from the design's Cog screens and the behaviour spec (CG-01 to CG-08). It **guides
before it fixes**: it explains, gives hints one at a time, shows a fix only when asked, never changes code without
**Apply**, and asks one question afterwards so the idea sticks.

## What a student sees

- **Ask Cog** in the top bar (Ctrl/⌘ + I) opens the panel on the right; the board card moves into a Board tab while it is
  open. The panel shows what Cog can see as chips (file and line or blocks, Output errors, Serial Monitor, board);
  clicking one opens it.
- **Explain** on each row of Problems, **Explain with Cog** above the Output after a failed Verify, and in the code
  editor as a quick fix on the squiggle (lightbulb, Ctrl+.) and in the right-click menu.
- **The hint ladder**: explanation without the answer → *Give me a hint* → *Another hint* → *Show the fix* (in "Hints
  first" only after two hints) → a diff with **Apply** / **Not now** → a quick check → the idea joins **You've learned**.
- **Blocks**: select a block and ask *Explain …* (Cog explains it and shows its C++) → *Give me a challenge* (a "Try it"
  card) → *I tried it* (Cog looks at the project and says what works).
- **Settings → Cog**: help style (**Hints first**, the default; **Explain the answer**; **Write code for me**, which needs a
  teacher PIN), *Let Cog read this project*, and **Test Cog**.
- **Offline**: Cog says it needs the internet; writing code, Verify, Upload and the Serial Monitor keep working.

## How it is built

| Part | Where |
|---|---|
| Server routes, system prompt, task wording, model settings | `server/src/cog.js` (Anthropic SDK), routes in `server/src/server.js` |
| Client: streamed chat (server-sent events), fix, quick check, status | `lib/hw/cog_client.dart` |
| The conversation and both step-by-step flows | `lib/state/cog.dart` (`AppState.cog`) |
| Panel, Ask Cog button, Explain lens, diff, quick check, concepts | `lib/ui/cog/cog_panel.dart` |
| Selected block → Cog; Explain with Cog in the code editor | `web/robocore_editors.js` (`onSelect`, `onExplain`) |
| Settings → Cog | `lib/ui/pages/settings_page.dart` |
| Tests | `test/cog_test.dart`, `server/test/cog.test.js` (fake Anthropic API) |

The IDE only chooses the task; the words sent to the model are on the server. The student's project is sent only while
*Let Cog read this project* is on. Learned concepts are saved in each project (`Project.learned`).

## Setting it up

1. Get an Anthropic API key (console.anthropic.com). Keep it on the server only.
2. Locally: `cd server && npm ci && ANTHROPIC_API_KEY=… npm start`. On Render: the blueprint asks for
   `ANTHROPIC_API_KEY` (marked secret). Cloud Run: `--set-secrets` or `--set-env-vars`.
3. In the IDE: Settings → Real board and upload → the server's address, then Settings → Cog → **Test Cog**.

## Choosing the model (cost)

`COG_MODEL` defaults to **Claude Opus 5.5** (`claude-opus-5-5`, $4 / $20 per million input / output tokens), the
strongest current model. A typical Cog turn sends the system prompt plus a small project (roughly 3,000-5,000 tokens)
and gets a short answer back, so expect **about 2-4 US cents per question** on Opus 5.5, before caching. For a class of 30
asking 20 questions each, that is roughly $12-25 per lesson.

**Claude Haiku 5.5** (`COG_MODEL=claude-haiku-5-5`, $0.10 / $0.50) would cost well under a cent per question (about
$0.30-0.60 for the same lesson). It is a much smaller model; try it on real student questions before switching. Note
that the server-side refusal fallback is not available for Haiku 5.5. **Claude Sonnet 5.5** (`claude-sonnet-5-5`,
$2 / $10) sits between the two. These are estimates; check them in the Anthropic console against real use.

## Teacher PIN

Setting a PIN (Settings → Cog) is needed to turn on *Write code for me*, and once set, changing the help style asks for
it. It is a classroom lock against changes by accident, stored as a hash on the device; it is not a security feature
(clearing the browser's site data removes it).

## Trying it without a key

`server/test/cog.test.js` runs every route against a fake Anthropic API. For the UI, run any stand-in that answers
`POST /v1/messages` (streaming and JSON) and start the server with `ANTHROPIC_BASE_URL=http://127.0.0.1:<port>` and any
`ANTHROPIC_API_KEY`.

## Not done yet

- Cog works where the compile server is reachable; there is no offline model.
- One conversation at a time, kept until *New conversation* or reload (not saved).
- No per-student accounts or teacher dashboard; the PIN is per device.
- Explain with Cog from the Blockly right-click menu, and the Arduino reference links in hovers, are not built.
