<!-- doc-language:waived -->
# Welcome — building an app on Iter Suite

You are here because you are going to build an application **on the Iter Suite platform**, from the
outside. This repository is the **only thing you need to read before anything exists** — no account, no
container, no tools. Start here, in order, and you will end with a working environment in about fifteen
minutes.

> **Everything on this page happens on YOUR machine, before any container exists.**
> Once your dev container is running, it carries its own runbook (`AGENTS.md`, inside your app repo) and
> this one is done. **That line — the container wall — is the only rule for where a thing is documented.**
> We learned it the hard way: instructions for your laptop, written inside a container you could not yet
> open, are instructions nobody can follow.

---

## What you are getting, and what you will never see

You build **against artifacts, never against the platform's source.**

| you receive | you never receive |
|---|---|
| the **devbox** — a container image with the platform **compiled** inside it | the platform's source code |
| the **engine wheel** — the backend, as a compiled binary (`.so`) | the engine's Python |
| the **types** — TypeScript declarations for the frontend packages | the frontend implementation |
| **`abcli`** — the developer CLI, one compiled binary | its source |

This is not a trust problem, and it is not a limitation of your role. It is the arrangement that lets a
third party build on a platform whose engine is its owner's core IP. **You compile against all of it and
can read none of it**, and everything you need to do your job crosses that line as a built artifact.

If something you need is not on the public surface, that is a **request** (`abcli feedback new`) — not a
reason to reach for internals. **They are not present.** There is nothing to reach for.

---

## Step 1 — Accept the invitation

You have been invited to the **IterSuite** GitHub organization. Accept it.

Your account will have **no default access to anything** (`base permission: None`). Access is granted to
you **by name, per repository** — you should see exactly two:

- **your app repo** (write) — the thing you are building
- **`IterSuite/engine-sdk`** (read) — where the compiled engine crosses the boundary to you

If you cannot see `engine-sdk`, stop here and say so. Everything downstream needs it, and every failure
it causes looks like something else.

---

## Step 2 — The two keys

You need **two** credentials. They look redundant. They are not — they open **two different doors**, and
we deliberately did not merge them.

| # | key | opens | how |
|---|---|---|---|
| **1** | a token with **`read:packages`** | **pulling the devbox image** from GHCR | the script below, or by hand |
| **2** | **`ENGINE_SDK_TOKEN`** — fine-grained, **`contents:read`**, on **`IterSuite/engine-sdk`** and nothing else | **the engine wheel + the frontend types** | you create it; an org owner approves it |

> **Why two?** Because the second one **is** the boundary. A key that opens exactly one repository of
> compiled binaries is a key that, if it ever leaks, costs a rotation instead of a company. We could
> hand you one broad token that opens both. It would work perfectly, and it would quietly undo the thing
> this whole arrangement exists to protect. See [ADR-106](#).

### 2.1 — The image key (scripted)

```powershell
# Windows (PowerShell)
iwr -useb https://raw.githubusercontent.com/IterSuite/welcome/v1/scripts/iter-login.ps1 | iex
```

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/IterSuite/welcome/v1/scripts/iter-login.sh | bash
```

> **Read the script before you run it.** It is about a hundred lines, in this repository, and we mean
> this literally: piping a remote script into your shell is the exact shape of a supply-chain attack.
> We use the pattern because it is the least-bad onboarding path, and we pin the URL to a tag so it
> cannot change under you. **You should still look.** If we ever teach you not to, we have taught you
> the vector.
>
> **It installs nothing.** It opens a browser, takes a token you paste into a hidden prompt, and hands
> it to Docker. That is all it does.

### 2.2 — The engine key (by hand, and it stays that way)

On **your** account: **Settings → Developer settings → Personal access tokens → Fine-grained tokens**

- **Resource owner:** `IterSuite` *(the organization — not your username)*
- **Repository access:** *Only select repositories* → **`engine-sdk`**, and nothing else
- **Permissions:** *Repository permissions* → **Contents: Read-only**

Then **wait**. A fine-grained token targeting an organization sits **`Pending`** until an owner approves
it — and while it is pending it can see **zero repositories** and reports every one of them as
**"not found"**. It does not say *"not yours"*; GitHub masks a 403 as a 404 on private repositories.

> **If a fetch 404s later, check the approval before you check anything else.** This is the single most
> expensive minute in this document, and it costs an afternoon when it is skipped.

Finally, put it in your environment — **never in a repo, never in an image, never in a chat**:

```powershell
# Windows: this session only. Then launch VS Code FROM this shell so it inherits.
$env:ENGINE_SDK_TOKEN = "github_pat_..."
code
```

```bash
# macOS / Linux
export ENGINE_SDK_TOKEN=github_pat_...
```

> **Do not use `setx`.** It writes the secret into your Windows registry permanently, and every process
> you launch from then on inherits it — including work that has nothing to do with us.
>
> **VS Code only ever sees the environment it was launched with.** If you set the variable and VS Code
> was already open, it will not have it. Quit VS Code **completely**, then launch it from the shell where
> you set it.

---

## Step 3 — Your app repository

Your repo was created from **`IterSuite/start-app`**, a template. It is a **seed**: it is nearly empty on
purpose, because pre-written scaffolding rots. `abcli` generates the real thing, fresh, when you ask.

Clone it and open it in VS Code. Accept **"Reopen in Container"** (or **"Clone Repository in Container
Volume"**, which is faster on Windows).

**What you should see:** the image is pulled, the container builds, and it prints a line proving the
platform loaded from **compiled** code with **zero** readable `.py` files. That line is not decoration —
it is the boundary, reporting itself.

**If the pull fails with `unauthorized`:** that is Step 2.1. The container cannot exist without it.

---

## Step 4 — You are inside. Stop reading this.

Your app repo carries **`AGENTS.md`** — the runbook for everything that happens *inside* the container:
installing `abcli`, scaffolding the app, bringing the engine across, writing your backend, and building
your image locally instead of waiting on CI.

**Point your AI coding agent at it.** It is written for one.

---

## When something breaks

Almost every failure here is one of four things, and each disguises itself as something else:

| what you see | what it almost always is |
|---|---|
| `unauthorized` pulling the image | **Step 2.1** — no `read:packages` credential |
| a `404` / *"could not resolve to a repository"* | **Step 2.2** — the token is **pending approval**, and sees nothing |
| the token is missing *inside* the container | VS Code was **already running** when you set the variable |
| a tool behaving like an older version | your Docker has a **cached image**. `docker pull` does not happen by itself, and `--no-cache` does not do it either |

If it is none of those, it is ours. **`abcli feedback new`** — from inside the container — files it with
the evidence, and it reaches the people who can fix it. **Do not work around it silently.** A wall you
climb over alone is a wall the next person also hits.

---

**Related:** [`IterSuite/start-app`](https://github.com/IterSuite/start-app) (the template) ·
[`IterSuite/engine-sdk`](https://github.com/IterSuite/engine-sdk) (the compiled engine) ·
[`omnianvil/abcli`](https://github.com/omnianvil/abcli) (the CLI, public releases)
