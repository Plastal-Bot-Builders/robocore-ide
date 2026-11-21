// Cog's daily limits when it is open to everyone (COG_OPEN=1): how many questions one computer, one internet address
// and everyone together may ask in a day (UTC). The counts live in one Durable Object, so every Cloudflare server sees
// the same numbers. It never sees an address or a device's number: the Worker sends hashes salted with the day, which
// can't be turned back into the address, or matched from one day to the next. Each new day starts from nothing.

/** The day the counts belong to, in UTC (Cloudflare's free AI allowance resets at 00:00 UTC too). */
export const today = (now = Date.now()) => new Date(now).toISOString().slice(0, 10);

/** Seconds until the next day starts, for Retry-After. */
export const secondsToTomorrow = (now = Date.now()) => {
  const next = new Date(now);
  next.setUTCHours(24, 0, 0, 0);
  return Math.max(60, Math.ceil((next.getTime() - now) / 1000));
};

/** A short hash of [id] that only means something on [day]. */
export async function hashFor(day, kind, id) {
  const data = new TextEncoder().encode(`robocore-cog|${day}|${kind}|${id}`);
  const h = new Uint8Array(await crypto.subtle.digest('SHA-256', data));
  return [...h.slice(0, 12)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Counts one question against [limits] ({all, device, address}) in [storage] (a Durable Object's storage, or anything
 * with the same get/put/deleteAll). A question over any limit is not counted. Returns {ok, why, left}: why is 'all',
 * 'device' or 'address' when a limit was reached.
 */
export async function take(storage, { day, device, address, limits }) {
  if ((await storage.get('day')) !== day) {
    await storage.deleteAll();
    await storage.put('day', day);
  }
  const k = { all: 'all', device: `d:${device}`, address: `a:${address}` };
  const got = await storage.get([k.all, k.device, k.address]);
  const n = (key) => got.get(key) ?? 0;
  if (n(k.all) >= limits.all) return { ok: false, why: 'all', left: 0 };
  if (n(k.device) >= limits.device) return { ok: false, why: 'device', left: limits.all - n(k.all) };
  if (n(k.address) >= limits.address) return { ok: false, why: 'address', left: limits.all - n(k.all) };
  await storage.put({ [k.all]: n(k.all) + 1, [k.device]: n(k.device) + 1, [k.address]: n(k.address) + 1 });
  return { ok: true, why: '', left: limits.all - n(k.all) - 1 };
}

/** The Durable Object (wrangler.jsonc: durable_objects, migrations). The Worker posts {day, device, address, limits}. */
export class CogQuota {
  constructor(state) {
    this.storage = state.storage;
  }

  async fetch(request) {
    return Response.json(await take(this.storage, await request.json()));
  }
}
