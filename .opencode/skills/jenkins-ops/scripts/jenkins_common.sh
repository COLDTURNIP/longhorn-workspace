#!/usr/bin/env bash
# Shared Jenkins operations helpers. This file is safe to source.

# Read-only entrypoints set DRY_RUN=false before sourcing this file. Keep the
# defensive prelude as the single owner of shell options and exit constants.
if [ "${JENKINS_COMMON_LOADED:-false}" != true ]; then
  JENKINS_COMMON_LOADED=true
  case "${BASH_SOURCE[0]}" in */*) _JENKINS_COMMON_DIR=${BASH_SOURCE[0]%/*} ;; *) _JENKINS_COMMON_DIR=. ;; esac
  _JENKINS_COMMON_DIR=$(CDPATH= cd -- "$_JENKINS_COMMON_DIR" && pwd)
  if ! declare -f defensive_parse_args >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    . "${_JENKINS_COMMON_DIR}/../../lib/defensive_prelude.sh"
  fi
  JOBS_FILE="${_JENKINS_COMMON_DIR}/../jobs.json"
  EXIT_JENKINS=4
  EXIT_TIMEOUT=5
  EXIT_BUILD_FAILURE=6
  EXIT_SSH=7
  JENKINS_DEADLINE_SIGNAL=75
  BASE_URL=""
  JOB_ALIAS=""
  JOB_PATH=""
  JOB_PIPELINE=""
  JOB_TEST_SOURCE=""
  JOB_RUNNER=""
  JOB_SEGMENTS_JSON=""
  JOB_REVIEW_PARAMETERS_JSON=""
  JOB_WARNINGS_JSON="{}"
  JOB_URL=""
  PRIVATE_DIR=""
  JENKINS_HTTP_STATUS=""
  JENKINS_HTTP_HEADERS=""
  JENKINS_CRUMB_FIELD=""
  JENKINS_CRUMB_VALUE=""
  JENKINS_CRUMB_DISABLED=false
  JENKINS_REQUEST_FORM=()
  JENKINS_REQUEST_HEADERS=()
  JENKINS_REQUEST_ARGS=()
fi

# Print only a generic diagnostic. Values supplied by users are intentionally
# never included in diagnostics.
_jenkins_error() {
  printf '%s\n' "$1" >&2
}

require_command() {
  local command_name
  command_name=${1:-}
  if [ -z "$command_name" ]; then
    _jenkins_error "Required command is unavailable"
    return 3
  fi
  if ! command -v "$command_name" >/dev/null 2>&1; then
    _jenkins_error "Required command is unavailable: ${command_name}"
    return 3
  fi
  return 0
}

require_jenkins_env() {
  local variable_name missing=0
  for variable_name in JENKINS_URL JENKINS_USER JENKINS_TOKEN; do
    if [ -z "${!variable_name:-}" ]; then
      _jenkins_error "Missing required environment variable: ${variable_name}"
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] || return 3
  return 0
}

require_ssh_env() {
  local variable_name missing=0 raw relative resolved
  for variable_name in JENKINS_SSH_IDENTITY_FILE JENKINS_SSH_USER; do
    if [ -z "${!variable_name:-}" ]; then
      _jenkins_error "Missing required environment variable: ${variable_name}"
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] || return 3

  raw=$JENKINS_SSH_IDENTITY_FILE
  case "$raw" in
    "~")
      if [ -z "${HOME:-}" ]; then
        _jenkins_error "Home directory is unavailable for SSH identity file"
        return 3
      fi
      resolved=$HOME
      ;;
    "~/"*)
      if [ -z "${HOME:-}" ]; then
        _jenkins_error "Home directory is unavailable for SSH identity file"
        return 3
      fi
      relative=${raw#\~/}
      resolved="${HOME%/}/${relative}"
      ;;
    "~"*)
      _jenkins_error "SSH identity file uses unsupported home shorthand"
      return 3
      ;;
    *)
      resolved=$raw
      ;;
  esac

  if [ ! -f "$resolved" ] || [ ! -r "$resolved" ]; then
    _jenkins_error "SSH identity file is unavailable"
    return 3
  fi
  JENKINS_SSH_IDENTITY_RESOLVED=$resolved
  return 0
}

# Normalize JENKINS_URL (or an explicit URL) into BASE_URL. Only loopback HTTP
# is accepted for the fixture; production URLs must use HTTPS.
normalize_base_url() {
  local raw rest authority hostport port normalized
  raw=${1:-${JENKINS_URL:-}}
  if [ -z "$raw" ]; then
    _jenkins_error "Missing required environment variable: JENKINS_URL"
    return 3
  fi
  case "$raw" in
    *[[:space:][:cntrl:]]*|*\?*|*\#*|*@*)
      _jenkins_error "Invalid JENKINS_URL"
      return 2
      ;;
  esac
  case "$raw" in
    https://*)
      rest=${raw#https://}
      ;;
    http://127.0.0.1:*)
      rest=${raw#http://}
      ;;
    http://localhost:*)
      rest=${raw#http://}
      ;;
    *)
      _jenkins_error "Invalid JENKINS_URL"
      return 2
      ;;
  esac
  authority=${rest%%/*}
  if [ -z "$authority" ]; then
    _jenkins_error "Invalid JENKINS_URL"
    return 2
  fi
  case "$authority" in
    :*|*:|*'@'*|*'?'*|*'#'*)
      _jenkins_error "Invalid JENKINS_URL"
      return 2
      ;;
  esac
  case "$authority" in
    *:*)
      case "$authority" in
        \[*\]) ;;
        *)
          port=${authority##*:}
          case "$port" in
            ''|*[!0-9]*)
              _jenkins_error "Invalid JENKINS_URL"
              return 2
              ;;
          esac
          ;;
      esac
      ;;
  esac
  # The fixture forms are deliberately strict: loopback HTTP requires a
  # numeric port, while HTTPS accepts an authority and optional context path.
  case "$raw" in
    http://127.0.0.1:*|http://localhost:*)
      hostport=$authority
      port=${hostport#*:}
      if [ -z "$port" ]; then
        _jenkins_error "Invalid JENKINS_URL"
        return 2
      fi
      case "$port" in *[!0-9]*)
        _jenkins_error "Invalid JENKINS_URL"
        return 2
        ;; esac
      ;;
  esac
  normalized=$raw
  while [ "${normalized%/}" != "$normalized" ]; do
    normalized=${normalized%/}
  done
  case "$normalized" in
    https://|http://|http://127.0.0.1|http://localhost)
      _jenkins_error "Invalid JENKINS_URL"
      return 2
      ;;
  esac
  BASE_URL=$normalized
  return 0
}

resolve_job() {
  local alias
  alias=${1:-}
  if [ -z "$alias" ]; then
    _jenkins_error "Jenkins job alias is required"
    return 2
  fi
  require_command jq || return $?
  if [ ! -r "$JOBS_FILE" ]; then
    _jenkins_error "Jenkins job catalog is unavailable"
    return 4
  fi
  if ! jq -e --arg alias "$alias" '
      (.jobs? | type == "object") and
      (.jobs[$alias]? | type == "object") and
      (.jobs[$alias].segments | type == "array" and length > 0 and all(.[]; type == "string" and length > 0)) and
      (.jobs[$alias].pipeline | type == "string") and
      (.jobs[$alias].testSource | type == "string") and
      (.jobs[$alias].runner | type == "string") and
      (.jobs[$alias].reviewParameters | type == "array") and
      (.jobs[$alias].warnings | type == "object")
    ' "$JOBS_FILE" >/dev/null 2>&1; then
    if jq -e '.jobs? | type == "object"' "$JOBS_FILE" >/dev/null 2>&1 &&
       ! jq -e --arg alias "$alias" '.jobs[$alias]? != null' "$JOBS_FILE" >/dev/null 2>&1; then
      _jenkins_error "Unknown Jenkins job alias"
      return 2
    fi
    _jenkins_error "Jenkins job catalog is malformed"
    return 4
  fi
  # Use independent, quiet queries so all exported fields are shell-safe and
  # no catalog JSON is emitted while a caller is running.
  JOB_ALIAS=$alias
  JOB_PATH=$(jq -r --arg alias "$alias" '.jobs[$alias].segments | join("/")' "$JOBS_FILE" 2>/dev/null) || {
    _jenkins_error "Jenkins job catalog is malformed"
    return 4
  }
  JOB_PIPELINE=$(jq -r --arg alias "$alias" '.jobs[$alias].pipeline' "$JOBS_FILE" 2>/dev/null) || return 4
  JOB_TEST_SOURCE=$(jq -r --arg alias "$alias" '.jobs[$alias].testSource' "$JOBS_FILE" 2>/dev/null) || return 4
  JOB_RUNNER=$(jq -r --arg alias "$alias" '.jobs[$alias].runner' "$JOBS_FILE" 2>/dev/null) || return 4
  JOB_SEGMENTS_JSON=$(jq -c --arg alias "$alias" '.jobs[$alias].segments' "$JOBS_FILE" 2>/dev/null) || return 4
  JOB_REVIEW_PARAMETERS_JSON=$(jq -c --arg alias "$alias" '.jobs[$alias].reviewParameters' "$JOBS_FILE" 2>/dev/null) || return 4
  JOB_WARNINGS_JSON=$(jq -c --arg alias "$alias" '.jobs[$alias].warnings' "$JOBS_FILE" 2>/dev/null) || return 4
  return 0
}

build_job_url() {
  local alias
  alias=${1:-${JOB_ALIAS:-}}
  [ -n "$alias" ] || { _jenkins_error "Jenkins job alias is required"; return 2; }
  [ -n "${BASE_URL:-}" ] || normalize_base_url || return $?
  resolve_job "$alias" || return $?
  require_command jq || return $?
  if ! JOB_URL=$(jq -nr -S --arg base "$BASE_URL" --argjson segments "$JOB_SEGMENTS_JSON" \
      '$base + "/job/" + ($segments | map(@uri) | join("/job/")) + "/"' 2>/dev/null); then
    _jenkins_error "Unable to construct Jenkins job URL"
    return 4
  fi
  return 0
}

new_private_dir() {
  local root directory absolute
  require_command mktemp || return $?
  require_command chmod || return $?
  root=${TMPDIR:-/tmp}
  case "$root" in
    */) root=${root%/} ;;
  esac
  [ -n "$root" ] || root=/
  if ! directory=$(mktemp -d "${root}/jenkins-ops.XXXXXX" 2>/dev/null); then
    _jenkins_error "Private temporary output is unavailable"
    return 3
  fi
  if ! chmod 700 "$directory" >/dev/null 2>&1; then
    rm -rf "$directory" >/dev/null 2>&1 || true
    _jenkins_error "Private temporary output is unavailable"
    return 3
  fi
  case "$directory" in
    /*) absolute=$directory ;;
    *)
      if ! absolute=$(CDPATH= cd -- "$(dirname -- "$directory")" && pwd)/$(basename -- "$directory"); then
        rm -rf "$directory" >/dev/null 2>&1 || true
        _jenkins_error "Private temporary output is unavailable"
        return 3
      fi
      ;;
  esac
  PRIVATE_DIR=$absolute
  return 0
}

_curl_config_escape() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  printf '%s' "$value"
}

# Set JENKINS_HTTP_STATUS and JENKINS_HTTP_HEADERS. The function returns 0 for
# any received HTTP response, 4 after an exhausted transport/retry failure,
# and 75 when an absolute deadline was exhausted before another request.
jenkins_request() {
  local method url outfile deadline remaining total connect attempt http_code curl_rc
  local response_headers retryable sleep_for now value header
  local -a curl_args
  method=${1:-}
  url=${2:-}
  outfile=${3:-}
  deadline=${4:-}
  if [ "$method" != GET ] && [ "$method" != POST ]; then
    _jenkins_error "Unsupported Jenkins HTTP method"
    return 2
  fi
  if [ -z "$url" ] || [ -z "$outfile" ]; then
    _jenkins_error "Jenkins HTTP request arguments are incomplete"
    return 2
  fi
  require_command curl || return $?
  require_jenkins_env || return $?
  normalize_base_url || return $?
  case "$url" in
    "$BASE_URL"/*) ;;
    *)
      _jenkins_error "Jenkins request URL is outside the configured origin"
      return 2
      ;;
  esac
  case "${JENKINS_USER}" in *:*)
    _jenkins_error "Invalid Jenkins credentials"
    return 2
    ;; esac
  case "${JENKINS_USER}" in *$'\r'*|*$'\n'*)
    _jenkins_error "Invalid Jenkins credentials"
    return 2
    ;; esac
  case "${JENKINS_TOKEN}" in *$'\r'*|*$'\n'*)
    _jenkins_error "Invalid Jenkins credentials"
    return 2
    ;; esac
  if [ -n "$deadline" ]; then
    case "$deadline" in *[!0-9]*)
      _jenkins_error "Invalid Jenkins request deadline"
      return 2
      ;; esac
  fi
  if ! : > "$outfile" 2>/dev/null; then
    _jenkins_error "Private temporary output is unavailable"
    return 3
  fi
  chmod 600 "$outfile" >/dev/null 2>&1 || {
    _jenkins_error "Private temporary output is unavailable"
    return 3
  }
  response_headers="${outfile}.headers.$$"
  : > "$response_headers" 2>/dev/null || {
    _jenkins_error "Private temporary output is unavailable"
    return 3
  }
  chmod 600 "$response_headers" >/dev/null 2>&1 || return 3
  JENKINS_HTTP_HEADERS=$response_headers
  attempt=0
  while :; do
    if [ -n "$deadline" ]; then
      remaining=$((deadline - SECONDS))
      if [ "$remaining" -le 0 ]; then
        return "$JENKINS_DEADLINE_SIGNAL"
      fi
      total=$remaining
      [ "$total" -gt 60 ] && total=60
      connect=$total
      [ "$connect" -gt 10 ] && connect=10
    else
      total=60
      connect=10
    fi
    : > "$response_headers" || return 3
    curl_args=(--silent --show-error --globoff --request "$method" --connect-timeout "$connect" --max-time "$total" --dump-header "$response_headers" --output "$outfile" --write-out '%{http_code}')
    for value in "${JENKINS_REQUEST_FORM[@]}"; do
      curl_args+=(--data-urlencode "$value")
    done
    for header in "${JENKINS_REQUEST_HEADERS[@]}"; do
      case "$header" in *$'\r'*|*$'\n'*)
        _jenkins_error "Invalid Jenkins request header"
        return 2
        ;; esac
      curl_args+=(--header "$header")
    done
    for value in "${JENKINS_REQUEST_ARGS[@]}"; do
      case "$value" in
        --location|-L|--config|--user|-u|--url)
          _jenkins_error "Unsupported Jenkins curl option"
          return 2
          ;;
      esac
      curl_args+=("$value")
    done
    curl_args+=(--config - "$url")
    http_code=""
    curl_rc=0
    if http_code=$(printf 'user = "%s:%s"\n' "$(_curl_config_escape "$JENKINS_USER")" "$(_curl_config_escape "$JENKINS_TOKEN")" | curl "${curl_args[@]}" 2>/dev/null); then
      curl_rc=0
    else
      curl_rc=$?
    fi
    JENKINS_HTTP_STATUS=$http_code
    if [ -n "$deadline" ] && [ "$SECONDS" -ge "$deadline" ]; then
      return "$JENKINS_DEADLINE_SIGNAL"
    fi
    if [ "$curl_rc" -ne 0 ] || [ -z "$http_code" ] || [ "$http_code" = 000 ]; then
      if [ "$method" = POST ]; then
        return "$EXIT_JENKINS"
      fi
      if [ -n "$deadline" ] && [ "$curl_rc" -eq 28 ]; then
        now=$SECONDS
        if [ "$now" -ge "$deadline" ]; then
          return "$JENKINS_DEADLINE_SIGNAL"
        fi
      fi
      if [ "$attempt" -ge 1 ]; then
        return "$EXIT_JENKINS"
      fi
      if [ -n "$deadline" ]; then
        remaining=$((deadline - SECONDS))
        if [ "$remaining" -le 0 ]; then
          return "$JENKINS_DEADLINE_SIGNAL"
        fi
        sleep_for=2
        [ "$sleep_for" -gt "$remaining" ] && sleep_for=$remaining
        sleep "$sleep_for"
        if [ "$SECONDS" -ge "$deadline" ]; then
          return "$JENKINS_DEADLINE_SIGNAL"
        fi
      else
        sleep 2
      fi
      attempt=$((attempt + 1))
      continue
    fi
    retryable=false
    case "$http_code" in
      408|429|500|502|503|504) retryable=true ;;
    esac
    if [ "$method" = GET ] && [ "$retryable" = true ]; then
      if [ "$attempt" -ge 1 ]; then
        return "$EXIT_JENKINS"
      fi
      if [ -n "$deadline" ]; then
        remaining=$((deadline - SECONDS))
        if [ "$remaining" -le 0 ]; then
          return "$JENKINS_DEADLINE_SIGNAL"
        fi
        sleep_for=2
        [ "$sleep_for" -gt "$remaining" ] && sleep_for=$remaining
        sleep "$sleep_for"
        if [ "$SECONDS" -ge "$deadline" ]; then
          return "$JENKINS_DEADLINE_SIGNAL"
        fi
      else
        sleep 2
      fi
      attempt=$((attempt + 1))
      continue
    fi
    return 0
  done
}

map_http_error() {
  local status method
  status=${1:-${JENKINS_HTTP_STATUS:-}}
  method=${2:-GET}
  case "$status" in
    401) _jenkins_error "Jenkins authentication failed; verify the configured credentials" ;;
    403)
      if [ "$method" = POST ]; then
        _jenkins_error "Jenkins denied Job/Build permission for this operation"
      else
        _jenkins_error "Jenkins denied Job/Read permission for this operation"
      fi
      ;;
    408|429|500|502|503|504) _jenkins_error "Jenkins transport or server error" ;;
    *) _jenkins_error "Jenkins HTTP request failed" ;;
  esac
  return "$EXIT_JENKINS"
}

fetch_crumb() {
  local crumb_file crumb_url request_rc field value
  crumb_file=${1:-${PRIVATE_DIR:-${TMPDIR:-/tmp}}/crumb.json}
  if [ -z "${BASE_URL:-}" ]; then
    normalize_base_url || return $?
  fi
  require_command jq || return $?
  crumb_url="${BASE_URL}/crumbIssuer/api/json"
  JENKINS_REQUEST_FORM=()
  JENKINS_REQUEST_HEADERS=()
  JENKINS_REQUEST_ARGS=()
  request_rc=0
  jenkins_request GET "$crumb_url" "$crumb_file" || request_rc=$?
  case "$request_rc" in
    2|3) return "$request_rc" ;;
  esac
  if [ "$request_rc" -eq "$JENKINS_DEADLINE_SIGNAL" ]; then
    return "$EXIT_JENKINS"
  fi
  if [ "$request_rc" -ne 0 ]; then
    map_http_error "${JENKINS_HTTP_STATUS:-}" GET >/dev/null 2>&1 || true
    return "$EXIT_JENKINS"
  fi
  if [ "${JENKINS_HTTP_STATUS:-}" = 404 ]; then
    JENKINS_CRUMB_FIELD=""
    JENKINS_CRUMB_VALUE=""
    JENKINS_CRUMB_DISABLED=true
    return 0
  fi
  if [ "${JENKINS_HTTP_STATUS:-}" != 200 ]; then
    map_http_error "${JENKINS_HTTP_STATUS:-}" GET >/dev/null 2>&1 || true
    return "$EXIT_JENKINS"
  fi
  if ! field=$(jq -r -e '.crumbRequestField | select(type == "string" and length > 0)' "$crumb_file" 2>/dev/null) || \
     ! value=$(jq -r -e '.crumb | select(type == "string" and length > 0)' "$crumb_file" 2>/dev/null); then
    _jenkins_error "Jenkins crumb response is malformed"
    return "$EXIT_JENKINS"
  fi
  JENKINS_CRUMB_FIELD=$field
  JENKINS_CRUMB_VALUE=$value
  JENKINS_CRUMB_DISABLED=false
  return 0
}

# Read one response header without printing it unless the caller explicitly
# captures the result. Header names are matched case-insensitively.
response_header() {
  local name line key value lower_name lower_key
  name=${1:-}
  [ -n "$name" ] || return 2
  [ -r "${JENKINS_HTTP_HEADERS:-}" ] || return 1
  lower_name=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
  while IFS= read -r line; do
    case "$line" in
      *:*)
        key=${line%%:*}
        value=${line#*:}
        lower_key=$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')
        if [ "$lower_key" = "$lower_name" ]; then
          value=${value# }
          value=${value%$'\r'}
          printf '%s' "$value"
          return 0
        fi
        ;;
    esac
  done < "$JENKINS_HTTP_HEADERS"
  return 1
}

fetch_parameter_definitions() {
  local alias outfile response normalized request_rc tmp
  alias=${1:-}
  outfile=${2:-}
  if [ -z "$alias" ] || [ -z "$outfile" ]; then
    _jenkins_error "Parameter output arguments are incomplete"
    return 2
  fi
  require_command jq || return $?
  require_command curl || return $?
  require_command mktemp || return $?
  require_command chmod || return $?
  require_jenkins_env || return $?
  normalize_base_url || return $?
  resolve_job "$alias" || return $?
  build_job_url "$alias" || return $?
  response="${outfile}.response.$$"
  if ! : > "$response" 2>/dev/null; then
    _jenkins_error "Private temporary output is unavailable"
    return 3
  fi
  chmod 600 "$response" >/dev/null 2>&1 || {
    rm -f "$response" >/dev/null 2>&1 || true
    _jenkins_error "Private temporary output is unavailable"
    return 3
  }
  JENKINS_REQUEST_FORM=()
  JENKINS_REQUEST_HEADERS=()
  JENKINS_REQUEST_ARGS=()
  jenkins_request GET "${JOB_URL}api/json?tree=name,buildable,actions[parameterDefinitions[name,type,description,defaultParameterValue[value],choices]],property[parameterDefinitions[name,type,description,defaultParameterValue[value],choices]]" "$response" || request_rc=$?
  request_rc=${request_rc:-0}
  if [ "$request_rc" -ne 0 ]; then
    rm -f "$response" >/dev/null 2>&1 || true
    case "$request_rc" in
      2|3) return "$request_rc" ;;
    esac
    if [ "$request_rc" -eq "$JENKINS_DEADLINE_SIGNAL" ]; then
      return "$EXIT_JENKINS"
    fi
    map_http_error "${JENKINS_HTTP_STATUS:-}" GET >/dev/null 2>&1 || true
    return "$EXIT_JENKINS"
  fi
  if [ "${JENKINS_HTTP_STATUS:-}" != 200 ]; then
    rm -f "$response" >/dev/null 2>&1 || true
    map_http_error "${JENKINS_HTTP_STATUS:-}" GET >/dev/null 2>&1 || true
    return "$EXIT_JENKINS"
  fi
  tmp="${outfile}.tmp.$$"
  if ! jq -S -e --arg job "$alias" '
    def fail: error("invalid parameter metadata");
    def scalar: (type == "string" or type == "number" or type == "boolean" or type == "null");
    def normalize:
      if (type != "object") then fail
      elif ((.name? | type) != "string" or (.name | length) == 0) then fail
      elif ((.type? | type) != "string" or (.type | length) == 0) then fail
      elif (.description? == null) then .description = ""
      elif (.description | type) != "string" then fail
      else . end
      | . as $d
      | ($d.defaultParameterValue? // null) as $dpv
      | if ($dpv == null) then
          {present:false, value:null}
        elif (($dpv | type) != "object") then fail
        elif ($dpv | has("value") | not) then
          {present:false, value:null}
        elif ($d.type == "BooleanParameterDefinition" and ($dpv.value | type) != "boolean") then fail
        elif (($d.type == "StringParameterDefinition" or $d.type == "TextParameterDefinition" or $d.type == "PasswordParameterDefinition") and ($dpv.value | type) != "string") then fail
        elif ($d.type == "ChoiceParameterDefinition" and ($dpv.value | type) != "string") then fail
        elif (($d.type != "BooleanParameterDefinition" and $d.type != "StringParameterDefinition" and $d.type != "TextParameterDefinition" and $d.type != "ChoiceParameterDefinition" and $d.type != "PasswordParameterDefinition") and (($dpv.value | scalar) | not)) then fail
        else {present:true, value:$dpv.value} end as $default
      | if ($d.type == "ChoiceParameterDefinition") then
          if (($d.choices? | type) != "array" or (($d.choices | length) == 0) or (any($d.choices[]; type != "string")) or (($d.choices | unique | length) != ($d.choices | length))) then fail
          elif ($default.present and (($d.choices | index($default.value)) == null)) then fail
          else $d.choices end
        elif ($d.choices? == null) then []
        elif (($d.choices | type) != "array" or (any($d.choices[]; type != "string")) or (($d.choices | unique | length) != ($d.choices | length))) then fail
        else $d.choices end as $choices
      | {name:$d.name, type:$d.type, description:$d.description, default:$default, choices:$choices};
    def definitions:
      if ((.actions? != null and (.actions | type) != "array") or (.property? != null and (.property | type) != "array")) then fail
      else (((.actions // []) + (.property // []))
        | map(if (type != "object") then fail elif (.parameterDefinitions? == null) then [] elif (.parameterDefinitions | type) != "array" then fail else .parameterDefinitions end)
        | add)
      end;
    if ((.buildable? | type) != "boolean") then fail
    else .buildable as $buildable
    | definitions as $raw
    | if ($raw | length) == 0 then fail else $raw end
    | map(normalize)
    | group_by(.name)
    | map(.[0] as $first | if (length == 1) then $first elif (.[1:] | all(. == $first)) then $first else fail end)
    | sort_by(.name)
    | map(if (.name | test("TOKEN|PASSWORD|SECRET|CREDENTIAL|PRIVATE_KEY"; "i")) then .default.value = (if .default.present then "[REDACTED]" else null end) else . end)
    | {job:$job, buildable:$buildable, parameters:.}
    end
  ' "$response" > "$tmp" 2>/dev/null; then
    rm -f "$response" "$tmp" >/dev/null 2>&1 || true
    _jenkins_error "Jenkins parameter definitions are malformed"
    return "$EXIT_JENKINS"
  fi
  chmod 600 "$tmp" >/dev/null 2>&1 || {
    rm -f "$response" "$tmp" >/dev/null 2>&1 || true
    _jenkins_error "Private temporary output is unavailable"
    return 3
  }
  if ! mv "$tmp" "$outfile" 2>/dev/null; then
    rm -f "$response" "$tmp" >/dev/null 2>&1 || true
    _jenkins_error "Private temporary output is unavailable"
    return 3
  fi
  chmod 600 "$outfile" >/dev/null 2>&1 || return 3
  rm -f "$response" >/dev/null 2>&1 || true
  return 0
}

# Extract exact Terraform control-plane IPv4 assignments into private JSON.
# Usage: extract_controlplane_hosts <console-file> <output-file> <alias> <build>
extract_controlplane_hosts() {
  local console_file=$1 output_file=$2 alias=$3 build=$4
  require_command jq || return $?
  require_command chmod || return $?
  if [ ! -f "$console_file" ] || [ ! -r "$console_file" ] || [ -z "$output_file" ]; then
    _jenkins_error "Private console evidence is unavailable"
    return "$EXIT_ENV"
  fi
  if ! jq -R -s -S --arg job "$alias" --argjson build "$build" '
    [ split("\n")[]
      | select(test("^controlplane_public_ip = \"[0-9]+(\\.[0-9]+){3}\"$"))
      | capture("^controlplane_public_ip = \"(?<ip>[0-9]+(\\.[0-9]+){3})\"$").ip as $ip
      | ($ip | split(".") | map(tonumber)) as $parts
      | select(($parts | length) == 4 and all($parts[]; . >= 0 and . <= 255))
      | {ip:$ip, parts:$parts}
    ]
    | sort_by(.parts)
    | unique_by(.parts)
    | {job:$job, build:$build, hosts:map(.ip)}
  ' "$console_file" > "$output_file" 2>/dev/null; then
    rm -f "$output_file" >/dev/null 2>&1 || true
    _jenkins_error "Jenkins console evidence is malformed"
    return "$EXIT_JENKINS"
  fi
  if ! chmod 600 "$output_file" >/dev/null 2>&1; then
    rm -f "$output_file" >/dev/null 2>&1 || true
    _jenkins_error "Private temporary output is unavailable"
    return "$EXIT_ENV"
  fi
}
