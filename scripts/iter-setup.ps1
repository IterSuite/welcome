<#
    iter-setup.ps1 — the external developer's whole Day 1, on the host side.

    READ THIS BEFORE YOU RUN IT. We mean it: you found this by piping a URL into your shell, which is
    the exact shape of a supply-chain attack. It is a couple of hundred lines, in a public repository.
    Look at them. If we ever ask you to stop looking, we have taught you the vector.

    WHAT IT DOES
      1. Checks Docker. (Installs nothing — not Docker, not gh, not anything. Your host stays yours.)
      2. KEY 1 — read:packages. Opens GitHub with the scope PRE-SELECTED, reads it from a hidden
         prompt, pipes it into `docker login`, and PROVES it by pulling the devbox.
      3. KEY 2 — ENGINE_SDK_TOKEN. Opens the fine-grained token page, tells you exactly what to
         select, and then ACTUALLY CHECKS IT against the API: 200 = it works; 404 = it is pending an
         org owner's approval and can see nothing. That check is the point. It is the single trap that
         costs people an entire afternoon, because a pending token reports every repository as
         "not found" and never once says "not yours".
      4. Launches VS Code AS A CHILD of this process, with ENGINE_SDK_TOKEN in its environment.
         So the container inherits it, and you never do the "quit VS Code, relaunch from the right
         shell" dance — which is easy to get wrong and impossible to diagnose.

    WHAT IT NEVER DOES
      • Writes a token to disk, to your registry (no `setx`), or to your shell history.
      • Merges the two keys. They open two different doors and are deliberately separate.
        A single broad token would work for both — and that is exactly why it is forbidden. Automation
        may ACQUIRE a credential; it may never WIDEN one.
#>

$ErrorActionPreference = 'Stop'

$IMAGE       = 'ghcr.io/itersuite/devbox:latest'
$SDK_REPO    = 'IterSuite/engine-sdk'
$PKG_URL     = 'https://github.com/settings/tokens/new?scopes=read:packages&description=Iter%20devbox%20pull'
$FG_URL      = 'https://github.com/settings/personal-access-tokens/new'

function Say($m)  { Write-Host $m }
function Ok($m)   { Write-Host "  ✓ $m" -ForegroundColor Green }
function Bad($m)  { Write-Host "  ✗ $m" -ForegroundColor Red }
function Warn($m) { Write-Host "  ⚠ $m" -ForegroundColor Yellow }
function Step($m) { Write-Host "`n▸ $m" -ForegroundColor Cyan }

function Read-Secret($prompt) {
    $s = Read-Host "  $prompt" -AsSecureString
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try   { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

# This script is STATELESS on purpose — we refuse to write a token to disk, so there is nothing to
# resume from. But stateless is not the same as oblivious: instead of REMEMBERING what is done, it
# MEASURES it. Try the pull first; if it already works, the whole credential dance is skipped. Returns
# 'ok' | 'denied' | 'transport' so the caller can tell "you lack access" from "your network dropped".
function Invoke-Pull {
    $log = [IO.Path]::GetTempFileName()
    for ($i = 1; $i -le 3; $i++) {
        docker pull $IMAGE 2>&1 | Tee-Object -FilePath $log
        if ($LASTEXITCODE -eq 0) { return 'ok' }
        if ((Get-Content $log -Raw) -imatch 'unauthorized|denied|forbidden') { return 'denied' }
        if ($i -lt 3) { Say ""; Say "  transport error — retrying ($i/3)…"; Start-Sleep 3 }
    }
    return 'transport'
}

function Show-TransportHelp {
    Bad "The download failed — and NOT because of permissions."
    Say ""
    Say "    You were authorised. The connection dropped mid-layer ('EOF', 'failed to copy')."
    Say "    Layers do not come from ghcr.io — they come from pkg-containers.githubusercontent.com,"
    Say "    a DIFFERENT host, and it routes badly from some regions."
    Say ""
    Say "    We measured this from Brazil: it fails. Over a VPN to Europe, the identical pull works."
    Say "    Same machine, same token, same image — only the route changed."
    Say ""
    Say "    Prove it in one minute (the first is PUBLIC — no credential at all):"
    Say "      docker pull ghcr.io/astral-sh/uv:latest"
    Say "      docker pull python:3.11-slim"
    Say "    First fails + second works  →  it is the route. TRY A VPN. Ask for no permissions;"
    Say "                                   you already have the ones you need."
}

Say ""
Say "Iter Suite — host setup"
Say "Two keys, two doors. This installs nothing."
Say ""

# ── Docker ───────────────────────────────────────────────────────────────────
Step "Docker"
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Bad "docker not found. Install Docker Desktop, start it, and run this again."
    exit 1
}
$server = docker version --format '{{.Server.Version}}' 2>$null
if (-not $server) { Bad "Docker is installed but the daemon is not running. Start it and try again."; exit 1 }
Ok "daemon reachable (server $server)"

Step "Your GitHub account"
$user = Read-Host "  GitHub username"
if (-not $user) { Bad "No username."; exit 1 }
Warn "Use the account that was INVITED to IterSuite. Logging in as someone else may still succeed —"
Say  "    and would prove nothing about whether YOUR account can reach anything. A green that tests"
Say  "    the wrong identity is worse than a red."

# ═══════════════════════════════════════════════════════════════════════════════
#  KEY 1 — the image  (probe first; only acquire a credential if the pull needs one)
# ═══════════════════════════════════════════════════════════════════════════════
Step "KEY 1 of 2 — the devbox image (read:packages)"
Say "  Checking whether you can already pull it — you may have set this up on an earlier run."
Say ""

switch (Invoke-Pull) {
    'ok'        { Ok "already authorised — KEY 1 works, skipping the login" }
    'transport' { Say ""; Show-TransportHelp; exit 1 }
    'denied'    {
        Say ""
        Say "  Not logged in yet. Opening GitHub — the scope is ALREADY selected: read:packages,"
        Say "  and nothing else. Generate it, copy it, come back."
        Say ""
        Start-Process $PKG_URL

        $pkgToken = Read-Secret "Paste the token (hidden)"
        if (-not $pkgToken) { Bad "No token."; exit 1 }
        $pkgToken | docker login ghcr.io -u $user --password-stdin
        $code = $LASTEXITCODE
        $pkgToken = $null; [GC]::Collect()
        if ($code -ne 0) { Bad "docker login failed — the token probably lacks read:packages."; exit 1 }
        Ok "logged in to ghcr.io"

        Say ""; Say "  Proving it. A login that cannot pull is not a login."; Say ""
        switch (Invoke-Pull) {
            'ok'        { Ok "the devbox pulled — KEY 1 works" }
            'transport' { Say ""; Show-TransportHelp; exit 1 }
            'denied'    {
                Say ""
                Bad "Authenticated, but ACCESS was denied."
                Say "    Your account cannot see the package. Org membership alone does not grant it."
                Say "    Quote this to whoever invited you:"
                Say "      '$user authenticates to ghcr.io but is DENIED on $IMAGE.'"
                exit 1
            }
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
#  KEY 2 — the engine
# ═══════════════════════════════════════════════════════════════════════════════
Step "KEY 2 of 2 — the engine (contents:read on ONE repo)"
Say "  This one is NOT the same token, and must never be. It opens the engine artifacts — the"
Say "  compiled wheel and the frontend types — and it is scoped to exactly one repository."
Say "  A key that opens one repo of compiled binaries costs a rotation if it leaks. A broad one"
Say "  costs the company. That is the whole reason there are two."
Say ""
# The common re-run: you created this token last time and were WAITING FOR APPROVAL. You do not need a
# new one — the same token flips from 404 to 200 the moment an owner approves it. So ask, and do not send
# you back to the browser to mint a duplicate you will then have to clean up.
$have = Read-Host "  Did you already create this token (e.g. you were waiting on approval)? [y/N]"
if ($have -notmatch '^(y|yes)$') {
    Say ""
    Say "  GitHub does not let us pre-select these, so select them yourself — EXACTLY these:"
    Say ""
    Say "     Resource owner ......  IterSuite          (the ORG — not your username)" -ForegroundColor White
    Say "     Repository access ...  Only select repositories → engine-sdk    (only that one)"
    Say "     Permissions .........  Repository permissions → Contents: Read-only"
    Say ""
    Start-Process $FG_URL
} else {
    Say "  Good — paste the SAME token. If it was pending, an owner approving it is all that changed."
}

$sdkToken = Read-Secret "Paste the ENGINE_SDK_TOKEN (hidden)"
if (-not $sdkToken) { Bad "No token."; exit 1 }

Say ""
Say "  Checking it — because a token that looks fine and sees nothing is the trap that costs a day."
Say ""

$status = 0
try {
    $r = Invoke-WebRequest -Uri "https://api.github.com/repos/$SDK_REPO" -Headers @{
        Authorization = "Bearer $sdkToken"; 'User-Agent' = 'iter-setup'
    } -UseBasicParsing -SkipHttpErrorCheck
    $status = $r.StatusCode
} catch { $status = $_.Exception.Response.StatusCode.value__ }

switch ($status) {
    200 {
        Ok "the engine token is APPROVED and can read $SDK_REPO"
    }
    401 {
        Bad "GitHub rejected the token itself (401)."
        Say "    It is invalid, expired, or was pasted incompletely. Generate a new one."
        exit 1
    }
    404 {
        Bad "The token is valid — and it can see NOTHING. (404)"
        Say ""
        Say "    This is the trap. A fine-grained token targeting an organisation is PENDING until an"
        Say "    org owner approves it, and while pending it sees ZERO repositories. GitHub masks a 403"
        Say "    as a 404 on private repos, so it reports 'not found' and never 'not yours'."
        Say ""
        Say "    Either:  an owner has not approved it yet   →  ask them; the request is already queued"
        Say "    Or:      you were not granted read on $SDK_REPO  →  ask for it by name"
        Say ""
        Say "    Nothing downstream works until this returns 200. Do not go debugging anything else."
        exit 1
    }
    default {
        Bad "Unexpected response from GitHub: $status"
        exit 1
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Hand over — VS Code inherits the environment from THIS process
# ═══════════════════════════════════════════════════════════════════════════════
Step "Opening your app"

$repo = Read-Host "  Path to your app repo (blank = skip and just print what to do)"

if ($repo -and (Test-Path $repo)) {
    if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
        Bad "VS Code's 'code' command is not on PATH."
        Say "    In VS Code: Ctrl+Shift+P → 'Shell Command: Install code command in PATH'."
        exit 1
    }
    # THE POINT OF DOING IT HERE: VS Code is launched as a CHILD of this process, so it inherits
    # ENGINE_SDK_TOKEN from our environment — which is what ${localEnv:ENGINE_SDK_TOKEN} in the
    # devcontainer reads. No `setx` (which would write your secret into the Windows registry forever),
    # no "quit VS Code and relaunch it from the right shell" — a dance that is easy to get wrong and
    # gives you no clue when you do: the variable is simply missing inside the container, and nothing
    # says why.
    $env:ENGINE_SDK_TOKEN = $sdkToken
    Ok "launching VS Code with ENGINE_SDK_TOKEN in its environment"
    code $repo
    $sdkToken = $null; [GC]::Collect()
    Say ""
    Say "  In VS Code: 'Reopen in Container'. The token crosses with it."
} else {
    $sdkToken = $null; [GC]::Collect()
    Say ""
    Warn "Skipped. Note the token is now GONE — we never write it down."
    Say  "    When you open your repo, launch VS Code from a shell that has the variable:"
    Say  "        `$env:ENGINE_SDK_TOKEN = '<your token>'"
    Say  "        code <your-repo>"
    Say  "    (VS Code only ever sees the environment it was LAUNCHED with. If it is already open,"
    Say  "     quit it completely first — otherwise the variable will simply be missing inside the"
    Say  "     container, and nothing will tell you why.)"
}

Say ""
Ok "Both keys work. Two doors, two keys — and that is on purpose."
Say ""
