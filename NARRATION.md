# Speaker notes

One spoken line per step, with the provenance of every claim. Read the line, press
Enter, let the commands run, then deliver the takeaway.

Provenance tags:
- **[GHSA]** - GitHub Advisory GHSA-mrrh-fwg8-r2c3 (CVE-2025-30066).
- **[StepSecurity]** - StepSecurity's Harden-Runner detection write-up.
- **[Wiz]**, **[Unit 42]**, **[Endor]**, **[CISA]** - see README Sources.
- **[GitHub]** - GitHub docs / changelog.
- **[lab]** - a lab stand-in or simplification; not a claim about the incident.

---

### ELI5 opener (optional, 30 s)
> "Your build is a kitchen, and every step is a cook you hired. In the vulnerable
> kitchen you hire 'whoever is wearing the v45 name tag', and your house keys are on
> the counter. Overnight someone swaps the name tag onto a different cook. It chops
> the onions - and photographs your keys and pins the photos to the public notice
> board. The hardened kitchen hires by fingerprint, gives that cook a separate room
> with nothing on the counter, hands out 'look, don't touch' badges, and the person
> who handles money gets a ticket that expires in an hour."

---

## Part 1 - `./demo.sh vulnerable`

### 1/5 The pipeline
> "This is what most pipelines look like. A tag, `@v4`. No `permissions:` block. And
> the deploy key lives in the same job as a third-party action. None of this would
> get flagged in code review." **[GHSA]** affected users referenced
> `tj-actions/changed-files` by tag; the attacker "retroactively modified multiple
> version tags" to point at a malicious commit. **[lab]** `./demo-action` is a local
> stand-in for `tj-actions/changed-files@v45`; a local action can't show a tag
> move - the tag move is the story, the run shows the blast radius.

### 2/5 Run it
> "This is a real GitHub-hosted runner, starting now."

### 3/5 What the token can do
> "Before a single line of our code runs, GitHub hands this job a token. No
> permissions block, so it gets the repo default: write to code, packages, pull
> requests, deployments." **[GitHub]** since Feb 2023 *new* repos and orgs default to
> read-only; existing ones kept read-write. **[lab]** this repo is set to read-write
> on purpose so you can see it.

### 4/5 What the action saw
> "It prints '12 files changed' - its advertised job. Then it reads what the job
> holds and prints it to the log. The stars are GitHub masking a secret it
> recognises. That's proof the action had it. And 377 characters of live,
> write-scoped token, in a stranger's code." **[GHSA]** the attack ended up "exposing CI/CD
> secrets in workflow logs"; public repos have public logs. **[Wiz]** the dump was
> "double-encoded base64", which the runner's masker does not match (it does mask
> the raw value and single base64 - that's *why* they encoded twice).
> **[StepSecurity]** no evidence the secrets were sent anywhere else - the log was
> the channel.

### 5/5 The part the demo simplifies
> "One honest shortcut: I passed the secrets into the action with `env:` so you can
> see them. The real payload didn't need that. It used passwordless sudo to read the
> runner process's memory, which holds every secret the job references - including
> the Deploy step's key. So the fix isn't 'don't pass env'. The fix is: the job, not
> the step, is the isolation boundary." **[GHSA]** the script "extracted secrets from
> the Runner Worker process memory". **[StepSecurity]** it located `Runner.Worker` via
> `/proc` and read its memory.

---

## Part 2 - `./demo.sh hardened`

### 1/6 Same pipeline, four changes
> "Same malicious action. Four changes. A least-privilege token. Actions pinned to a
> full commit SHA, which nobody can move. The untrusted action in its own job. And
> OIDC instead of a stored cloud key." **[Wiz]** users pinned to a known-good SHA
> were unaffected - "unless they had updated to an impacted hash during the
> exploitation timeframe". So review SHA bumps from Dependabot/Renovate too.

### 2/6 Run it
> "Same runner, same malicious code."

### 3/6 The token now
> "Read-only. Even if something steals it, it can't push code or publish a package."

### 4/6 What the action saw
> "The exact same action, looking for the exact same secrets. Nothing. No secret is
> referenced anywhere in this job, so they never reached this machine - not in env,
> not in memory. Each job is a separate VM." **[lab]** the read-only `GITHUB_TOKEN`
> does still exist in this job's runner; checkout has `persist-credentials: false`
> so it isn't left in `.git/config`.

### 5/6 OIDC
> "The deploy job asks GitHub for a short-lived identity token that says 'I am this
> repo, this branch'. AWS would trade it for credentials that expire in an hour.
> Nothing long-lived exists to steal." **[GitHub]** the `sub` here uses the immutable
> subject format with owner and repo IDs; an IAM trust policy must match that exact
> string. Scope it to repo + branch or environment, never `repo:org/*`.

### 6/6 The gap
> "Pinning the action you call doesn't pin what *that* action pulls in. That's how
> tj-actions itself was likely breached: one of its own workflows used
> `reviewdog/action-setup@v1`, whose tag had been moved days earlier." **[CISA]**
> "potentially enabled by" CVE-2025-30154 - say "likely", not "confirmed". **[Unit 42]**
> traces the chain back to a `pull_request_target` token leak in spotbugs, with
> Coinbase's agentkit as the original target. **[GitHub]** workflow lockfiles went GA
> on 2026-10-28: `gh actions-lock` writes `.github/workflows/actions.lock` pinning
> actions and their transitive dependencies, and admins can require it.

### Close
> "Pin. Scope the token. Split the job. Use OIDC. Lock the transitive tree. And
> enforce it: GitHub can fail any workflow that uses an unpinned action, and
> publishers can make their release tags immutable."

---

## Likely questions

- **"Harden-Runner caught tj-actions through egress, so isn't egress monitoring
  enough?"** It caught the *loader* download from gist.githubusercontent.com
  **[GHSA]**. The secrets themselves never left over the network. A payload shipped
  inside the action needs no egress at all. Necessary, not sufficient.
- **"23,000 repos were compromised?"** 23,000 *used* the action. Endor Labs found 218
  that actually leaked secrets during the window **[Endor]**, mostly short-lived
  `GITHUB_TOKEN`s.
- **"The log shows your payload source."** A composite action echoes its script.
  tj-actions hid its payload in compiled JS plus a base64 blob, so the log showed
  only the output.
- **"Why `@v4` when checkout is on v7?"** Exactly the point: a tag gives you no signal
  about what changed. Pins need a bot to bump them, and a human to review the bump.
