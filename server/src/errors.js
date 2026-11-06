// An error the IDE should see: answered as {"error": message} with this HTTP status. A module of its own so that
// cog.js needs nothing from compile.js, which uses Node's child_process and file system: the Cog Worker
// (cog-worker/) runs cog.js on Cloudflare, where those don't exist.
export class RequestError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}
