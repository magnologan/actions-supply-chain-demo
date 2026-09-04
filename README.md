# GitHub Actions Supply-Chain Compromise - Demo Lab

Companion repo for the Offensive Engineering session on CI/CD supply-chain
compromise via a malicious GitHub Action.

Reproduces the mechanism behind **CVE-2025-30066** (`tj-actions/changed-files`,
March 2025), where attackers retroactively moved version tags onto a malicious
commit, affecting 23,000+ repositories.

## What's here

| File | What it shows |
|---|---|
| `.github/workflows/vulnerable.yml` | Mutable tag reference, unscoped `GITHUB_TOKEN`, secrets in the same job as untrusted code |
| `.github/workflows/hardened.yml` | SHA-pinned actions, `contents: read`, job split, OIDC |
| `demo-action/action.yml` | Stand-in for the compromised third-party action |

## The mechanism, in one paragraph

A third-party action runs as a **step inside your job**. Steps in a job share an
environment. So any secret the job holds, `GITHUB_TOKEN`, deploy keys, registry
tokens, is readable by every step, including the one you didn't write. The
compromise doesn't need a GitHub vulnerability; it needs your workflow to point
at code that changed underneath you.

## The fixes, in blast-radius order

1. **Pin actions to full 40-character commit SHAs.** Tags are mutable pointers;
   in the tj-actions incident, users pinned to a hash were unaffected.
2. **Scope `GITHUB_TOKEN`** with an explicit `permissions:` block, default
   `contents: read`. Note the default was read-write before Feb 2023, and GitHub
   only changed it for *new* orgs and repos.
3. **Isolate secrets from untrusted code**, run third-party actions in a job
   that holds nothing.
4. **Use OIDC** for cloud credentials so nothing long-lived exists to steal.
5. **Monitor runner egress** (e.g. StepSecurity Harden-Runner, which is what
   actually detected tj-actions). Note that tj-actions printed to logs rather
   than exfiltrating, so egress monitoring alone is not sufficient either.

## The gap nobody talks about

Pinning the action you call does **not** pin that action's own transitive
dependencies. GitHub's 2026 security roadmap includes a `dependencies:` workflow
lockfile, a `go.sum` for workflows, for precisely this reason.

## Running it

Use a throwaway repo you own, with fake secrets only.

## Sources

- GitHub Advisory: https://github.com/advisories/ghsa-mrrh-fwg8-r2c3
- CISA: https://www.cisa.gov/news-events/alerts/2025/03/18/supply-chain-compromise-third-party-tj-actionschanged-files-cve-2025-30066-and-reviewdogaction
- Wiz: https://www.wiz.io/blog/github-action-tj-actions-changed-files-supply-chain-attack-cve-2025-30066
- StepSecurity (detection): https://www.stepsecurity.io/blog/harden-runner-detection-tj-actions-changed-files-action-is-compromised
- Unit 42 (Coinbase origin): https://unit42.paloaltonetworks.com/github-actions-supply-chain-attack/
- GitHub secure-use docs: https://docs.github.com/en/actions/reference/security/secure-use
