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
- **Blocks and code from Cog into the project**: in a blocks project Cog gives its answer as a stack of blocks drawn in
  the chat, with **Add to my blocks**: the stack lands loose beside the program (greyed until it is joined on), nothing
  of the student's changes, and one Undo takes it away. In a code project each piece of code has **Insert in my code**
  (at the cursor, one undo step). Both have **Copy**. Cog hands answers over in **Explain the answer** and **Write code
  for me**; in **Hints first** it only guides, and the stack comes with *Show the fix* after two hints. A line of a
  stack that is not a real block is shown as plain text and is never added.
- **Settings → Cog**: help style (**Hints first**, the default; **Explain the answer**; **Write code for me**, which needs a
  teacher PIN), *Let Cog read this project*, and **Test Cog**. Cog works straight away: there is no address or key to
  type (see "Setting it up").
- **Offline**: Cog says it needs the internet; writing code, Verify, Upload and the Serial Monitor keep working.

## How it is built

| Part | Where |
|---|---|
| Server routes, system prompt, task wording, the two engines | `server/src/cog.js` (Anthropic SDK for Claude; `fetch` for OpenAI-format services), routes in `server/src/server.js` |
| Client: streamed chat (server-sent events), fix, quick check, status | `lib/hw/cog_client.dart` |
| The conversation and both step-by-step flows | `lib/state/cog.dart` (`AppState.cog`) |
| Panel, Ask Cog button, Explain lens, diff, quick check, concepts | `lib/ui/cog/cog_panel.dart` |
| Selected block → Cog; Explain with Cog in the code editor | `web/robocore_editors.js` (`onSelect`, `onExplain`) |
| Cog's blocks scripts → rows to draw and Blockly JSON | `lib/engine/block_script.dart` (the catalogue as it reads on the blocks) |
| Stacks into the workspace, code to the cursor | `web/robocore_editors.js` (`rcEditor.blocks.add`, `rcEditor.code.insert`), `cogAddBlocks` / `cogInsertCode` in `lib/state/cog.dart`, set by the editor page |
| Settings → Cog | `lib/ui/pages/settings_page.dart` |
| Tests | `test/cog_test.dart`, `test/block_script_test.dart`, `test/cog_give_test.dart`, `server/test/cog.test.js` (fake Anthropic API), `server/test/cog_openai.test.js` (fake OpenAI-format service) |

The IDE only chooses the task; the words sent to the model are on the server. The student's project is sent only while
*Let Cog read this project* is on. Learned concepts are saved in each project (`Project.learned`).

**Blocks scripts.** In the Blocks editor the model is told to answer with a fenced block that starts with
`` ```blocks ``: one block per line, worded as the block reads (`move forward for 20 cm`), the blocks inside another
indented by two spaces, `else` on its own line. The rule is repeated beside each question (`editorNote` in
`server/src/cog.js`), because a small model follows it there and not from the long instructions alone. The IDE reads
the lines against the block catalogue (`_statements` and `_reporters` in `block_script.dart`): a new block in
`web/robocore_editors.js` needs its line there and in the list in the system prompt. The IDE also says which editor
is open when it may not read the project, so Cog knows to answer with blocks.

## Setting it up

**Nothing to set up in the IDE.** Every copy of the IDE asks RoboCore's own Cog, `https://robocore-cog.robocorezambia.workers.dev`
(`kCogServer` in `lib/hw/cog_client.dart`): the Cog Worker in `cog-worker/` (its README says how it is put online). It
is open to everyone (`COG_OPEN=1`), so no school key is needed; instead each question counts against daily limits, for
one computer, one internet address and everyone together (`cog-worker/src/quota.js`). The IDE sends its own random
number with each question (`X-Cog-Device`, `Settings.cogDevice`, made the first time Cog is asked) so the limits are
shared fairly between computers; the Worker only keeps hashes of it and of the address, salted with the day. While
RoboCore is being tested the Worker uses Cloudflare's free AI, about 45 questions a day for everyone.

A school with its own RoboCore server and Cog uses **Settings → Cog → Use your school’s own Cog server…** (an address
and, if that server asks for one, its school key). A school key that RoboCore's Cog knows (`COG_KEYS`) skips its daily
limits. Devices that had the Cog Worker's workers.dev address typed in as their compile server have it removed on
the next start (it never compiled).

A RoboCore server of your own with Cog:

1. Get an Anthropic API key (console.anthropic.com). Keep it on the server only. (For another AI, see "Another AI"
   below.)
2. Locally: `cd server && npm ci && ANTHROPIC_API_KEY=… npm start`. On Render: the blueprint asks for
   `ANTHROPIC_API_KEY` (marked secret). Cloud Run: `--set-secrets` or `--set-env-vars`.
3. In the IDE: Settings → Cog → **Use your school’s own Cog server…**, the server's address (and its school key),
   then **Test Cog**.

## Choosing the model (cost)

A typical Cog turn sends the instructions plus a small project (roughly 3,000-5,000 tokens) and gets a short answer
back. Prices are per million input / output tokens, from Anthropic's price list on 18 November 2026; a lesson is a
class of 30 asking 20 questions each.

| `COG_MODEL` | Price | One question | One lesson |
|---|---|---|---|
| `claude-haiku-5-5` (the default) | $0.10 / $0.50 | well under a tenth of a cent | about $0.30-0.60 |
| `claude-sonnet-5-5` | $2 / $10 | about 1-2 cents | about $6-12 |
| `claude-opus-5-5` | $4 / $20 | about 2-4 cents | about $12-25 |

Haiku 5.5 is the smallest Claude: try it on real student questions, and move up a model if its explanations fall
short. The refusal fallback (a declined request re-run on Anthropic's recommended model) is not offered for Haiku 5.5.
Set a monthly spending limit in the Anthropic console, and check these estimates there against real use.

## Another AI (`COG_PROVIDER=openai`)

Cog can also get its answers from any service that speaks the OpenAI chat format (`POST …/chat/completions`): a model
on a computer the school owns, or another company's service. The instructions, the hint ladder, the school keys and
everything in the IDE stay the same.

A model on your own computer costs nothing per question and keeps students' words in the building, and Cog then works
without the internet (the IDE still has to reach the RoboCore server on the school's network). Open models that fit
on a laptop explain less well than Claude, and one computer answers a whole class slowly. With [Ollama](https://ollama.com):

```bash
ollama pull <a model>          # one that fits the computer's memory
cd server && npm ci
COG_PROVIDER=openai COG_BASE_URL=http://127.0.0.1:11434/v1 COG_MODEL=<that model> COG_LOCAL=1 COG_OPEN=1 npm start
```

Give the model a context window of at least 16,000 tokens (in Ollama: `OLLAMA_CONTEXT_LENGTH=16384`). With a smaller
one it quietly loses part of Cog's instructions or of the student's project. When the server runs in Docker and the
model on the same computer, the model's address is `http://host.docker.internal:11434/v1`.

A company's service needs its address, its key, and who it is, e.g. DeepSeek (`api-docs.deepseek.com`):

```bash
COG_PROVIDER=openai COG_BASE_URL=https://api.deepseek.com COG_MODEL=deepseek-flash COG_API_KEY=… \
COG_AI_NAME=DeepSeek COG_AI_COMPANY=DeepSeek COG_AI_WHERE=China COG_KEYS=… npm start
```

Cloudflare's own AI is set up ready-made, for nothing up to a daily allowance: `bash cog-worker/deploy.sh cloudflare`
(`cog-worker/README.md`, "Without paying"). Groq, OpenRouter and Ollama's cloud work the same way, with the address
their documentation gives for the OpenAI format. Free allowances are small (tens to a few hundred questions a day) and change without
notice, and some free tiers use what is sent to train models: read the terms before a class uses one.

**Who answers.** The IDE tells every student what Cog is and where their words go, before the first question. That
text comes from the server: `COG_LOCAL=1` ("where the AI runs; not sent on to another company"), or `COG_AI_COMPANY`
and `COG_AI_WHERE` ("on to DeepSeek, a company in China"). A service without them stays shut. When a server changes
its AI, each device shows the new notice before anything else is sent, and an IDE too old to do that (its notice says
Claude) gets no answer from another AI.

How the engines differ: structured answers (the fix, the quick check) are asked for by JSON Schema, then as plain JSON
when the service doesn't know that, and are checked either way; a model's thinking (`<think>…</think>` or a separate
reasoning field) never reaches the student; `COG_EFFORT` only applies to Claude; `COG_EXTRA_BODY` adds settings a
service documents to every request, as JSON; `COG_JSON_MODE` and the two token caps are in `server/README.md`. A
free allowance that is used up for the day is said plainly ("Cog will be back tomorrow"). This engine is tested against a stand-in service only: try a real model
on real questions before a class does.

## Teacher PIN

Setting a PIN (Settings → Cog) is needed to turn on *Write code for me*, and once set, changing the help style asks for
it. It is a classroom lock against changes by accident, stored as a hash on the device; it is not a security feature
(clearing the browser's site data removes it).

## Trying it without a key

`server/test/cog.test.js` runs every route against a fake Anthropic API. For the UI, run any stand-in that answers
`POST /v1/messages` (streaming and JSON) and start the server with `ANTHROPIC_BASE_URL=http://127.0.0.1:<port>` and any
`ANTHROPIC_API_KEY`.

## Not done yet

- Cog works where the RoboCore server is reachable. Without the internet that means a server and a model on the
  school's own network ("Another AI"); there is no model inside the IDE itself.
- One conversation at a time, kept until *New conversation* or reload (not saved).
- No per-student accounts or teacher dashboard; the PIN is per device.
- Explain with Cog from the Blockly right-click menu, and the Arduino reference links in hovers, are not built.
