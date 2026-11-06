#!/usr/bin/env bash
# Puts Cog on Cloudflare Workers (README.md here): signs in to Cloudflare if needed, uploads the Worker, and the first
# time asks for the Anthropic API key and sets a school key. Nothing secret is written to disk: the API key goes from
# the hidden prompt straight to Cloudflare.
#
# Usage: bash cog-worker/deploy.sh
#   WRANGLER=/path/to/wrangler   a wrangler already on this computer (otherwise `wrangler` on PATH, then npx)
#   COG_SCHOOL_KEY=…             the school key to set the first time (otherwise a new random one)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
if [ -z "${WRANGLER:-}" ]; then
  WRANGLER=$(command -v wrangler || true)
  [ -n "$WRANGLER" ] || WRANGLER="npx --yes wrangler@4"
fi
export WRANGLER_SEND_METRICS=false

# The Worker is bundled with server/src/cog.js and the Anthropic SDK from server/node_modules.
[ -d "$HERE/../server/node_modules/@anthropic-ai/sdk" ] || (cd "$HERE/../server" && npm ci --no-audit --no-fund)

cd "$HERE"
$WRANGLER whoami 2>/dev/null | grep -q "You are logged in" || $WRANGLER login
$WRANGLER deploy

if ! $WRANGLER secret list 2>/dev/null | grep -q '"ANTHROPIC_API_KEY"'; then
  echo
  echo "First time: paste your Anthropic API key when asked (it won't show)."
  $WRANGLER secret put ANTHROPIC_API_KEY
  KEY=${COG_SCHOOL_KEY:-$(openssl rand -hex 16)}
  printf '%s' "$KEY" | $WRANGLER secret put COG_KEYS
  echo
  echo "School key, for RoboCore Settings > Cog > School key:  $KEY"
  echo "Keep it. To give each school its own, set all of them, comma-separated: wrangler secret put COG_KEYS"
fi
echo
echo "In RoboCore Settings > Real board and upload > Compile server, use the workers.dev address above, then Test Cog."
