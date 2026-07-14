<!-- doc-language:waived -->
# AGENTS.md — get your human onto the platform

You are an AI coding agent running on a developer's **own machine** — their laptop, their shell, their
Docker. They are about to start building on **Iter Suite**, and nothing exists yet: no container, no
tools, no credentials.

**Your job is everything that happens BEFORE the dev container exists.** The moment it is running, your
job here is done: their app repo carries its own `AGENTS.md`, written for an agent *inside* the
container, and that one takes over.

> ## The one rule that decides everything you do here
>
> **You are OUTSIDE the container. The container's runbook cannot help you, and you cannot do its job.**
>
> This line is not pedantry — it is the bug that produced this file. The credential instructions used to
> live *inside* the container's `AGENTS.md`. An agent could only read them **after** the container
> existed — which required the credential it was reading about. It dutifully offered to run
> `docker login` from inside the very container that login had already paid for.
>
> If a step happens on the host, it is documented here. If it happens inside, it is documented there.
> **Nothing is written twice**, and nothing is written on the wrong side of the wall.

---

## What you must NOT do

**Do not install things on their machine unless they ask.** This developer may be on a locked corporate
laptop, or may simply keep a clean host on purpose — a preference you should respect without being told.
Everything below works with **Docker Desktop and a browser**. Nothing else is required.

**Do not create, request, or handle a broad token.** There are exactly two credentials (below) and they
are deliberately separate. If you find yourself thinking *"we already have a token that would work for
this too"* — **stop.** That thought is the failure mode this platform is designed against, and it is
written up as ADR-106. A token that works for two planes is not convenient; it is the boundary, gone.

---

## Step 1 — Find out what is actually true

Do not assume. Measure, then act on what you find.

```bash
docker version --format 'server {{.Server.Version}}'   # is there a daemon at all?
docker login --help >/dev/null 2>&1 && echo "docker cli: ok"
gh auth status 2>&1 | head -3                          # they may not have gh. That is FINE.
echo "${ENGINE_SDK_TOKEN:+ENGINE_SDK_TOKEN: present}"  # empty output = not set
```

**No Docker daemon** → stop. They need Docker Desktop. Do not try to work around it; there is nothing
downstream that works without it.

**No `gh`** → fine, and not a problem to solve. It is not required for any step here.

---

## Step 2 — The image credential (`read:packages`)

The devbox image is **private**. Without this, `Reopen in Container` dies at the pull with
`Error response from daemon: error from registry: unauthorized` and **nothing else can start**.

Run the bootstrap script — or do it by hand, which is three lines and no download:

1. Open `https://github.com/settings/tokens/new?scopes=read:packages&description=Iter+devbox`
   *(the scope is pre-selected: `read:packages`, and only that)*
2. Generate, copy.
3. `docker login ghcr.io -u <their-github-username>` → paste at the **hidden** password prompt.

**Never put the token on the command line** (`-p <token>` writes it into their shell history, forever).
Use the prompt, or `--password-stdin`.

**Verify it, do not assume it:**

```bash
docker pull ghcr.io/itersuite/devbox:latest && echo "image credential: WORKS"
```

---

## Step 3 — The engine credential (`ENGINE_SDK_TOKEN`)

This one **you cannot automate, and must not try to.** It is a grant that a human with authority makes,
by name, to this developer — and can revoke by name.

Walk them through it:

- **Settings → Developer settings → Personal access tokens → Fine-grained**
- **Resource owner:** `IterSuite` *(the organization — not their own username. If the org is not in the
  dropdown, they are not a member yet: that is the blocker, go fix that first.)*
- **Repository access:** *Only select repositories* → **`engine-sdk`** — **only** that one
- **Permissions:** *Repository permissions* → **Contents: Read-only**

> ### Then it sits `Pending`, and this is the trap that costs the most time.
>
> A fine-grained token targeting an organization is **not active until an org owner approves it**. Until
> then it can see **zero repositories** — and GitHub masks a 403 as a **404** on private repos, so every
> failure reads *"not found"*, never *"not yours"*.
>
> **If anything 404s later, check the approval before you debug anything else.** Do not go hunting for a
> typo. There is no typo.

Then, in the environment VS Code will inherit:

```powershell
# Windows: SESSION-SCOPED, then launch VS Code from that same shell.
$env:ENGINE_SDK_TOKEN = "github_pat_..."
code
```

**Never `setx`.** It writes the secret permanently into the Windows registry, and every process they
launch afterwards inherits it — including work that has nothing to do with this platform. A secret at
rest, in a place nobody will remember to clean, is not a convenience.

**And VS Code only sees the environment it was launched with.** If it was already open, it does not have
the variable — no matter what the shell says. It must be **fully quit** and relaunched from that shell.

---

## Step 4 — Open the container, then hand over

Clone their repo, open it in VS Code, accept **Reopen in Container** (or *Clone Repository in Container
Volume*).

**Verify from inside, do not declare victory from outside:**

```bash
echo "${ENGINE_SDK_TOKEN:+token: present}"
docker version --format 'docker: {{.Server.Version}}'      # the local bench
python -c "import omnianvil.core as c; l=type(c.__loader__).__name__; print('engine:', l)"
find /opt/iter -name '*.py' | wc -l                        # must be 0
```

Expect: token present · a docker server version · `nuitka_module_loader` · **`0`**.

That last line is the boundary reporting itself. If it is not `0`, something is very wrong and it is
ours — file it.

**Then stop.** The app repo's own `AGENTS.md` owns everything from here. Read it, and follow it there.

---

## If something breaks

Four failures cover nearly everything, and each one disguises itself:

| what you see | what it is |
|---|---|
| `unauthorized` on the image pull | Step 2 — no `read:packages` credential |
| `404` / *"could not resolve to a repository"* | Step 3 — the token is **pending approval** |
| the token is missing *inside* the container | VS Code was already running when the variable was set |
| a tool behaves like an older version of itself | **a cached image.** Docker does not re-pull a tag it already has, and `--no-cache` rebuilds *layers on top of* the base — it never re-fetches the base. `docker pull` explicitly, or delete the image. |

Anything else is **ours**, not theirs. From inside the container: **`abcli feedback new`**. Paste the
evidence — the failing command, the traceback, the path. Do not classify it; the routing is derived from
what you paste.

**Do not silently work around a wall.** You are the first person to walk this path with fresh eyes, and
the things that stop you are the things we cannot see from inside the house. Every one of them is a
defect we want.
