# GitHub Actions Supply-Chain Compromise - Demo Lab

Companion repo for the session on CI/CD supply-chain
compromise via a malicious GitHub Action.

Reproduces the mechanism behind **CVE-2025-30066** (`tj-actions/changed-files`,
March 2025), where attackers retroactively moved version tags onto a malicious
commit. The action was used by 23,000+ repositories; Endor Labs found 218 that
actually leaked secrets to their build logs during the window.

The tj-actions maintainer token itself was likely stolen through a *transitive*
action: `tj-actions/eslint-changed-files` used `reviewdog/action-setup@v1`,
whose tag had been moved to a malicious commit days earlier (CVE-2025-30154).

## What's here

| File | What it shows |
|---|---|
| `.github/workflows/vulnerable.yml` | Mutable tag reference, unscoped `GITHUB_TOKEN`, secrets in the same job as untrusted code |
| `.github/workflows/hardened.yml` | SHA-pinned actions, `contents: read`, job split, OIDC |
| `demo-action/action.yml` | Stand-in for the compromised third-party action |
| `demo.sh` | Live driver: pre-flight, then each part step by step with an Enter pause |
| `RUNBOOK.md` | Presenter cue sheet: pre-flight, what to type, what to expect, fallbacks |
| `NARRATION.md` | Speaker notes: the spoken line per step, with sources, plus likely questions |

## The mechanism, in one paragraph

A third-party action runs as a **step inside your job**: same VM, same user,
passwordless `sudo` on GitHub-hosted runners. The runner process holds every
secret the job references, not just the ones you put in that step's `env:`.
tj-actions read them straight out of `Runner.Worker` memory. So any secret the
job holds, `GITHUB_TOKEN`, deploy keys, registry tokens, is reachable from every
step, including the one you didn't write. The job, not the step, is the
isolation boundary. The compromise doesn't need a GitHub vulnerability; it needs
your workflow to point at code that changed underneath you.

## The fixes, in blast-radius order

1. **Pin actions to full 40-character commit SHAs.** Tags are mutable pointers;
   in the tj-actions incident, users pinned to a known-good hash were unaffected
   (unless a bot or a human bumped the pin to the malicious commit during the
   window, so review pin bumps too). Enforce it with the Actions policy
   "Require actions to be pinned to a full-length commit SHA". If you publish
   actions, enable immutable releases so your tags can't be moved.
2. **Scope `GITHUB_TOKEN`** with an explicit `permissions:` block, default
   `contents: read`. Note the default was read-write before Feb 2023, and GitHub
   only changed it for *new* orgs and repos.
3. **Isolate secrets from untrusted code**, run third-party actions in a job
   that holds nothing.
4. **Use OIDC** for cloud credentials so nothing long-lived exists to steal.
5. **Monitor runner egress** (e.g. StepSecurity Harden-Runner, which detected
   tj-actions when the payload fetched `memdump.py` from
   `gist.githubusercontent.com`). The secrets themselves were printed to logs
   (double base64) rather than sent anywhere, so a payload carrying its code
   inline would make no outbound call at all. Necessary, not sufficient.

## The gap nobody talks about

Pinning the action you call does **not** pin that action's own transitive
dependencies (see reviewdog above). GitHub's workflow lockfiles, GA since
October 2026, address this: `gh actions-lock` writes `.github/workflows/actions.lock`,
pinning every action and its transitive dependencies to commit SHAs, a `go.sum`
for workflows. Admins can enforce it with the "Require lockfile" policy.

## Running it

Use a throwaway repo you own, with fake secrets only. Run logs on a public
repo are public.

1. Fork this repo.
2. Add repo secrets `DEMO_DEPLOY_KEY` and `DEMO_NPM_TOKEN` with fake values.
3. Run **Build (vulnerable)**, then **Build (hardened)** from the Actions tab
   (or `gh workflow run vulnerable.yml` / `gh workflow run hardened.yml`).
4. Compare the `Analyze changed files` step output and the
   `GITHUB_TOKEN Permissions` block under `Set up job`.

Or drive it live, step by step (needs `gh` logged in to your fork):

```bash
./demo.sh preflight      # checks settings, runs both workflows, caches logs
./demo.sh vulnerable     # part 1, Enter between steps
./demo.sh hardened       # part 2
./demo.sh all --offline  # replay the cached runs with no network
```

See RUNBOOK.md for the full on-stage sequence.

## Sources

- GitHub Advisory: https://github.com/advisories/ghsa-mrrh-fwg8-r2c3
- CISA: https://www.cisa.gov/news-events/alerts/2025/03/18/supply-chain-compromise-third-party-tj-actionschanged-files-cve-2025-30066-and-reviewdogaction
- Wiz: https://www.wiz.io/blog/github-action-tj-actions-changed-files-supply-chain-attack-cve-2025-30066
- StepSecurity (detection): https://www.stepsecurity.io/blog/harden-runner-detection-tj-actions-changed-files-action-is-compromised
- Unit 42 (full chain: spotbugs -> reviewdog -> tj-actions, Coinbase as initial target): https://unit42.paloaltonetworks.com/github-actions-supply-chain-attack/
- Endor Labs (blast radius): https://www.endorlabs.com/learn/blast-radius-of-the-tj-actions-changed-files-supply-chain-attack
- GitHub changelog, workflow lockfiles GA: https://github.blog/changelog/2026-10-28-github-actions-workflow-lockfiles-are-generally-available/
- GitHub secure-use docs: https://docs.github.com/en/actions/reference/security/secure-use
