#!/bin/bash

assert_success() {
  if [[ "$status" != 0 ]]; then
    echo "expected: 0"
    echo "actual: $status"
    echo "output: $output"
    return 1
  fi
}

assert_failure() {
  if [[ "$status" == 0 ]]; then
    echo "expected: non-zero exit code"
    echo "actual: $status"
    echo "output: $output"
    return 1
  fi
}

assert_equal() {
  if [[ "$1" != "$2" ]]; then
    echo "expected: $1"
    echo "actual: $2"
    return 1
  fi
}

assert_not_equal() {
  if [[ "$1" == "$2" ]]; then
    echo "unexpected: $1"
    echo "actual: $2"
    return 1
  fi
}

assert_match() {
  if [[ ! "$2" =~ $1 ]]; then
    echo "expected: $1"
    echo "actual: $2"
    return 1
  fi
}

assert_match_either() {
  if [[ ! ("$3" =~ $1 || "$3" =~ $2 ) ]]; then
    echo "expected: $1 or $2"
    echo "actual: $3"
    return 1
  fi
}

assert_not_match() {
  if [[ "$2" =~ $1 ]]; then
    echo "expected: $1"
    echo "actual: $2"
    return 1
  fi
}

# Store the current time in milliseconds in the variable named by $1. Tests
# replace this function with a deterministic clock.
wait_clock_now() {
  local destination="$1"
  local now

  now="$(date +%s%3N)" || return 1
  [[ "$now" =~ ^[0-9]+$ ]] || return 1
  printf -v "$destination" '%s' "$now"
}

# Sleep for the number of milliseconds in $1. Tests replace this function so
# waiting does not consume wall-clock time.
wait_clock_sleep() {
  local milliseconds="$1"
  local seconds=$((milliseconds / 1000))
  local remainder=$((milliseconds % 1000))

  sleep "$(printf '%d.%03d' "$seconds" "$remainder")"
}

seconds_to_milliseconds() {
  local destination="$1"
  local seconds="$2"
  local whole
  local fraction

  if [[ ! "$seconds" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "invalid duration: ${seconds}" >&2
    return 1
  fi

  whole="${seconds%%.*}"
  if [[ "$seconds" == *.* ]]; then
    fraction="${seconds#*.}000"
    fraction="${fraction:0:3}"
  else
    fraction="000"
  fi

  printf -v "$destination" '%d' "$((10#${whole} * 1000 + 10#${fraction}))"
}

wait_for_process() {
  local wait_time="$1"
  local sleep_time="$2"
  local cmd="$3"
  local timeout_ms
  local interval_ms
  local started_at
  local deadline
  local observation_started
  local now
  local next_observation
  local sleep_ms

  seconds_to_milliseconds timeout_ms "$wait_time" || return 2
  seconds_to_milliseconds interval_ms "$sleep_time" || return 2

  # Readiness must never be observed more than five times per second. Clamp
  # callers to the minimum interval rather than allowing accidental busy loops.
  if ((interval_ms < 200)); then
    interval_ms=200
  fi

  wait_clock_now started_at || return 2
  deadline=$((started_at + timeout_ms))
  now="$started_at"

  while ((now < deadline)); do
    observation_started="$now"
    if eval "$cmd"; then
      # Return on the successful observation; do not add a trailing sleep.
      return 0
    fi

    # Re-read the clock after the command so command execution consumes the
    # timeout and the interval is measured between observation starts.
    wait_clock_now now || return 2
    if ((now >= deadline)); then
      break
    fi

    next_observation=$((observation_started + interval_ms))
    if ((next_observation > deadline)); then
      next_observation="$deadline"
    fi
    if ((now < next_observation)); then
      sleep_ms=$((next_observation - now))
      wait_clock_sleep "$sleep_ms" || return 2
      wait_clock_now now || return 2
    fi
  done

  echo "timed out after ${wait_time}s waiting for: ${cmd}" >&2
  return 1
}

get_ca_cert() {
  destination="$1"
  if [ "$(kubectl get secret -n gatekeeper-system gatekeeper-webhook-server-cert -o jsonpath='{.data.ca\.crt}' | wc -w)" -eq 0 ]; then
    return 1
  fi
  kubectl get secret -n gatekeeper-system gatekeeper-webhook-server-cert -o jsonpath='{.data.ca\.crt}' | base64 -d >"$destination"
}

constraint_status_ready() {
  local pod_list="$1"
  local constraint="$2"
  local summary
  local ready_count
  local pod_count
  local current_pods_match

  # A ready entry must belong to a current webhook pod, have observed the
  # constraint's current generation, include the webhook operation, and report
  # successful enforcement. Requiring the exact current pod ID set prevents
  # duplicate or terminated-pod statuses from satisfying the count by accident.
  if ! summary="$(printf '%s\n%s\n' "$pod_list" "$constraint" | jq -er -s '
    if length != 2 or (.[0] | type) != "object" or (.[1] | type) != "object" then
      error("pod and constraint responses must be JSON objects")
    else
      .[0] as $pods
      | .[1] as $constraint
      | if ($pods.items | type) != "array" then
          error("pod response is missing items")
        elif any($pods.items[]; (.metadata.name | type) != "string" or (.metadata.name | length) == 0) then
          error("pod response contains an item without a name")
        elif ($constraint.metadata.generation | type) != "number" then
          error("constraint response is missing metadata.generation")
        elif (($constraint.status.byPod? // []) | type) != "array" then
          error("constraint status.byPod is not an array")
        else
          ($pods.items | map(.metadata.name)) as $pod_ids
          | ($constraint.status.byPod? // []) as $statuses
          | [
              $statuses[]
              | select(
                  (.id | type) == "string"
                  and (.operations | type) == "array"
                  and (.operations | index("webhook") != null)
                  and .observedGeneration == $constraint.metadata.generation
                  and .enforced == true
                  and ((.errors // []) | type) == "array"
                  and ((.errors // []) | length) == 0
                )
            ] as $ready
          | "\($ready | length)\t\($pod_ids | length)\t\(($ready | map(.id) | sort) == ($pod_ids | sort))"
        end
    end
  ')"; then
    echo "invalid pod or constraint status response"
    return 1
  fi

  IFS=$'\t' read -r ready_count pod_count current_pods_match <<<"$summary"
  echo "ready: ${ready_count}, expected: ${pod_count}"

  if ((pod_count < 1)); then
    echo "Gatekeeper pod count is < 1"
    return 1
  fi

  [[ "$ready_count" -eq "$pod_count" && "$current_pods_match" == "true" ]]
}

manifest_identity() {
  local destination="$1"
  local manifest="$2"
  local api_version=""
  local kind=""
  local name=""
  local namespace="default"
  local in_metadata=false
  local line
  local value

  while IFS= read -r line; do
    case "$line" in
      apiVersion:*)
        api_version="${line#*:}"
        api_version="${api_version#"${api_version%%[![:space:]]*}"}"
        ;;
      kind:*)
        kind="${line#*:}"
        kind="${kind#"${kind%%[![:space:]]*}"}"
        ;;
      metadata:)
        in_metadata=true
        ;;
      '  name:'*|'    name:'*)
        if [[ "$in_metadata" == true ]]; then
          name="${line#*:}"
          name="${name#"${name%%[![:space:]]*}"}"
        fi
        ;;
      '  namespace:'*|'    namespace:'*)
        if [[ "$in_metadata" == true ]]; then
          namespace="${line#*:}"
          namespace="${namespace#"${namespace%%[![:space:]]*}"}"
        fi
        ;;
      [![:space:]]*)
        in_metadata=false
        ;;
    esac
  done <"$manifest"

  if [[ -z "$api_version" || -z "$kind" || -z "$name" ]]; then
    echo "unable to determine resource identity from ${manifest}" >&2
    return 1
  fi

  value="${api_version}/${kind}/${namespace}/${name}"
  printf -v "$destination" '%s' "$value"
}

constraint_get_pods() {
  if [[ -n "${KUBERNETES_API_PROXY:-}" ]]; then
    curl -fsS "${KUBERNETES_API_PROXY}/api/v1/namespaces/gatekeeper-system/pods?labelSelector=gatekeeper.sh%2Foperation%3Dwebhook"
  else
    kubectl -n gatekeeper-system get pod -l gatekeeper.sh/operation=webhook -o json
  fi
}

constraint_get_object() {
  local kind="$1"
  local name="$2"

  if [[ -n "${KUBERNETES_API_PROXY:-}" ]]; then
    curl -fsS "${KUBERNETES_API_PROXY}/apis/constraints.gatekeeper.sh/v1beta1/${kind}/${name}"
  else
    kubectl get "$kind" "$name" -o json
  fi
}

constraint_deleted() {
  local kind="$1"
  local name="$2"
  local manifest="$3"
  local url
  local delete_code
  local get_code

  if [[ -z "${KUBERNETES_API_PROXY:-}" ]]; then
    kubectl delete -f "$manifest"
    return
  fi

  url="${KUBERNETES_API_PROXY}/apis/constraints.gatekeeper.sh/v1beta1/${kind}/${name}"
  if ! delete_code="$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE "$url")"; then
    return 1
  fi
  case "$delete_code" in
    2??|404) ;;
    *) return 1 ;;
  esac

  # Do not let an API error masquerade as absence. Only an explicit 404 means
  # cleanup is complete and the next sample can be isolated safely.
  if ! get_code="$(curl -sS -o /dev/null -w '%{http_code}' "$url")"; then
    return 1
  fi
  if [[ "$get_code" == 404 ]]; then
    echo "constraint ${kind}/${name} deleted"
    return 0
  fi
  return 1
}

constraint_enforced() {
  local kind="$1"
  local name="$2"
  local result_prefix="${TMPDIR:-/tmp}/constraint-enforced-${BASHPID}-${RANDOM}"
  local pods_file="${result_prefix}-pods"
  local constraint_file="${result_prefix}-constraint"
  local pods_pid
  local constraint_pid
  local pods_status
  local constraint_status
  local pod_list
  local cstr

  # These are independent API reads. Run them concurrently to avoid adding
  # their command latencies together on every readiness observation.
  constraint_get_pods >"$pods_file" &
  pods_pid=$!
  constraint_get_object "$kind" "$name" >"$constraint_file" &
  constraint_pid=$!

  if wait "$pods_pid"; then
    pods_status=0
  else
    pods_status=$?
  fi
  if wait "$constraint_pid"; then
    constraint_status=0
  else
    constraint_status=$?
  fi

  if ((pods_status != 0)); then
    rm -f "$pods_file" "$constraint_file"
    echo "error gathering pods"
    return 1
  fi
  if ((constraint_status != 0)); then
    rm -f "$pods_file" "$constraint_file"
    echo "Error gathering constraint ${kind} ${name}"
    return 1
  fi

  pod_list="$(<"$pods_file")"
  cstr="$(<"$constraint_file")"
  rm -f "$pods_file" "$constraint_file"

  echo "checking constraint ${kind} ${name}"
  constraint_status_ready "$pod_list" "$cstr"
}
