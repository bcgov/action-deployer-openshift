#!/usr/bin/env bash
#
# Regression tests for scripts/parse-parameters.sh.
#
# These exist because a keystore password containing `$` was once leaked into a
# workflow log: the value was interpolated into the step's script body, bash
# expanded it, and the mangled result no longer matched the secret GitHub had
# registered for masking.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARSE="${SCRIPT_DIR}/scripts/parse-parameters.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

PASS=0
FAIL=0

# Runs the parser and populates: ARGS (array), LOG (stdout), STATUS (exit code).
run_parse() {
  local params="$1"
  ARGS=()
  STATUS=0
  LOG="$(PARAMETERS="${params}" "${PARSE}" "${WORK}/out.nul" 2>&1)" || STATUS=$?
  if [ -s "${WORK}/out.nul" ]; then
    while IFS= read -r -d '' a; do ARGS+=("${a}"); done < "${WORK}/out.nul"
  fi
}

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "${expected}" = "${actual}" ]; then
    echo "  ok   ${name}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL ${name}"
    echo "         expected: ${expected}"
    echo "         actual:   ${actual}"
    FAIL=$((FAIL + 1))
  fi
}

echo "dollar signs survive verbatim"
run_parse '-p ZONE=123 -p KEYSTORE_PASSWORD=Pa$$w0rd$X!'
check "argument count"  "4"                             "${#ARGS[@]}"
check "value preserved" 'KEYSTORE_PASSWORD=Pa$$w0rd$X!' "${ARGS[3]}"

echo "command substitution is never executed"
run_parse '-p API_TOKEN=$(whoami)-`hostname`'
check "value preserved" 'API_TOKEN=$(whoami)-`hostname`' "${ARGS[1]}"
check "whoami not run" "0" "$(grep -c "$(whoami)" <<< "${ARGS[1]}")"

echo "sensitive parameters are masked"
run_parse '-p KEYSTORE_PASSWORD=Pa$$w0rd'
check "add-mask emitted" "1" "$(grep -cFx '::add-mask::Pa$$w0rd' <<< "${LOG}")"

run_parse '--param TLS_PRIVATE_KEY=abc123 -p DB_SECRET=xyz789'
check "add-mask for --param form" "1" "$(grep -cFx '::add-mask::abc123' <<< "${LOG}")"
check "add-mask for second pair"  "1" "$(grep -cFx '::add-mask::xyz789' <<< "${LOG}")"

run_parse '-pAPP_PASSWORD=joined'
check "add-mask for joined -p form" "1" "$(grep -cFx '::add-mask::joined' <<< "${LOG}")"

echo "ordinary parameters are not masked"
run_parse '-p MIN_REPLICAS=1 -p ZONE=123 -p KEYCLOAK_URL=https://example.com'
check "no add-mask lines" "0" "$(grep -c '::add-mask::' <<< "${LOG}")"

echo "quoted values stay a single argument"
run_parse '-p GREETING="hello there" -p ZONE=1'
check "argument count"  "4"                       "${#ARGS[@]}"
check "quotes honoured" 'GREETING=hello there'    "${ARGS[1]}"

echo "empty input yields no arguments"
run_parse ''
check "exit status"    "0" "${STATUS}"
check "argument count" "0" "${#ARGS[@]}"
run_parse '   '
check "whitespace-only argument count" "0" "${#ARGS[@]}"

echo "unmatched quotes fail loudly"
run_parse '-p BROKEN="unterminated'
check "non-zero exit" "1" "${STATUS}"
check "error annotation" "1" "$(grep -c '^::error::' <<< "${LOG}")"
check "input not echoed" "0" "$(grep -c 'unterminated' <<< "${LOG}")"

echo
echo "${PASS} passed, ${FAIL} failed"
[ "${FAIL}" -eq 0 ]
