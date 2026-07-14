#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# iter-login.sh — give Docker the one credential it needs to pull the Iter devbox.
#
# READ THIS BEFORE YOU RUN IT. We mean that literally: you found this script by piping a URL into your
# shell, which is the exact shape of a supply-chain attack. It is a hundred lines. Look at them. If we
# ever ask you to stop looking, we have taught you the vector.
#
# WHAT IT DOES
#   1. Checks you have a Docker daemon. (It does not install one — that is your call, not ours.)
#   2. Opens your browser at GitHub's token page with the scope `read:packages` PRE-SELECTED.
#   3. Reads the token from a HIDDEN prompt and pipes it straight into `docker login`.
#   4. PROVES it worked by actually pulling the image.
#
# WHAT IT DOES NOT DO
#   • It installs NOTHING. Your host stays yours.
#   • It never writes the token to disk, to a file, or to your shell history.
#   • It never touches ENGINE_SDK_TOKEN — the OTHER credential, the one that IS the IP boundary.
#     Those two keys are separate on purpose (ADR-106). If a tool ever offers to make them one, that
#     tool is wrong, even when it works. Especially when it works.
#
# WHY NOT `gh auth login`, which would be prettier?
#   Because gh's OAuth token carries scope `repo` — read AND WRITE on every repository you can reach.
#   We only need to pull an image. The narrowest key that opens the door is the one you should hold,
#   and a browser flow that hands you a wider one is not a bargain.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

IMAGE="ghcr.io/itersuite/devbox:latest"
TOKEN_URL="https://github.com/settings/tokens/new?scopes=read:packages&description=Iter%20devbox%20pull"

G='\033[0;32m'; R='\033[0;31m'; C='\033[0;36m'; N='\033[0m'
ok()   { printf "  ${G}✓ %s${N}\n" "$1"; }
bad()  { printf "  ${R}✗ %s${N}\n" "$1"; }
step() { printf "\n${C}▸ %s${N}\n" "$1"; }

open_url() {
  if   command -v open        >/dev/null 2>&1; then open "$1"
  elif command -v xdg-open    >/dev/null 2>&1; then xdg-open "$1" >/dev/null 2>&1
  else printf "  Open this in your browser:\n    %s\n" "$1"; fi
}

echo
echo "Iter Suite — the image credential"
echo "This gives Docker permission to pull the devbox. It installs nothing."
echo

# ── 1. Docker ────────────────────────────────────────────────────────────────
step "Checking Docker"
command -v docker >/dev/null 2>&1 || {
  bad "docker not found."
  echo "    Install Docker, start it, and run this again."
  exit 1
}
SERVER="$(docker version --format '{{.Server.Version}}' 2>/dev/null || true)"
[ -n "$SERVER" ] || {
  bad "Docker is installed but the daemon is not running."
  echo "    Start it, wait until it is up, and run this again."
  exit 1
}
ok "Docker daemon reachable (server $SERVER)"

# ── 2. Who are you on GitHub? ────────────────────────────────────────────────
step "Your GitHub account"
printf "  GitHub username: "
read -r USER_NAME
[ -n "$USER_NAME" ] || { bad "No username. Nothing to do."; exit 1; }

echo
echo "  ⚠  Use the account that was INVITED to the IterSuite organization."
echo "     If you log in as someone else, the pull may still succeed — and you will have proven"
echo "     nothing about whether YOUR account can reach the image. A green that tests the wrong"
echo "     identity is worse than a red."
echo

# ── 3. The token ─────────────────────────────────────────────────────────────
step "Creating a token (scope: read:packages, and nothing else)"
echo "  Opening your browser. The scope is already selected — do not add any others."
echo "  Set an expiry you are comfortable with, click 'Generate token', and copy it."
echo
open_url "$TOKEN_URL"

printf "  Paste the token (it will not be shown): "
stty -echo 2>/dev/null || true
read -r TOKEN
stty echo 2>/dev/null || true
echo
[ -n "$TOKEN" ] || { bad "No token pasted. Nothing to do."; exit 1; }

# ── 4. Hand it to Docker, and never let it touch the disk ───────────────────
step "Logging in to ghcr.io"
if ! printf '%s' "$TOKEN" | docker login ghcr.io -u "$USER_NAME" --password-stdin; then
  TOKEN=""
  bad "docker login failed."
  echo "    The token is probably missing the read:packages scope. Generate a new one from the"
  echo "    link above — the scope is pre-selected there — and try again."
  exit 1
fi
TOKEN=""
ok "Logged in to ghcr.io"

# ── 5. PROVE it. A login that cannot pull is not a login. ───────────────────
step "Proving it — pulling the devbox image"
echo "  (This is the only step that matters. Everything above is a claim; this is the evidence.)"
echo
if ! docker pull "$IMAGE"; then
  echo
  bad "Authenticated, but the pull was DENIED."
  echo
  echo "  This is not a token problem — you logged in. It means your account does not have"
  echo "  access to the package itself."
  echo
  echo "  Tell whoever invited you, and quote this exactly:"
  echo
  echo "      '$USER_NAME is authenticated to ghcr.io but denied on $IMAGE.'"
  echo "      'The account needs read access to the devbox package, not just org membership.'"
  echo
  exit 1
fi

echo
ok "The devbox image pulled. Your first key works."
echo
echo "Next:"
echo "  1. Create your ENGINE_SDK_TOKEN — the SECOND key. It is a different door, on purpose."
echo "     See the README, section 2.2. It needs an org owner's approval, so start it now:"
echo "     until it is approved it sees zero repositories and everything reads as 'not found'."
echo
echo "  2. Clone your app repo and open it in VS Code → 'Reopen in Container'."
echo
