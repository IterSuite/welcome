<#
    iter-login.ps1 — give Docker the one credential it needs to pull the Iter devbox.

    READ THIS BEFORE YOU RUN IT. We mean that literally: you found this script by piping a URL into
    your shell, which is the exact shape of a supply-chain attack. It is a hundred lines. Look at them.
    If we ever ask you to stop looking, we have taught you the vector.

    WHAT IT DOES
      1. Checks you have a Docker daemon. (It does not install one — that is your call, not ours.)
      2. Opens your browser at GitHub's token page with the scope `read:packages` PRE-SELECTED.
      3. Reads the token from a HIDDEN prompt and pipes it straight into `docker login`.
      4. PROVES it worked by actually pulling the image.

    WHAT IT DOES NOT DO
      • It installs NOTHING. Not gh, not winget packages, nothing. Your host stays yours.
      • It never writes the token to disk, to a file, or to your shell history.
      • It never touches ENGINE_SDK_TOKEN — the OTHER credential, the one that is the IP boundary.
        Those two keys are separate on purpose (ADR-106). If a tool ever offers to make them one,
        that tool is wrong, even when it works. Especially when it works.

    WHY NOT `gh auth login`, which would be prettier?
      Because gh's OAuth token carries scope `repo` — read AND WRITE on every repository you can reach.
      We only need to pull an image. The narrowest key that opens the door is the one you should hold,
      and a browser flow that hands you a wider one is not a bargain.
#>

$ErrorActionPreference = 'Stop'

$IMAGE = 'ghcr.io/itersuite/devbox:latest'
$TOKEN_URL = 'https://github.com/settings/tokens/new?scopes=read:packages&description=Iter%20devbox%20pull'

function Say($msg)  { Write-Host $msg }
function Ok($msg)   { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Bad($msg)  { Write-Host "  ✗ $msg" -ForegroundColor Red }
function Step($msg) { Write-Host "`n▸ $msg" -ForegroundColor Cyan }

Say ""
Say "Iter Suite — the image credential"
Say "This gives Docker permission to pull the devbox. It installs nothing."
Say ""

# ── 1. Docker ────────────────────────────────────────────────────────────────
Step "Checking Docker"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Bad "docker not found."
    Say  "    Install Docker Desktop, start it, and run this again."
    Say  "    https://www.docker.com/products/docker-desktop/"
    exit 1
}

try {
    $server = docker version --format '{{.Server.Version}}' 2>$null
    if (-not $server) { throw }
    Ok "Docker daemon reachable (server $server)"
} catch {
    Bad "Docker is installed but the daemon is not running."
    Say  "    Start Docker Desktop, wait for it to say 'Engine running', and run this again."
    exit 1
}

# ── 2. Who are you on GitHub? ────────────────────────────────────────────────
Step "Your GitHub account"

$user = Read-Host "  GitHub username"
if ([string]::IsNullOrWhiteSpace($user)) { Bad "No username. Nothing to do."; exit 1 }

Say ""
Say "  ⚠  Use the account that was INVITED to the IterSuite organization."
Say "     If you log in as someone else, the pull may still succeed — and you will have proven"
Say "     nothing about whether YOUR account can reach the image. A green that tests the wrong"
Say "     identity is worse than a red."
Say ""

# ── 3. The token ─────────────────────────────────────────────────────────────
Step "Creating a token (scope: read:packages, and nothing else)"

Say  "  Opening your browser. The scope is already selected — do not add any others."
Say  "  Set an expiry you are comfortable with, click 'Generate token', and copy it."
Say ""
Start-Process $TOKEN_URL

$secure = Read-Host "  Paste the token (it will not be shown)" -AsSecureString
$bstr   = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$token  = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

if ([string]::IsNullOrWhiteSpace($token)) { Bad "No token pasted. Nothing to do."; exit 1 }

# ── 4. Hand it to Docker, and never let it touch the disk ───────────────────
Step "Logging in to ghcr.io"

$token | docker login ghcr.io -u $user --password-stdin
$loginCode = $LASTEXITCODE
$token = $null
[GC]::Collect()

if ($loginCode -ne 0) {
    Bad "docker login failed."
    Say  "    The token is probably missing the read:packages scope. Generate a new one from the"
    Say  "    link above — the scope is pre-selected there — and try again."
    exit 1
}
Ok "Logged in to ghcr.io"

# ── 5. PROVE it. A login that cannot pull is not a login. ───────────────────
Step "Proving it — pulling the devbox image"

Say "  (This is the only step that matters. Everything above is a claim; this is the evidence.)"
Say ""

# The image is ~25 layers and a few GB. A truncated blob download is COMMON and has nothing to do with
# your permissions — so we retry before we blame anything.
#
# The first version of this script did not. It treated ANY non-zero exit as "access denied" and printed
# a confident, specific, WRONG diagnosis — it told a developer whose pull had authenticated fine,
# fetched the manifest, and pulled 25 layers before hitting `EOF` on a blob, that his account lacked
# access to the package. He would have gone and asked for permissions he already had, while the real
# problem — a dropped connection — sat untouched.
#
# A wrong diagnosis is worse than no diagnosis. It does not merely fail to help; it sends you somewhere
# else, confidently, with our name on it. So: read the error before naming a cause.
$attempts = 3
$pullOk   = $false
$log      = ''
$logFile  = [IO.Path]::GetTempFileName()

for ($i = 1; $i -le $attempts; $i++) {
    # Tee to a FILE, not to a variable: `| Out-String` swallowed the output entirely, so a multi-GB,
    # 25-layer pull looked frozen and — worse — the real error never reached the screen. I told this
    # developer to read the error, and then hid it from him. The evidence must stream while it is
    # captured; a diagnostic that eats its own evidence is not a diagnostic.
    docker pull $IMAGE 2>&1 | Tee-Object -FilePath $logFile
    $code = $LASTEXITCODE
    $log  = Get-Content $logFile -Raw

    if ($code -eq 0) { $pullOk = $true; break }

    if ($log -imatch 'unauthorized|denied|forbidden|authentication required') {
        break    # a permission problem does not get better by trying again
    }
    if ($i -lt $attempts) {
        Say ""
        Say "  transport error — retrying ($i/$attempts)…"
        Start-Sleep -Seconds 3
    }
}

if (-not $pullOk) {
    Say ""
    if ($log -imatch 'unauthorized|denied|forbidden|authentication required') {
        Bad "Authenticated, but ACCESS was denied."
        Say ""
        Say "  This is not a token problem — the login succeeded. Your account does not have access"
        Say "  to the package itself. Org membership alone does not grant it."
        Say ""
        Say "  Tell whoever invited you, and quote this exactly:"
        Say ""
        Say "      '$user is authenticated to ghcr.io but DENIED on $IMAGE.'"
        Say "      'The account needs read access to the devbox package, not just org membership.'"
    } else {
        Bad "The download failed — but NOT because of permissions."
        Say ""
        Say "  You were authorised: the login succeeded and the registry served you the manifest."
        Say "  The connection then dropped while fetching a layer ('EOF', 'failed to copy')."
        Say ""
        Say "  ⚠ Note WHERE it dropped. Layers do not come from ghcr.io — they come from"
        Say "    pkg-containers.githubusercontent.com, a DIFFERENT host. A corporate proxy, VPN or DLP"
        Say "    appliance very often allows the first and mangles the second, because one carries JSON"
        Say "    and the other carries gigabytes of binary. Authentication passing therefore tells you"
        Say "    nothing about whether the download will."
        Say ""
        Say "  This is the most likely cause on a managed corporate machine, and it is not something"
        Say "  more permissions can fix."
        Say ""
        Say "  Try, in order:"
        Say "    1. docker pull $IMAGE          (transient drops are common; it often just works)"
        Say "    2. off the corporate network / VPN — if it works there, you have your answer"
        Say "    3. ask IT to allow pkg-containers.githubusercontent.com"
        Say ""
        Say "  Do NOT go asking for more permissions. You already have the ones you need — this run"
        Say "  proved it: you authenticated, and the registry answered."
    }
    Say ""
    exit 1
}

Say ""
Ok "The devbox image pulled. Your first key works."
Say ""
Say "Next:"
Say "  1. Create your ENGINE_SDK_TOKEN — the SECOND key. It is a different door, on purpose."
Say "     See the README, section 2.2. It needs an org owner's approval, so start it now:"
Say "     until it is approved it sees zero repositories and everything reads as 'not found'."
Say ""
Say "  2. Clone your app repo and open it in VS Code → 'Reopen in Container'."
Say ""
