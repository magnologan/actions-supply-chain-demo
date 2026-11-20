# RUNBOOK - the only file you need open on stage

`./demo.sh vulnerable` and `./demo.sh hardened` are the live drivers: each prints a
step, waits for you to press **Enter**, then runs the commands in front of the room.
The workflows run for real on GitHub-hosted runners. This sheet is the wrapper
around them: pre-flight, the command order, the Enter cadence, what each step should
print, and what to do if something hangs. Full spoken lines are in NARRATION.md;
keep that open on a second screen if you want the exact wording.

---

## The evening before (and again 30 min before you walk on)

```bash
cd ~/bsides-ottawa-review/actions-supply-chain-demo
git pull --ff-only
# 1. Checks gh auth, githubstatus.com, the two fake secrets, DEMO_LISTENER unset,
#    default GITHUB_TOKEN = write. Then runs BOTH workflows for real (~45 s),
#    asserts what they print, and caches the logs in .demo-cache/ for --offline.
./demo.sh preflight      # must end: "stage-ready"
# 2. Dry-run the whole walkthrough once, non-interactively.
./demo.sh all --yes >/dev/null && echo REHEARSAL_OK
```

If `preflight` fails, do not go on stage until it's green - see **Fallbacks**.
Run `preflight` on the venue wifi, so the `--offline` cache is fresh and you know
the network works.

Also open these in browser tabs as a visual backup (they're printed by preflight):
the latest **Build (vulnerable)** and **Build (hardened)** runs on `main`.

## Terminal setup

- Font size 18-22 pt, window ~120 columns.
- Dark background: the script uses green (learned), yellow (narration), cyan
  (commands), dim grey (asides).
- One terminal, one tab. `clear` before you start.
- **Never run `gh auth token` or `gh auth status -t` while mirroring.** The CLI token
  has `admin:org` scopes.
- Close any browser tabs with work content before you mirror.

---

## ON STAGE - the sequence

### 0. Frame it (30 s, no terminal)
"March 2025. Someone moved the version tags of `tj-actions/changed-files`, a GitHub
Action used by 23,000 repos, onto a malicious commit. Every pipeline that said `@v45`
ran the attacker's code on its next build. No GitHub bug. The pipelines just pointed
at code that changed underneath them. This is that, live, on real GitHub runners.
The 'compromised action' is a stand-in in this repo; I'll call that out."

### 1. Part 1: the leak
```bash
./demo.sh vulnerable
```
It prints a **step header + yellow narration**, then `[Enter]`. **Read the
narration (or your NARRATION.md line), then press Enter.** Cadence below - the bold
is the beat to land before you hit Enter.

| # | Header on screen | Land this, then Enter | Expect after Enter |
|---|---|---|---|
| 1 | THE PIPELINE | "Three ordinary choices. **Nobody would flag this in review.**" | the workflow YAML: `@v4`, no `permissions:`, secrets in one job |
| 2 | RUN IT | "This runs for real, right now." | `gh workflow run`, `gh run watch` (~10-20 s), then `run: success <url>` |
| 3 | WHAT THE TOKEN CAN DO | "Before any of our code ran - **look what GitHub handed this job.**" | `Contents: write`, `Packages: write`, ... `17 of 20 scopes at write` |
| 4 | WHAT THE ACTION SAW | "It does its job. **Then the part nobody reviews.**" | `12 files changed`, `DEPLOY_KEY visible: ***`, `NPM_TOKEN visible: ***`, `token length: 377` |
| 5 | THE PART THE DEMO SIMPLIFIES | "**I'm being honest about one shortcut.**" | `The job, not the step, is the isolation boundary.` |

**Step 4 - say this precisely.** `***` is GitHub masking a value it knows is a
secret - that is proof the action *had* it, not proof it was safe. tj-actions printed
its dump **double base64-encoded**, which the masker doesn't match, into public logs.
Don't say "masking only matches the literal string": it also masks single-base64
and other encodings, which is *why* they encoded twice.

**Step 5 - say this precisely.** The demo passes secrets to the action through
`env:` so the leak is visible. The real payload read `Runner.Worker` process memory
(passwordless `sudo` on hosted runners), which holds every secret the job
references - including the Deploy step's. So the fix is a separate job, not deleting
env lines.

### 2. Part 2: same action, no blast radius
```bash
./demo.sh hardened
```

| # | Header on screen | Land this, then Enter | Expect after Enter |
|---|---|---|---|
| 1 | SAME PIPELINE, FOUR CHANGES | "Same malicious action. **Four changes.**" | `permissions: contents: read`, checkout `@fbc6f39...` (v5.1.0), `analyze` / `deploy` jobs, `id-token: write` |
| 2 | RUN IT | "Same runner, same malicious code." | two jobs, `run: success <url>` (~20-40 s) |
| 3 | THE TOKEN NOW | "Same place in the log as before." | both jobs `Contents: read`, `Metadata: read` |
| 4 | WHAT THE ACTION SAW | "**It goes looking for the same secrets.**" | `DEPLOY_KEY visible: <not set>`, `NPM_TOKEN visible: <not set>`, `token length: 0` |
| 5 | OIDC | "Nothing durable to steal." | `iss`, `aud: sts.amazonaws.com`, `sub: repo:magnologan-fellow@329162780/...:ref:refs/heads/main`, `exp` |
| 6 | THE GAP | "**The part nobody talks about.**" | `Pin. Scope the token. Split the job. Use OIDC. Lock the transitive tree.` |

Closing line: "Pinning stops the tag move. Least privilege limits what a stolen token
can do. The job split limits what any action can see - pinned or not, because the
commit you pinned can itself be the bad one. OIDC means there's nothing durable to
take. And lockfiles pin what your pinned actions pull in."

---

## Between runs / next session

Nothing to reset: every run is a fresh GitHub runner. To refresh the offline cache:

```bash
./demo.sh preflight
```

## After the talk

Old runs stay public in the Actions tab. That's fine: the secrets are fake and
masked. Delete them only if you want a clean history:
`gh run list -L 50 --json databaseId --jq '.[].databaseId' | xargs -n1 gh run delete`

---

## Fallbacks (when something misbehaves)

- **`gh run watch` sits > ~60 s** (runner queue). Say "GitHub is finding us a
  runner." If it's still waiting at ~90 s, `Ctrl-C` and re-run the part with
  `--offline` - it replays the run cached at preflight, same output.
- **Venue wifi is down.** `./demo.sh vulnerable --offline` and
  `./demo.sh hardened --offline`. No network needed; the "RUN IT" step says
  "replaying the run cached at preflight". Say so out loud.
- **A step prints the wrong thing** (e.g. `token length: 0` in part 1). Don't debug
  live: `Ctrl-C`, switch to `--offline`. Check later: someone may have changed the
  repo's default token permissions or deleted a secret (`./demo.sh preflight` tells you
  which).
- **`gh` says you're not logged in.** Don't fix it on the projector (the login flow
  shows codes). Go `--offline`.
- **GitHub Actions incident** (githubstatus.com not green). Go `--offline` from the
  start and say why - it's a supply-chain talk; a dependency being down is on theme.
- **You want to skip the pauses** (ran low on time): `Ctrl-C`, then
  `./demo.sh hardened --yes` runs the rest end-to-end without Enter.
- **Projector is a light background.** The colour cues wash out but the text is still
  there; lean on the `->` summaries and read the narration aloud.

## Timing budget (30-min slot)

| Segment | Time |
|---|---|
| Frame (0) | 1-2 min |
| Part 1, 5 steps | 6-8 min |
| Part 2, 6 steps | 8-10 min |
| Q&A / buffer | 8-10 min |

Pre-flight is done **before** the slot, not during it.
