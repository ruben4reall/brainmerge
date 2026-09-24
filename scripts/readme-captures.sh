#!/bin/bash
# scripts/readme-captures.sh: the README's screenshots, on a demo home with generic accounts, with an active window.
# Each capture waits until the Mac is idle (see capture.sh --active): run it when you are away from the keyboard.
set -eo pipefail
cd "$(dirname "$0")/.."
EXPORTS=$(scripts/demo-home.sh 2>/dev/null | tail -n1)
case "$EXPORTS" in export\ BRAINMERGE_HOME=*) eval "$EXPORTS" ;; *) echo "the demo home could not be prepared" >&2; exit 1 ;; esac
export BRAINMERGE_MEMORY_PRESSURE=normal
cleanup() { scripts/demo-home.sh clean "$BRAINMERGE_HOME" >/dev/null 2>&1 || true; }
trap cleanup EXIT
BRAINMERGE_ONBOARDING_STEP=0 scripts/capture.sh 02-premier-lancement --active
BRAINMERGE_ONBOARDING_STEP=1 scripts/capture.sh 02b-how-it-works --active
BRAINMERGE_ONBOARDING_STEP=2 scripts/capture.sh 02c-memory-location --active
BRAINMERGE_ONBOARDING_STEP=4 scripts/capture.sh 02d-second-account --active
BRAINMERGE_ONBOARDING_STEP=5 scripts/capture.sh 02e-all-set --active
BRAINMERGE_SCREEN=accounts scripts/capture.sh 03-comptes --active
BRAINMERGE_SCREEN=add scripts/capture.sh 04-ajout --active
BRAINMERGE_SCREEN=edit scripts/capture.sh 08-edit --active
BRAINMERGE_SCREEN=memory scripts/capture.sh 05-memoire --active
BRAINMERGE_SCREEN=settings scripts/capture.sh 06-reglages --active
BRAINMERGE_SCREEN=usage scripts/capture.sh 21-usage --active
echo "README captures done"
