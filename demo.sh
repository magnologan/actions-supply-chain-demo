#!/usr/bin/env bash
# demo.sh - the live walkthrough, step by step.
#
# Each step prints a header and one line of narration, pauses for Enter, runs the
# commands VISIBLY, then prints what the audience just learned. Workflows run for
# real on GitHub-hosted runners via `gh workflow run`.
#
#   ./demo.sh preflight          check auth, GitHub status, secrets, settings; cache logs
#   ./demo.sh vulnerable         part 1: the leak
#   ./demo.sh hardened           part 2: same action, no blast radius
#   ./demo.sh all                both parts back to back
#   ./demo.sh <part> --yes       no pauses (rehearsal)
#   ./demo.sh <part> --offline   replay the logs cached by preflight (venue wifi down)
set -euo pipefail
cd "$(dirname "$0")"

REPO="${DEMO_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo magnologan-fellow/actions-supply-chain-demo)}"
REF="${DEMO_REF:-main}"
CACHE=.demo-cache

PART="${1:-all}"; shift || true
YES=0; OFFLINE=0
for a in "$@"; do case "$a" in --yes) YES=1;; --offline) OFFLINE=1;; esac; done
[ -t 1 ] || YES=1   # non-TTY (pipe/CI) runs non-interactive

if [ -t 1 ]; then
  c_bold=$'\e[1m' c_dim=$'\e[2m' c_yel=$'\e[33m' c_grn=$'\e[32m' c_cyn=$'\e[36m' c_red=$'\e[31m' c_off=$'\e[0m'
else
  c_bold= c_dim= c_yel= c_grn= c_cyn= c_red= c_off=
fi

pause()   { (( YES )) && { echo; return; }; printf '%s   [Enter]%s ' "$c_dim" "$c_off"; read -r _ </dev/tty || true; echo; }
step()    { echo; printf '%s==== %s ====%s\n' "$c_bold" "$1" "$c_off"; printf '%s%s%s\n' "$c_yel" "$2" "$c_off"; pause; }
learned() { printf '%s  -> %s%s\n' "$c_grn" "$1" "$c_off"; }
note()    { printf '%s     (%s)%s\n' "$c_dim" "$1" "$c_off"; }
show()    { printf '%s$ %s%s\n' "$c_cyn" "$1" "$c_off"; }
ok()      { printf '%s  ok%s   %s\n' "$c_grn" "$c_off" "$1"; }
bad()     { printf '%s  FAIL%s %s\n' "$c_red" "$c_off" "$1"; FAILED=1; }
die()     { printf '%s%s%s\n' "$c_red" "$1" "$c_off" >&2; exit 1; }

# Strip timestamps, ANSI colour and the echoed script body from `gh run view --log`
# so only what the step actually printed is left.
clean() {
  # gh writes ANSI colour as literal "^[" text; the script body it echoes is cyan.
  awk -F'\t' 'BEGIN{OFS="\t"} {
    sub(/^\xef\xbb\xbf/, "", $3)
    sub(/^[0-9T:.-]+Z ?/, "", $3)
    if ($3 ~ /^(\^\[|\x1b)\[36;1m/ || $3 ~ /^##\[/) next
    gsub(/(\^\[|\x1b)\[[0-9;]*m/, "", $3)
    print }'
}

# trigger <workflow file>: run it on $REF, wait, cache the cleaned log, print the run id.
trigger() {
  local wf=$1 out id
  show "gh workflow run $wf --ref $REF" >&2
  out=$(gh workflow run "$wf" -R "$REPO" --ref "$REF" 2>&1) || die "$out"
  id=$(grep -oE 'runs/[0-9]+' <<<"$out" | tail -1 | cut -d/ -f2)
  [ -n "$id" ] || { sleep 5; id=$(gh run list -R "$REPO" -w "$wf" -b "$REF" -L 1 --json databaseId --jq '.[0].databaseId'); }
  show "gh run watch $id" >&2
  gh run watch "$id" -R "$REPO" --exit-status --interval 3 >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6; do   # logs can lag completion by a few seconds
    gh run view "$id" -R "$REPO" --log 2>/dev/null | clean > "$CACHE/${wf%.yml}.log" && [ -s "$CACHE/${wf%.yml}.log" ] && break
    sleep 3
  done
  gh run view "$id" -R "$REPO" --json conclusion,url --jq '"\(.conclusion) \(.url)"' > "$CACHE/${wf%.yml}.meta"
  echo "$id"
}

# grab <workflow> <job> <step> [regex]: print the cached output lines of one step.
grab() {
  awk -F'\t' -v j="$2" -v s="$3" '$1==j && $2==s {print "     " $3}' "$CACHE/$1.log" | grep -E "${4:-.}" || true
}
# The full scope list is ~20 lines; show the ones that matter, then count the rest.
perms() {
  local all; all=$(grab "$1" "$2" "Set up job" '^ +[A-Za-z]+: (read|write)$')
  grep -E '^ +(Contents|Packages|Actions|PullRequests|Deployments|Metadata):' <<<"$all"
  local more; more=$(grep -vcE '^ +(Contents|Packages|Actions|PullRequests|Deployments|Metadata):' <<<"$all" || true)
  (( more > 0 )) && note "+ $more more scopes, $(grep -c ': write$' <<<"$all" || true) of $(grep -c . <<<"$all") scopes at write"
  return 0
}
result() { read -r concl url < "$CACHE/$1.meta"; learned "run: $concl  $url"; }

run_wf() {
  mkdir -p "$CACHE"
  if (( OFFLINE )); then
    [ -s "$CACHE/$1.log" ] || die "no cached log for $1; run ./demo.sh preflight while you still have network"
    note "offline: replaying the run cached at preflight"
  else
    trigger "$1.yml" >/dev/null
  fi
}

# ---------------------------------------------------------------------------
preflight() {
  FAILED=0
  echo "${c_bold}Pre-flight for $REPO @ $REF${c_off}"
  gh auth status >/dev/null 2>&1 && ok "gh is logged in" || bad "gh auth status failed (run: gh auth login)"
  local s; s=$(curl -fsS --max-time 5 https://www.githubstatus.com/api/v2/status.json 2>/dev/null | grep -o '"description":"[^"]*"' | head -1 | cut -d'"' -f4)
  [ "$s" = "All Systems Operational" ] && ok "githubstatus: $s" || bad "githubstatus: ${s:-unreachable}"
  local sec; sec=$(gh secret list -R "$REPO" 2>/dev/null | cut -f1)
  for n in DEMO_DEPLOY_KEY DEMO_NPM_TOKEN; do grep -qx "$n" <<<"$sec" && ok "secret $n exists" || bad "secret $n missing"; done
  local lis; lis=$(gh variable list -R "$REPO" 2>/dev/null | cut -f1 | grep -x DEMO_LISTENER || true)
  [ -z "$lis" ] && ok "DEMO_LISTENER unset (exfil step stays silent)" || note "DEMO_LISTENER is set: the action will POST to it"
  local wp; wp=$(gh api "repos/$REPO/actions/permissions/workflow" --jq .default_workflow_permissions 2>/dev/null)
  [ "$wp" = write ] && ok "default GITHUB_TOKEN is write (vulnerable run shows it)" || bad "default_workflow_permissions=$wp (vulnerable run will show read-only)"
  echo; echo "${c_bold}Rehearsal: running both workflows for real and caching their logs${c_off}"
  mkdir -p "$CACHE"
  for wf in vulnerable hardened; do
    trigger "$wf.yml" >/dev/null
    read -r concl url < "$CACHE/$wf.meta"
    [ "$concl" = success ] && ok "$wf: $url" || bad "$wf: $concl $url"
  done
  grep -q 'token length: [1-9]' "$CACHE/vulnerable.log" && ok "vulnerable: action saw a live token" || bad "vulnerable: no token length in log"
  grep -q 'DEPLOY_KEY visible: <not set>' "$CACHE/hardened.log" && ok "hardened: action saw no secrets" || bad "hardened: unexpected analyze output"
  grep -q '  sub: ' "$CACHE/hardened.log" && ok "hardened: OIDC claims printed" || bad "hardened: no OIDC claims"
  echo
  (( FAILED )) && die "pre-flight FAILED, see RUNBOOK.md Fallbacks" || echo "${c_grn}${c_bold}stage-ready${c_off} (cached logs in $CACHE/ for --offline)"
}

# ---------------------------------------------------------------------------
vulnerable() {
  step "1/5  THE PIPELINE" \
"A normal build: check out the code, run a popular third-party action, deploy.
Three ordinary choices: a mutable tag, no permissions block, secrets in the same job."
  show "sed -n '/^on:/,\$p' .github/workflows/vulnerable.yml"
  sed -n '/^on:/,$p' .github/workflows/vulnerable.yml | grep -vE '^\s*#' | sed '/^$/d; s/^/     /'
  learned "actions/checkout@v4 is a tag: a pointer the publisher (or an attacker) can move."
  learned "./demo-action stands in for tj-actions/changed-files@v45."

  step "2/5  RUN IT" \
"This runs for real on a GitHub-hosted runner, right now."
  run_wf vulnerable
  result vulnerable

  step "3/5  WHAT THE TOKEN CAN DO" \
"No permissions block, so the job gets the repo default. Look at the token GitHub
handed this job, before any of our code ran."
  show "gh run view --log  (step: Set up job, GITHUB_TOKEN Permissions)"
  perms vulnerable build
  learned "Write access to code, packages, PRs and deployments. For a job that only reads files."

  step "4/5  WHAT THE ACTION SAW" \
"The action does its advertised job. Then, in the part nobody reviews, it reads
whatever the job holds and prints it to the log. On a public repo, the log is the
exfiltration channel."
  show "gh run view --log  (step: Analyze changed files)"
  grab vulnerable build "Analyze changed files" 'files changed|\[demo\]'
  learned "*** is GitHub masking a secret it knows. The action HAD both secrets."
  learned "token length 377: a live write-scoped GITHUB_TOKEN, in a stranger's code."
  note "tj-actions double-base64'd its dump, so the masker didn't match. The log is public."

  step "5/5  THE PART THE DEMO SIMPLIFIES" \
"I passed the secrets in through env so you can see it. The real payload didn't need
that: it read Runner.Worker memory, which holds every secret the job references,
including the Deploy step's key. Removing env lines is not the fix. Moving jobs is."
  learned "The job, not the step, is the isolation boundary."
}

# ---------------------------------------------------------------------------
hardened() {
  step "1/6  SAME PIPELINE, FOUR CHANGES" \
"Same third-party action, same deploy. Least-privilege token, actions pinned to a
commit SHA, the untrusted action in its own job, and OIDC instead of a stored key."
  show "diff <(vulnerable.yml) <(hardened.yml)  (highlights)"
  grep -nE '^permissions:|^  contents: read|uses: actions/checkout@|^  [a-z]+:$|needs:|id-token: write' .github/workflows/hardened.yml | sed 's/^/     /'
  learned "@fbc6f39... is one exact commit. Nobody can move it."

  step "2/6  RUN IT" \
"Same runner, same malicious action."
  run_wf hardened
  result hardened

  step "3/6  THE TOKEN NOW" \
"Same place in the log as before: the token GitHub handed each job."
  show "gh run view --log  (step: Set up job, GITHUB_TOKEN Permissions)"
  echo "     analyze:"; perms hardened analyze
  echo "     deploy:";  perms hardened deploy
  learned "Read-only everywhere. A stolen token can't push code or packages."

  step "4/6  WHAT THE ACTION SAW" \
"The exact same action code. It goes looking for the same secrets."
  show "gh run view --log  (job: analyze, step: Analyze changed files)"
  grab hardened analyze "Analyze changed files" 'files changed|\[demo\]'
  learned "Nothing. No secret is referenced in this job, so none ever reached this runner."
  note "not in env, not in Runner.Worker memory: different job, different VM"

  step "5/6  OIDC: NOTHING DURABLE TO STEAL" \
"The deploy job asks GitHub for a short-lived identity token. AWS would trade it for
credentials that expire in an hour. We print the claims, never the token."
  show "gh run view --log  (job: deploy, step: Request OIDC token)"
  grab hardened deploy "Request OIDC token (what AWS would receive)" '^ +(iss|aud|sub|ref|exp): '
  learned "The cloud trusts 'this repo, this branch', not a key someone stored."
  note "the sub has owner/repo IDs (immutable subject): your IAM trust policy matches that exact string"

  step "6/6  THE GAP" \
"Pinning the action you call does not pin what that action pulls in. tj-actions
itself was likely breached through reviewdog/action-setup@v1, a transitive action.
Workflow lockfiles (GA October 2026) pin the whole tree."
  learned "Pin. Scope the token. Split the job. Use OIDC. Lock the transitive tree."
}

case "$PART" in
  preflight)  preflight ;;
  vulnerable) vulnerable ;;
  hardened)   hardened ;;
  all)        vulnerable; hardened ;;
  *) die "usage: ./demo.sh {preflight|vulnerable|hardened|all} [--yes] [--offline]" ;;
esac
