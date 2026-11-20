#!/usr/bin/env bash
# Puts Cog on Cloudflare Workers (README.md here): signs in to Cloudflare if needed, uploads the Worker, and the first
# time asks for the AI's key and sets a school key. Nothing secret is written to disk: a key goes from the hidden
# prompt straight to Cloudflare.
#
# Usage: bash cog-worker/deploy.sh [claude|cloudflare]
#   claude (the default)  Cog answers through Claude: asks for an Anthropic API key (paid per question)
#   cloudflare            Cog answers through Cloudflare's own AI (Workers AI): free up to a daily allowance, no card
#                         and no Anthropic key; asks for a free Workers AI API token
#
#   WRANGLER=/path/to/wrangler   a wrangler already on this computer (otherwise `wrangler` on PATH, then npx)
#   COG_SCHOOL_KEY=…             the school key to set the first time (otherwise a new random one)
#   CLOUDFLARE_ACCOUNT_ID=…      which Cloudflare account, when you have more than one
set -euo pipefail

MODE=${1:-claude}
case "$MODE" in
  claude) ENVARG="--env=" ;; # the top level of wrangler.jsonc, said out loud (wrangler warns otherwise)
  cloudflare) ENVARG="--env cloudflare" ;;
  *) echo "Usage: bash cog-worker/deploy.sh [claude|cloudflare]" >&2; exit 2 ;;
esac

HERE=$(cd "$(dirname "$0")" && pwd)
if [ -z "${WRANGLER:-}" ]; then
  WRANGLER=$(command -v wrangler || true)
  [ -n "$WRANGLER" ] || WRANGLER="npx --yes wrangler@4"
fi
export WRANGLER_SEND_METRICS=false

# The Worker is bundled with server/src/cog.js and the Anthropic SDK from server/node_modules.
[ -d "$HERE/../server/node_modules/@anthropic-ai/sdk" ] || (cd "$HERE/../server" && npm ci --no-audit --no-fund)

cd "$HERE"
WHO=$($WRANGLER whoami 2>/dev/null || true)
if ! grep -q "You are logged in" <<<"$WHO"; then
  $WRANGLER login
  WHO=$($WRANGLER whoami 2>/dev/null || true)
fi

if [ "$MODE" = cloudflare ]; then
  # The AI's address has the account in it, and the upload must go to that same account.
  ACCOUNT=${CLOUDFLARE_ACCOUNT_ID:-}
  if [ -z "$ACCOUNT" ]; then
    IDS=$(grep -oE '[0-9a-f]{32}' <<<"$WHO" | sort -u || true)
    if [ "$(grep -c . <<<"$IDS" || true)" = 1 ]; then
      ACCOUNT=$IDS
    else
      echo "Your Cloudflare login sees more than one account:"
      grep -E '[0-9a-f]{32}' <<<"$WHO" || true
      echo "Which one should Cog live in? Copy its Account ID (the 32 letters and digits) from above, paste it here"
      echo "and press Enter. (To skip this question next time, start with CLOUDFLARE_ACCOUNT_ID=<that ID> in front.)"
      read -r ACCOUNT
      ACCOUNT=$(tr -d '[:space:]' <<<"$ACCOUNT")
    fi
  fi
  if ! grep -qE '^[0-9a-f]{32}$' <<<"$ACCOUNT"; then
    echo "That is not an Account ID (32 letters and digits). Nothing was changed." >&2
    exit 1
  fi
  export CLOUDFLARE_ACCOUNT_ID=$ACCOUNT
fi

# shellcheck disable=SC2086  # $WRANGLER and $ENVARG are words on purpose
$WRANGLER deploy $ENVARG

# A slow or dropped connection is tried again: a key that was pasted is not asked for twice, and a setting that could
# not be read is never taken for "not set" (that would swap a working school key for a new one).
WAIT=${COG_DEPLOY_RETRY_SECONDS:-10}
gave_up() {
  echo "Cloudflare could not be reached ($1). Check the internet, then run this again: it carries on where it stopped." >&2
  exit 1
}

# The names of the settings Cloudflare already holds for this Worker (never their values).
SECRETS=""
# shellcheck disable=SC2086
load_secrets() {
  local try
  for try in 1 2 3; do
    if SECRETS=$($WRANGLER secret list $ENVARG 2>/dev/null) && grep -q '^\[' <<<"$SECRETS"; then return 0; fi
    [ "$try" = 3 ] || sleep "$WAIT"
  done
  gave_up "reading the Worker's settings"
}
has_secret() { grep -q "\"$1\"" <<<"$SECRETS"; }

# send_secret NAME VALUE
# shellcheck disable=SC2086
send_secret() {
  local try
  for try in 1 2 3; do
    if printf '%s' "$2" | $WRANGLER secret put "$1" $ENVARG; then return 0; fi
    [ "$try" = 3 ] || { echo "That did not reach Cloudflare. Trying again in $WAIT seconds…"; sleep "$WAIT"; }
  done
  gave_up "saving $1"
}

# ask_secret NAME QUESTION: a hidden prompt, then send_secret.
ask_secret() {
  local value
  read -rsp "$2 (it won't show), then press Enter: " value
  echo
  value=$(tr -d '[:space:]' <<<"$value")
  if [ -z "$value" ]; then
    echo "Nothing was pasted. Run this again when you have it." >&2
    exit 1
  fi
  send_secret "$1" "$value"
}

load_secrets
if [ "$MODE" = cloudflare ]; then
  send_secret COG_BASE_URL "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT/ai/v1"
  if ! has_secret COG_API_KEY; then
    echo
    echo "First time: Cog needs a free Workers AI API token."
    echo "  1. Open https://dash.cloudflare.com/$ACCOUNT/ai/workers-ai (the Workers AI page of this account)."
    echo "  2. Select Use REST API, then Create a Workers AI API Token, then Create API Token."
    echo "  3. Copy the token."
    ask_secret COG_API_KEY "Paste the token here"
  fi
elif ! has_secret ANTHROPIC_API_KEY; then
  echo
  echo "First time: Cog needs your Anthropic API key."
  ask_secret ANTHROPIC_API_KEY "Paste the key here"
fi

if ! has_secret COG_KEYS; then
  KEY=${COG_SCHOOL_KEY:-$(openssl rand -hex 16)}
  send_secret COG_KEYS "$KEY"
  echo
  echo "School key, for RoboCore Settings > Cog > School key:  $KEY"
  echo "Keep it. To give each school its own, set all of them, comma-separated: wrangler secret put COG_KEYS $ENVARG"
fi
echo
echo "In RoboCore Settings > Real board and upload > Compile server, use the workers.dev address above, then Test Cog."
if [ "$MODE" = cloudflare ]; then
  echo "Cloudflare answers about 50 questions a day for free with this model; after that Cog rests until 00:00 UTC."
  echo "Nothing is billed on Cloudflare's free plan. wrangler.jsonc (env.cloudflare) says how to allow more questions."
fi
