#!/usr/bin/env bash
# Trigger a Jenkins job over HTTP (works with classic crumb + API token).
#
# Required: JENKINS_URL (e.g. https://jenkins.example.com), JENKINS_JOB (folder/job name URL-encoded if needed)
# Optional: JENKINS_USER, JENKINS_TOKEN (or JENKINS_API_TOKEN). If anonymous build is allowed, leave user/token unset.

set -euo pipefail

: "${JENKINS_URL:?Set JENKINS_URL (e.g. https://jenkins.example.com)}"
: "${JENKINS_JOB:?Set JENKINS_JOB (job path, e.g. car-detector or folder/job)}"

BASE="${JENKINS_URL%/}"
JOB_PATH=""
IFS='/' read -r -a PARTS <<< "${JENKINS_JOB}"
for p in "${PARTS[@]}"; do
  [[ -z "$p" ]] && continue
  JOB_PATH+="/job/${p}"
done
JOB_URL="${BASE}${JOB_PATH}/build"

USER="${JENKINS_USER:-}"
TOKEN="${JENKINS_TOKEN:-${JENKINS_API_TOKEN:-}}"
AUTH=()
if [[ -n "$USER" || -n "$TOKEN" ]]; then
  AUTH=(-u "${USER}:${TOKEN}")
fi

CRUMB_JSON="$(curl -fsS "${AUTH[@]}" "${BASE}/crumbIssuer/api/json" 2>/dev/null || true)"
CRUMB="$(echo "$CRUMB_JSON" | jq -r '.crumb // empty' 2>/dev/null || true)"
CRUMB_FIELD="$(echo "$CRUMB_JSON" | jq -r '.crumbRequestField // empty' 2>/dev/null || true)"

HDR=()
if [[ -n "$CRUMB" && -n "$CRUMB_FIELD" ]]; then
  HDR=(-H "${CRUMB_FIELD}: ${CRUMB}")
fi

echo "POST ${JOB_URL}"
curl -fsS -X POST "${AUTH[@]}" "${HDR[@]}" "$JOB_URL" -o /dev/null
echo "Build trigger sent."
