#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# iter-setup.sh — the external developer's whole Day 1, on the host side.
#
# READ THIS BEFORE YOU RUN IT. We mean it: you found this by piping a URL into your shell, which is the
# exact shape of a supply-chain attack. It is a couple of hundred lines, in a public repository. Look at
# them. If we ever ask you to stop looking, we have taught you the vector.
#
# WHAT IT DOES
#   1. Checks Docker. (Installs nothing — not Docker, not gh, not anything. Your host stays yours.)
#   2. KEY 1 — read:packages. Opens GitHub with the scope PRE-SELECTED, reads it from a hidden prompt,
#      pipes it into `docker login`, and PROVES it by pulling the devbox.
#   3. KEY 2 — ENGINE_SDK_TOKEN. Opens the fine-grained page, says exactly what to select, and then
#      ACTUALLY CHECKS IT: 200 = it works; 404 = it is pending an org owner's approval and can see
#      nothing. That check is the point. It is the one trap that costs people an entire afternoon,
#      because a pending token reports every repository as "not found" and never says "not yours".
#   4. Launches VS Code AS A CHILD of this process with ENGINE_SDK_TOKEN in its environment, so the
#      container inherits it and you never do the "quit VS Code and relaunch from the right shell"
#      dance — easy to get wrong, impossible to diagnose.
#
# WHAT IT NEVER DOES
#   • Writes a token to disk or to your shell history.
#   • Merges the two keys. They open two different doors and are deliberately separate (ADR-106). A
#     single broad token would work for both — which is exactly why it is forbidden. Automation may
#     ACQUIRE a credential; it may never WIDEN one.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

IMAGE="ghcr.io/itersuite/devbox:latest"
SDK_REPO="IterSuite/engine-sdk"
PKG_URL="https://github.com/settings/tokens/new?scopes=read:packages&description=Iter%20devbox%20pull"
FG_URL="https://github.com/settings/personal-access-tokens/new"

G='\033[0;32m'; R='\033[0;31m'; Y='\033[0;33m'; C='\033[0;36m'; N='\033[0m'
ok()   { printf "  ${G}✓ %s${N}\n" "$1"; }
bad()  { printf "  ${R}✗ %s${N}\n" "$1"; }
warn() { printf "  ${Y}⚠ %s${N}\n" "$1"; }
step() { printf "\n${C}▸ %s${N}\n" "$1"; }
open_url() {
  if   command -v open     >/dev/null 2>&1; then open "$1"
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$1" >/dev/null 2>&1
  else printf "  Open this in your browser:\n    %s\n" "$1"; fi
}
read_secret() { printf "  %s: " "$1"; stty -echo 2>/dev/null || true; read -r SECRET; stty echo 2>/dev/null || true; echo; }

# STATELESS ON PURPOSE — we refuse to write a token to disk, so there is nothing to resume from. But
# stateless is not oblivious: instead of REMEMBERING what is done, we MEASURE it. Try the pull first;
# if it already works, the whole credential dance is skipped. Prints 'ok' | 'denied' | 'transport' so
# the caller can tell "you lack access" from "your network dropped".
try_pull() {
  local log; log="$(mktemp)"
  local i
  for i in 1 2 3; do
    if docker pull "$IMAGE" 2>&1 | tee "$log"; then echo ok; return; fi
    grep -qiE 'unauthorized|denied|forbidden' "$log" && { echo denied; return; }
    [ "$i" -lt 3 ] && { echo; echo "  transport error — retrying ($i/3)…"; sleep 3; } >&2
  done
  echo transport
}

show_transport_help() {
  bad "The download failed — and NOT because of permissions."
  echo
  echo "    You were authorised. The connection dropped mid-layer ('EOF', 'failed to copy')."
  echo "    Layers do not come from ghcr.io — they come from pkg-containers.githubusercontent.com,"
  echo "    a DIFFERENT host, and it routes badly from some regions."
  echo
  echo "    We measured this from Brazil: it fails. Over a VPN to Europe, the identical pull works."
  echo "    Same machine, same token, same image — only the route changed."
  echo
  echo "    Prove it in one minute (the first is PUBLIC — no credential at all):"
  echo "      docker pull ghcr.io/astral-sh/uv:latest"
  echo "      docker pull python:3.11-slim"
  echo "    First fails + second works  →  it is the route. TRY A VPN. Ask for no permissions;"
  echo "                                   you already have the ones you need."
}

echo; echo "Iter Suite — host setup"; echo "Two keys, two doors. This installs nothing."; echo

# ── Docker ───────────────────────────────────────────────────────────────────
step "Docker"
command -v docker >/dev/null 2>&1 || { bad "docker not found. Install it, start it, try again."; exit 1; }
SERVER="$(docker version --format '{{.Server.Version}}' 2>/dev/null || true)"
[ -n "$SERVER" ] || { bad "Docker is installed but the daemon is not running."; exit 1; }
ok "daemon reachable (server $SERVER)"

step "Your GitHub account"
printf "  GitHub username: "; read -r USER_NAME
[ -n "$USER_NAME" ] || { bad "No username."; exit 1; }
warn "Use the account that was INVITED to IterSuite. Logging in as someone else may still succeed —"
echo  "    and would prove nothing about whether YOUR account can reach anything. A green that tests"
echo  "    the wrong identity is worse than a red."

# ══════════════ KEY 1 — the image (probe first; acquire only if needed) ══════════════
step "KEY 1 of 2 — the devbox image (read:packages)"
echo "  Checking whether you can already pull it — you may have set this up on an earlier run."
echo
case "$(try_pull)" in
  ok) ok "already authorised — KEY 1 works, skipping the login" ;;
  transport) echo; show_transport_help; exit 1 ;;
  denied)
    echo
    echo "  Not logged in yet. Opening GitHub — the scope is ALREADY selected: read:packages,"
    echo "  and nothing else. Generate it, copy it, come back."
    echo; open_url "$PKG_URL"
    read_secret "Paste the token (hidden)"; PKG_TOKEN="$SECRET"; SECRET=""
    [ -n "$PKG_TOKEN" ] || { bad "No token."; exit 1; }
    if ! printf '%s' "$PKG_TOKEN" | docker login ghcr.io -u "$USER_NAME" --password-stdin; then
      PKG_TOKEN=""; bad "docker login failed — the token probably lacks read:packages."; exit 1
    fi
    PKG_TOKEN=""; ok "logged in to ghcr.io"
    echo; echo "  Proving it. A login that cannot pull is not a login."; echo
    case "$(try_pull)" in
      ok) ok "the devbox pulled — KEY 1 works" ;;
      transport) echo; show_transport_help; exit 1 ;;
      denied)
        echo
        bad "Authenticated, but ACCESS was denied."
        echo "    Your account cannot see the package. Org membership alone does not grant it."
        echo "    Quote this to whoever invited you:"
        echo "      '$USER_NAME authenticates to ghcr.io but is DENIED on $IMAGE.'"
        exit 1 ;;
    esac ;;
esac

# ═════════════════════════════ KEY 2 — the engine ════════════════════════════
step "KEY 2 of 2 — the engine (contents:read on ONE repo)"
echo "  This one is NOT the same token, and must never be. It opens the engine artifacts — the compiled"
echo "  wheel and the frontend types — and it is scoped to exactly one repository. A key that opens one"
echo "  repo of compiled binaries costs a rotation if it leaks. A broad one costs the company. That is"
echo "  the whole reason there are two."
echo
# The common re-run: you created this token last time and were WAITING FOR APPROVAL. You do not need a
# new one — the same token flips from 404 to 200 the moment an owner approves it. So ask, rather than
# sending you to mint a duplicate you would then have to clean up.
printf "  Did you already create this token (e.g. you were waiting on approval)? [y/N]: "; read -r HAVE
case "$HAVE" in
  y|Y|yes|YES)
    echo "  Good — paste the SAME token. If it was pending, an owner approving it is all that changed." ;;
  *)
    echo
    echo "  GitHub does not let us pre-select these, so select them yourself — EXACTLY these:"
    echo
    echo "     Resource owner ......  IterSuite          (the ORG — not your username)"
    echo "     Repository access ...  Only select repositories → engine-sdk    (only that one)"
    echo "     Permissions .........  Repository permissions → Contents: Read-only"
    echo
    open_url "$FG_URL" ;;
esac
read_secret "Paste the ENGINE_SDK_TOKEN (hidden)"; SDK_TOKEN="$SECRET"; SECRET=""
[ -n "$SDK_TOKEN" ] || { bad "No token."; exit 1; }

echo; echo "  Checking it — because a token that looks fine and sees nothing is the trap that costs a day."; echo
STATUS="$(curl -s -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $SDK_TOKEN" -H 'User-Agent: iter-setup' \
  "https://api.github.com/repos/$SDK_REPO")"

case "$STATUS" in
  200) ok "the engine token is APPROVED and can read $SDK_REPO" ;;
  401) SDK_TOKEN=""; bad "GitHub rejected the token itself (401) — invalid, expired, or truncated."; exit 1 ;;
  404)
    SDK_TOKEN=""
    bad "The token is valid — and it can see NOTHING. (404)"
    echo
    echo "    This is the trap. A fine-grained token targeting an organisation is PENDING until an org"
    echo "    owner approves it, and while pending it sees ZERO repositories. GitHub masks a 403 as a"
    echo "    404 on private repos, so it reports 'not found' and never 'not yours'."
    echo
    echo "    Either:  an owner has not approved it yet        →  ask them; the request is queued"
    echo "    Or:      you were not granted read on $SDK_REPO  →  ask for it by name"
    echo
    echo "    Nothing downstream works until this returns 200. Do not debug anything else."
    exit 1 ;;
  *) SDK_TOKEN=""; bad "Unexpected response from GitHub: $STATUS"; exit 1 ;;
esac

# ═══════════════════ Hand over — VS Code inherits from THIS process ══════════
step "Opening your app"
printf "  Path to your app repo (blank = skip): "; read -r REPO

if [ -n "$REPO" ] && [ -d "$REPO" ]; then
  command -v code >/dev/null 2>&1 || { bad "VS Code's 'code' command is not on PATH."; exit 1; }
  # THE POINT OF DOING IT HERE: VS Code is launched as a CHILD of this process, so it inherits
  # ENGINE_SDK_TOKEN — which is what ${localEnv:ENGINE_SDK_TOKEN} in the devcontainer reads. No secret
  # written anywhere, and no "quit VS Code and relaunch from the right shell" dance: a dance that is
  # easy to get wrong and gives you no clue when you do — the variable is simply absent inside the
  # container, and nothing tells you why.
  ok "launching VS Code with ENGINE_SDK_TOKEN in its environment"
  ENGINE_SDK_TOKEN="$SDK_TOKEN" code "$REPO"
  SDK_TOKEN=""
  echo; echo "  In VS Code: 'Reopen in Container'. The token crosses with it."
else
  SDK_TOKEN=""
  echo
  warn "Skipped. The token is now GONE — we never write it down."
  echo  "    When you open your repo, launch VS Code from a shell that carries it:"
  echo  "        export ENGINE_SDK_TOKEN='<your token>'"
  echo  "        code <your-repo>"
  echo  "    (VS Code only ever sees the environment it was LAUNCHED with. If it is already open, quit"
  echo  "     it completely first — otherwise the variable is simply missing inside the container, and"
  echo  "     nothing will tell you why.)"
fi

echo
ok "Both keys work. Two doors, two keys — and that is on purpose."
echo
