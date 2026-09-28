#!/usr/bin/env bash
#
# Split the `parameters` input into argv and mask any sensitive values.
#
# Usage: parse-parameters.sh <output-file>
#   Reads $PARAMETERS and writes the resulting arguments, NUL delimited, to
#   <output-file>.  Emits ::add-mask:: for values whose parameter name looks
#   sensitive.
#
# The input is deliberately never handed to the shell.  GitHub Actions
# substitutes `${{ inputs.parameters }}` into the script text *before* bash
# parses it, so a value containing $, ` or $() gets expanded -- or executed.
# For a secret that is a disclosure bug: the string bash ends up with no longer
# matches the one GitHub registered for masking, so the runner cannot redact it
# and it reaches the log in the clear.  xargs gives shell-style quote handling
# with no expansion of any kind.
set -euo pipefail

OUTPUT="${1:?output file path required}"
PARAMS="${PARAMETERS:-}"

: > "${OUTPUT}"
[ -n "${PARAMS//[[:space:]]/}" ] || exit 0

# stderr is dropped on purpose: xargs quotes part of its input back in some
# parse errors, which is the one thing we must keep out of the log.
if ! printf '%s' "${PARAMS}" | xargs -n1 printf '%s\0' > "${OUTPUT}" 2>/dev/null; then
  echo "::error::Could not parse the 'parameters' input; check for unmatched quotes."
  exit 1
fi

SENSITIVE_NAME='(PASS|PASSWD|PASSWORD|PASSPHRASE|PWD|SECRET|TOKEN|CREDENTIAL|PRIVATE|SALT|AUTH|CERT|SIGNING)|(^|_)(KEY|KEYS|KEYSTORE|TRUSTSTORE|APIKEY)(_|$)'

# GitHub only masks values it was told about, so a parameter sourced from
# anything but `secrets.*` (a var, a computed value, a matrix entry) is printed
# verbatim unless we register it here.
mask_pair() {
  local pair="$1" name value
  [[ "${pair}" == *=* ]] || return 0
  name="$(printf '%s' "${pair%%=*}" | tr '[:lower:]' '[:upper:]')"
  value="${pair#*=}"
  [ -n "${value}" ] || return 0
  if [[ "${name}" =~ ${SENSITIVE_NAME} ]]; then
    # The runner redacts the value from this line before logging it.
    echo "::add-mask::${value}"
    echo "Masking value of sensitive parameter: ${pair%%=*}"
  fi
}

expect_value=false
while IFS= read -r -d '' arg; do
  if [ "${expect_value}" = true ]; then
    mask_pair "${arg}"
    expect_value=false
    continue
  fi
  case "${arg}" in
    -p|--param) expect_value=true ;;
    --param=*)  mask_pair "${arg#--param=}" ;;
    -p?*)       mask_pair "${arg#-p}" ;;
  esac
done < "${OUTPUT}"
