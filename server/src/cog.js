// Cog, the learning partner in the RoboCore IDE. It answers through Claude (the Anthropic API),
// so the API key stays on this server and never reaches the IDE.
//
//   POST /cog/chat   text/event-stream of {"t":"text","v":"…"} … then {"t":"done"} (or {"t":"refusal"} / {"t":"error"})
//   POST /cog/fix    {explanation, file, newContent}: the smallest change that fixes the problem
//   POST /cog/check  {question, options, answer, explanation, concept}: one question after a fix
//
// Needs ANTHROPIC_API_KEY, and COG_KEYS: the schools' keys, one of which each request carries in X-Cog-Key, so nobody
// else can spend the API credit (COG_OPEN=1 instead lets anyone in, for a server on your own computer). COG_MODEL picks
// the model (default claude-opus-5-5); COG_EFFORT and COG_FIX_EFFORT set how hard it thinks for chat / for fixes (low,
// medium, high).
//   GET /cog/key     200 when the X-Cog-Key header is a school key (the IDE's Test Cog)
import { createHash, timingSafeEqual } from 'node:crypto';
import Anthropic from '@anthropic-ai/sdk';
import { RequestError } from './compile.js';

// On a safety decline the API re-runs the request on Anthropic's recommended fallback model. Only some
// models offer it (not Claude Haiku 5.5), so it is sent only for those.
const FALLBACK_BETA = 'server-side-fallback-2026-07-01';
const FALLBACK_MODELS = new Set(['claude-opus-5-5', 'claude-opus-5', 'claude-fable-5-1', 'claude-sonnet-5-5']);

export const COG_LIMITS = {
  messages: 30, messageChars: 4000, files: 20, fileChars: 60_000, totalChars: 200_000, problems: 50, logChars: 8000,
};

export function cogConfig(env = process.env) {
  return {
    ready: Boolean(env.ANTHROPIC_API_KEY || env.ANTHROPIC_AUTH_TOKEN),
    model: env.COG_MODEL || 'claude-opus-5-5',
    effort: env.COG_EFFORT || 'low',
    fixEffort: env.COG_FIX_EFFORT || 'medium',
    ratePerMin: Number(env.COG_RATE_PER_MIN || 12),
    baseURL: env.ANTHROPIC_BASE_URL || undefined,
    keys: String(env.COG_KEYS || '').split(',').map((k) => k.trim()).filter(Boolean),
    open: env.COG_OPEN === '1',
  };
}

// Stays the same for every request, so the API can cache it.
const SYSTEM = `You are Cog, the learning partner inside RoboCore IDE. Students aged about 10 to 18, mostly in Zambian schools, use RoboCore IDE to program the RoboCore V2 classroom robot with blocks (Google Blockly) or Arduino C++. Many of them speak English as a second language, and many are programming for the first time.

How you talk
- Use short sentences and everyday words. Explain any technical word the first time you use it.
- Be warm and encouraging, never sarcastic. Mistakes are a normal part of learning; say so when a student is stuck.
- Keep answers short: usually under 120 words. Use a short list when steps help. Put code names in backticks.
- Only use fenced code blocks (\`\`\`cpp) when the help style allows code, or for the C++ of a block you are explaining.
- Be honest. If you are not sure, say so. Never invent functions, pins or libraries: use only Arduino core functions and the RoboCore library below. If something can only be checked on the real robot, say how to check it.
- Stay on coding, robots, electronics, maths and science that help the project. For anything else, say kindly that you can only help with their RoboCore project.
- Never ask for or repeat personal information. If a student shares some (a full name, an address, a phone number), don't repeat it, and remind them kindly not to share personal details here.
- You are an AI, not a person. If a student asks, say so plainly.
- Don't use emoji: the IDE can't show them.

Keeping students safe
- If a student says they are being hurt, bullied or threatened, that they feel unsafe or very sad, or that they might hurt themselves or someone else: answer kindly in one or two sentences, say it is not their fault, and tell them to talk to a trusted adult now, such as a teacher, a parent or a guardian. Don't ask for details, don't try to counsel them, and don't keep the subject going. Then offer to carry on with their project when they are ready.

How you help
- Each request says which help style the student or teacher chose. Follow it exactly:
  - Hints first: help the student find the answer. Explain what is wrong and why, without giving the corrected code or the exact fix. Give one hint at a time, each a little more specific than the last.
  - Explain the answer: explain the problem and the fix clearly in words. Small snippets are fine; do not rewrite their whole sketch.
  - Write code for me: you may write or change code when asked, and then explain each part briefly.
- Each request also gives an explanation level. Beginner: everyday words, one idea at a time, no jargon. Intermediate: name the programming idea (variable, loop, function) and use it. Advanced: be precise and brief, with the C++ terms a programmer would use.
- When you can see the project, refer to the student's own file names, line numbers and blocks.
- When the student is in the Blocks editor, talk about blocks first and their C++ second.

RoboCore V2 board (ESP32-S3)
- One include gives everything: #include <RoboCore.h>.
- RoboCoreMotors motors; motors.begin(); motors.drive(left, right) with each speed in percent from -100 (full reverse) to 100 (full forward), so drive(60, 60) goes forward and drive(-50, 50) turns left; motors.stop() (coast); motors.brake(); one wheel at a time: motors.run(LEFT, 1, ROTATIONS) (or DEGREES, SECONDS; waits), motors.start(RIGHT, 50), motors.stop(LEFT), motors.positionDeg(LEFT) (360 = one turn), motors.resetPosition(LEFT), motors.speedPercent(LEFT); motors.leftCount() / rightCount() encoder counts.
- Driving base: IMU imu; RoboCoreDrive robot(motors, imu); robot.move(10, CM) (or ROTATIONS, SECONDS; negative = backwards; waits until done); robot.turn(90) (positive = right, uses the IMU heading; waits); robot.start(FORWARD) / start(BACKWARD); robot.steer(-100 to 100) (0 straight, 50 one wheel stopped, 100 spins); robot.stop() (brake); robot.setSpeed(percent) (default 50); robot.setWheelCm(18.8); robot.distanceCm().
- Servos: RoboCoreServos servos; servos.write(port 1 to 4, degrees 0 to 180); servos.angle(port).
- Sonar sonar; sonar.begin(); float cm = sonar.distanceCm(); (400 when nothing echoes); sonar.justCloserThan(cm) is true once when something comes closer.
- LineSensor line; line.begin(); float pos = line.read(); is -1 when the line is under the left sensor, 0 when centred, 1 on the right. line.left(), line.centre(), line.right() give 0.0 (white) to 1.0 (black); line.onLine(); line.justFound() / justLost() are true once.
- IMU imu; imu.begin() (keep the robot still: it measures the gyro); imu.yawDeg() heading (turning right counts up), imu.resetYaw(); imu.pitchDeg() / rollDeg() / tiltDeg(); imu.isTilted() / isShaken() / isFlat() and justTilted() / justShaken() / justFlat(); imu.temperature().
- Board helpers: RoboCore::batteryVolts() / batteryPercent(), RoboCore::userPressed() / userJustPressed(), RoboCore::beep(freqHz, ms) (waits), RoboCore::melody(MELODY_POWER_UP / _POWER_DOWN / _SUCCESS / _ERROR / _ALARM), RoboCore::rgb(r, g, b) with 0 to 255 each, RoboCore::ledBrightness(percent), RoboCore::timer() / resetTimer() / timerPassed(seconds), RoboCore::stopProgram(). RoboCoreEdge when1; when1.rose(condition) is true once each time the condition becomes true.
- Pins: USER button RC_PIN_USER_BUTTON (42, LOW when pressed), buzzer RC_PIN_BUZZER (47, use tone()), RGB LED RC_PIN_RGB_LED (48, also called RGB_BUILTIN), servos 38, 39, 35, 36, free expansion pins 3, 37, 43, 44. There is no plain LED: LED_BUILTIN lights the RGB LED white.
- Serial.begin(115200) and Serial.println() print to the Serial Monitor in the IDE.
- Some values only make sense on the real robot (distances, the heading): the preview board simulates them roughly.

Blocks and the C++ they make (10 categories, hardware first)
- Events: on start → void setup() { … }; forever → void loop() { … }; the "when …" hats (when USER button is pressed, when obstacle is closer than 20 cm, when the line is found / lost, when the robot is tilted / shaken / flat, when timer > 10 s, when <condition>) become if (…just…()) { … } at the top of loop(), so keep forever free of long waits; when I receive message1 → void on_message1() { … }; broadcast message1 → on_message1();
- Movement: move forward for 10 cm → robot.move(10, CM); turn right for 90 ° → robot.turn(90); start moving forward → robot.start(FORWARD); start moving, steering 30 → robot.steer(30); drive left 50 % right 50 % → motors.drive(50, 50); stop moving → robot.stop(); set movement speed to 50 % → robot.setSpeed(50); set 1 wheel turn to 18.8 cm; distance moved (cm) → robot.distanceCm().
- Motors: run left motor for 1 rotations → motors.run(LEFT, 1, ROTATIONS); start / stop / reset left motor; left motor position (°) / speed (%); set servo 1 to 90 ° → servos.write(1, 90); servo 1 angle.
- Light & Sound: turn LED on/off → digitalWrite(LED_BUILTIN, HIGH/LOW); set LED to red → RoboCore::rgb(255, 0, 0); set LED brightness; play beep C5 for 0.2 s → RoboCore::beep(523, 200); start playing beep → tone(RC_PIN_BUZZER, 523); play melody; stop sound → noTone(RC_PIN_BUZZER).
- Sensors: distance (cm); is obstacle closer than 20 cm? → sonar.distanceCm() < 20; line position; is centre sensor on the line? → line.centre() > 0.5; centre line sensor (%); tilt angle; yaw / pitch / roll angle; set yaw angle to 0; is the robot tilted?; is USER button pressed? → RoboCore::userPressed(); battery %; temperature; timer; reset timer.
- Control: wait 1 secs → delay(1000); repeat 5 times (a for loop); if / if else; wait until <condition> → while (!(condition)) { delay(10); }; repeat until; stop program.
- Operators: arithmetic, compare, and / or / not, pick random 1 to 10 → random(1, 11), is x between a and b?, round, join → String("cm: ") + value.
- Variables: set / change / get (int, float or String, from what is stored). My Blocks: define "blink twice" → void blinkTwice() { … }, and its call block.
- Pins & Serial: set pin IO37 to HIGH, read pin, read analog pin, start serial at 115200 baud, print "text" or a value → Serial.println(…), serial read line.

Verify compiles the sketch with arduino-cli for the ESP32-S3; Upload sends it to the robot over USB-C, or runs it on the preview board (a simulator) when no robot is connected.`;

const STYLE = {
  hints: 'Help style: Hints first.',
  explain: 'Help style: Explain the answer.',
  write: 'Help style: Write code for me.',
};

// Settings → Cog → Explanation level.
const LEVEL = {
  beginner: 'Explanation level: Beginner.',
  intermediate: 'Explanation level: Intermediate.',
  advanced: 'Explanation level: Advanced.',
};

// What each kind of request asks Cog to do. The IDE only picks the task; the words stay here.
const TASKS = {
  chat: () => 'Answer the student\'s message.',
  explain_error: () => 'The student pressed "Explain" on a problem from Verify. Explain the first error in simple words: what it means and roughly where to look. Follow the help style about how much of the fix to show. End with one short question that invites them to try.',
  hint: (n) => `The student asked for hint ${n} about the same problem. Give exactly one new hint, more specific than the hints you already gave, in one or two sentences. Do not give the corrected code.`,
  explain_block: () => 'The student selected a block and asked what it does. Explain it in two or three sentences with one everyday example, then show the C++ it makes (from the selected block below) in a cpp code block.',
  challenge: () => 'Give the student one small "Try it" challenge that changes their current project and takes about five minutes. One or two sentences, starting with a verb. Do not give the solution.',
  review_try: () => 'The student says they tried the last challenge. Look at their project now: say what works, and if the challenge is not done yet, give one hint. Be encouraging. Two to four sentences.',
};

const clip = (s, n) => {
  const t = String(s ?? '');
  return t.length > n ? t.slice(0, n) + '\n[…cut]' : t;
};

/// Checks and trims a Cog request from the IDE.
export function validateCog(body, { needTask = true } = {}) {
  if (!body || typeof body !== 'object') throw new RequestError(400, 'Send a JSON object.');
  const style = STYLE[body.style] ? body.style : 'hints';
  const level = LEVEL[body.level] ? body.level : 'beginner';
  const task = body.task ?? 'chat';
  if (needTask && !TASKS[task]) throw new RequestError(400, `Unknown task ${String(task).slice(0, 40)}.`);
  const raw = Array.isArray(body.messages) ? body.messages : [];
  if (raw.length > COG_LIMITS.messages) throw new RequestError(413, 'The conversation is too long. Start a new one.');
  const messages = [];
  for (const m of raw) {
    if (!m || (m.role !== 'user' && m.role !== 'assistant') || typeof m.content !== 'string' || !m.content.trim()) continue;
    if (m.content.length > COG_LIMITS.messageChars) throw new RequestError(413, 'A message is too long.');
    messages.push({ role: m.role, content: m.content });
  }
  const ctx = body.context && typeof body.context === 'object' ? body.context : {};
  const files = Array.isArray(ctx.files) ? ctx.files.slice(0, COG_LIMITS.files) : [];
  let total = 0;
  for (const f of files) {
    if (typeof f?.name !== 'string' || typeof f?.content !== 'string') throw new RequestError(400, 'Each file needs a name and content.');
    if (f.content.length > COG_LIMITS.fileChars) throw new RequestError(413, `${f.name.slice(0, 60)} is too big for Cog.`);
    total += f.content.length;
  }
  if (total > COG_LIMITS.totalChars) throw new RequestError(413, 'The project is too big for Cog.');
  return {
    style,
    level,
    task,
    hint: Math.max(1, Math.min(3, Number(body.hint) || 1)),
    messages,
    context: {
      read: ctx.read !== false,
      project: clip(ctx.project, 80),
      board: clip(ctx.board, 80),
      editor: ctx.editor === 'blocks' ? 'blocks' : 'code',
      files: files.map((f) => ({ name: clip(f.name, 80), content: f.content })),
      problems: (Array.isArray(ctx.problems) ? ctx.problems : []).slice(0, COG_LIMITS.problems).map((p) => ({
        file: clip(p?.file, 80), line: Number(p?.line) || 0, column: Number(p?.column) || 0,
        severity: p?.severity === 'warning' ? 'warning' : 'error', message: clip(p?.message, 500),
      })),
      output: clip(ctx.output, COG_LIMITS.logChars),
      serial: clip(ctx.serial, COG_LIMITS.logChars),
      block: ctx.block && typeof ctx.block === 'object' ? { label: clip(ctx.block.label, 120), cpp: clip(ctx.block.cpp, 2000) } : null,
    },
  };
}

const esc = (s) => String(s).replace(/</g, '‹');

// What Cog can see, as one block of text at the start of the latest user turn.
function contextText(c) {
  if (!c.read) return 'The student turned off "Let Cog read this project", so you cannot see their code, output or serial monitor. Answer in general terms, and say so if seeing the code would matter.';
  const parts = [`<project name="${esc(c.project || 'Untitled')}" board="${esc(c.board || 'RoboCore V2')}" editor="${c.editor}">`];
  for (const f of c.files) parts.push(`<file name="${esc(f.name)}">\n${f.content}\n</file>`);
  if (c.problems.length) {
    parts.push('<problems>\n' + c.problems.map((p) => `${p.file}:${p.line}${p.column ? ':' + p.column : ''} ${p.severity}: ${p.message}`).join('\n') + '\n</problems>');
  }
  if (c.output.trim()) parts.push(`<output>\n${c.output}\n</output>`);
  if (c.serial.trim()) parts.push(`<serial_monitor>\n${c.serial}\n</serial_monitor>`);
  if (c.block) parts.push(`<selected_block label="${esc(c.block.label)}">\n${c.block.cpp}\n</selected_block>`);
  parts.push('</project>');
  return parts.join('\n');
}

// The conversation for the API: earlier turns as they were, the latest user turn with the project
// context, the help style and the task in front of the student's words.
function apiMessages(job, instruction) {
  const msgs = job.messages.slice();
  while (msgs.length && msgs[0].role !== 'user') msgs.shift();
  const last = msgs.length && msgs[msgs.length - 1].role === 'user' ? msgs.pop() : null;
  const content = [
    { type: 'text', text: contextText(job.context) },
    { type: 'text', text: `${STYLE[job.style]}\n${LEVEL[job.level]}\nTask: ${instruction}` },
  ];
  if (last) content.push({ type: 'text', text: `The student: ${last.content}` });
  msgs.push({ role: 'user', content });
  return msgs;
}

const FIX_SCHEMA = {
  type: 'object',
  properties: {
    explanation: { type: 'string', description: 'One or two short sentences: what was wrong and what the change does.' },
    file: { type: 'string', description: 'The name of the file that changes, exactly as given.' },
    newContent: { type: 'string', description: 'The whole new content of that file.' },
  },
  required: ['explanation', 'file', 'newContent'],
  additionalProperties: false,
};

const CHECK_SCHEMA = {
  type: 'object',
  properties: {
    question: { type: 'string' },
    options: { type: 'array', items: { type: 'string' }, description: 'Two to four short answers, often lines of code.' },
    answer: { type: 'integer', description: 'Index of the right option, from 0.' },
    explanation: { type: 'string', description: 'One sentence on why the right answer is right.' },
    concept: { type: 'string', description: 'The idea being learned, in two to four words, e.g. "Names are case-sensitive".' },
  },
  required: ['question', 'options', 'answer', 'explanation', 'concept'],
  additionalProperties: false,
};

function friendly(e) {
  if (e instanceof Anthropic.RateLimitError) return 'Cog is busy right now. Try again in a minute.';
  if (e instanceof Anthropic.AuthenticationError || e instanceof Anthropic.PermissionDeniedError) return 'Cog is not set up correctly on the server (API key).';
  if (e instanceof Anthropic.APIConnectionError) return 'The server could not reach Cog. Check its internet connection.';
  if (e instanceof Anthropic.APIError) return 'Cog hit a problem. Try again.';
  return 'Cog hit a problem. Try again.';
}

// Keys are compared as hashes of the same length, so how long a check takes says nothing about them.
const digest = (s) => createHash('sha256').update(String(s)).digest();

export function makeCog(cfg) {
  const client = cfg.ready ? new Anthropic({ ...(cfg.baseURL ? { baseURL: cfg.baseURL } : {}), ...(cfg.apiKey ? { apiKey: cfg.apiKey } : {}) }) : null;
  const keys = (cfg.keys ?? []).map(digest);
  const notReady = () => new RequestError(503, 'Cog is not set up on this server yet: it needs an Anthropic API key (ANTHROPIC_API_KEY).');
  const base = (effort, maxTokens) => ({
    model: cfg.model,
    max_tokens: maxTokens,
    ...(FALLBACK_MODELS.has(cfg.model) ? { betas: [FALLBACK_BETA], fallbacks: 'default' } : {}),
    cache_control: { type: 'ephemeral' },
    system: SYSTEM,
    output_config: { effort },
  });

  async function structured(job, instruction, schema, effort) {
    if (!client) throw notReady();
    let msg;
    try {
      const p = base(effort, 16000);
      msg = await client.beta.messages.create({
        ...p,
        output_config: { ...p.output_config, format: { type: 'json_schema', schema } },
        messages: apiMessages(job, instruction),
      });
    } catch (e) {
      throw new RequestError(e instanceof Anthropic.RateLimitError ? 429 : 502, friendly(e));
    }
    if (msg.stop_reason === 'refusal') throw new RequestError(422, 'Cog can\'t help with that one. Try asking about your code or your robot.');
    if (msg.stop_reason === 'max_tokens') throw new RequestError(502, 'Cog\'s answer was too long. Try again.');
    const text = msg.content.filter((b) => b.type === 'text').map((b) => b.text).join('');
    try {
      return JSON.parse(text);
    } catch {
      throw new RequestError(502, 'Cog gave an answer the IDE could not read. Try again.');
    }
  }

  return {
    get ready() { return cfg.ready; },
    get model() { return cfg.model; },
    /// Whether requests need a school key.
    get keys() { return !cfg.open; },

    /// Throws unless [key] (the X-Cog-Key header) lets the request in.
    admit(key) {
      if (cfg.open) return;
      if (!keys.length) {
        throw new RequestError(503, 'Cog on this server needs school keys first (COG_KEYS). A server on your own computer can set COG_OPEN=1 instead.');
      }
      const d = digest(key ?? '');
      if (key && keys.some((k) => timingSafeEqual(k, d))) return;
      throw new RequestError(401, key ? 'That school key is not right. Check it in Settings → Cog.' : 'This Cog server needs a school key. A teacher can add it in Settings → Cog.');
    },

    /// Streams the reply to [res] as server-sent events. [onClose] registers a callback for when the
    /// IDE goes away, which stops the request to the API.
    async chat(job, res, headers, onClose) {
      if (!client) throw notReady();
      res.writeHead(200, {
        ...headers,
        'Content-Type': 'text/event-stream; charset=utf-8',
        'Cache-Control': 'no-store',
        'X-Accel-Buffering': 'no',
        'X-Content-Type-Options': 'nosniff',
      });
      const event = (o) => res.write(`data: ${JSON.stringify(o)}\n\n`);
      const instruction = TASKS[job.task](job.hint);
      const stream = client.beta.messages.stream({ ...base(cfg.effort, 8000), messages: apiMessages(job, instruction) });
      let closed = false;
      onClose(() => { closed = true; stream.abort(); });
      stream.on('text', (t) => event({ t: 'text', v: t }));
      try {
        const msg = await stream.finalMessage();
        if (msg.stop_reason === 'refusal') event({ t: 'refusal', message: 'Cog can\'t help with that one. Try asking about your code or your robot.' });
        event({ t: 'done', stop: msg.stop_reason });
      } catch (e) {
        if (!closed) event({ t: 'error', message: friendly(e) });
      }
      res.end();
    },

    async fix(job) {
      const files = job.context.files;
      if (!job.context.read || !files.length) throw new RequestError(400, 'Cog needs to read the project to suggest a fix.');
      const fix = await structured(job,
        'Suggest the smallest change to one file that fixes the first error (or the problem the student described). Keep their style, names and comments; change only what is needed. Return the whole new content of that one file.',
        FIX_SCHEMA, cfg.fixEffort);
      const before = files.find((f) => f.name === fix.file);
      if (!before) throw new RequestError(502, 'Cog suggested a change to a file that is not in the project. Try again.');
      if (typeof fix.newContent !== 'string' || !fix.newContent.trim() || fix.newContent === before.content) {
        throw new RequestError(502, 'Cog could not find a change to suggest.');
      }
      return { explanation: String(fix.explanation), file: fix.file, newContent: fix.newContent };
    },

    async check(job) {
      const q = await structured(job,
        'The student just applied a fix. Write one multiple-choice question (two to four options) that checks they understood the idea behind it. Not a trick question.',
        CHECK_SCHEMA, cfg.effort);
      const ok = typeof q.question === 'string' && Array.isArray(q.options) && q.options.length >= 2 && q.options.length <= 4 &&
        q.options.every((o) => typeof o === 'string') && Number.isInteger(q.answer) && q.answer >= 0 && q.answer < q.options.length;
      if (!ok) throw new RequestError(502, 'Cog could not make a question this time.');
      return { question: q.question, options: q.options, answer: q.answer, explanation: String(q.explanation), concept: String(q.concept) };
    },
  };
}
