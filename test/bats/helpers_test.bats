#!/usr/bin/env bats

load helpers

setup() {
  fake_now_ms=0
  observations=0
  sleep_calls=0
  artificial_sleep_ms=0

  pods_json='{"items":[{"metadata":{"name":"webhook-a"}},{"metadata":{"name":"webhook-b"}}]}'
  constraint_json='{"metadata":{"generation":4},"status":{"byPod":[{"id":"webhook-a","observedGeneration":4,"operations":["webhook"],"enforced":true},{"id":"webhook-b","observedGeneration":4,"operations":["audit","webhook"],"enforced":true}]}}'
  pods_api_status=0
  constraint_api_status=0
}

wait_clock_now() {
  printf -v "$1" '%d' "$fake_now_ms"
}

wait_clock_sleep() {
  sleep_calls=$((sleep_calls + 1))
  artificial_sleep_ms=$((artificial_sleep_ms + $1))
  fake_now_ms=$((fake_now_ms + $1))
}

succeed_immediately() {
  observations=$((observations + 1))
  return 0
}

succeed_on_second_observation() {
  observations=$((observations + 1))
  ((observations >= 2))
}

succeed_on_third_observation() {
  observations=$((observations + 1))
  ((observations >= 3))
}

always_fail() {
  observations=$((observations + 1))
  return 1
}

slow_failure() {
  observations=$((observations + 1))
  fake_now_ms=$((fake_now_ms + 350))
  return 1
}

curl() {
  local url="${*: -1}"

  if [[ "$url" == *"/api/v1/namespaces/gatekeeper-system/pods?"* ]]; then
    if ((pods_api_status != 0)); then
      echo "pod API unavailable" >&2
      return "$pods_api_status"
    fi
    printf '%s\n' "$pods_json"
    return 0
  fi

  if [[ "$url" == *"/apis/constraints.gatekeeper.sh/v1beta1/ExampleConstraint/example" ]]; then
    if ((constraint_api_status != 0)); then
      echo "constraint API unavailable" >&2
      return "$constraint_api_status"
    fi
    printf '%s\n' "$constraint_json"
    return 0
  fi

  echo "unexpected curl arguments: $*" >&2
  return 99
}

kubectl() {
  if [[ " $* " == *" get pod "* ]]; then
    if ((pods_api_status != 0)); then
      echo "pod API unavailable" >&2
      return "$pods_api_status"
    fi
    printf '%s\n' "$pods_json"
    return 0
  fi

  if [[ " $* " == *" get ExampleConstraint example "* ]]; then
    if ((constraint_api_status != 0)); then
      echo "constraint API unavailable" >&2
      return "$constraint_api_status"
    fi
    printf '%s\n' "$constraint_json"
    return 0
  fi

  echo "unexpected kubectl arguments: $*" >&2
  return 99
}

@test "wait_for_process returns after one successful observation without sleeping" {
  wait_for_process 1 0.2 succeed_immediately

  assert_equal 1 "$observations"
  assert_equal 0 "$sleep_calls"
  assert_equal 0 "$fake_now_ms"
}

@test "wait_for_process returns immediately after a delayed successful observation" {
  wait_for_process 1 0.2 succeed_on_second_observation

  assert_equal 2 "$observations"
  assert_equal 1 "$sleep_calls"
  assert_equal 200 "$fake_now_ms"
}

@test "wait_for_process retries transient command failures" {
  wait_for_process 1 0.2 succeed_on_third_observation

  assert_equal 3 "$observations"
  assert_equal 2 "$sleep_calls"
  assert_equal 400 "$fake_now_ms"
}

@test "wait_for_process returns failure at the configured deadline" {
  if wait_for_process 1 0.2 always_fail; then
    echo "permanent failure unexpectedly succeeded"
    return 1
  fi

  assert_equal 5 "$observations"
  assert_equal 1000 "$fake_now_ms"
}

@test "wait_for_process counts command execution time toward its deadline" {
  if wait_for_process 1 0.2 slow_failure; then
    echo "permanent failure unexpectedly succeeded"
    return 1
  fi

  assert_equal 3 "$observations"
  assert_equal 0 "$sleep_calls"
  assert_equal 1050 "$fake_now_ms"
}

@test "wait_for_process limits observations and delays second-observation success by at most 500ms" {
  wait_for_process 1 0.001 succeed_on_second_observation

  assert_equal 2 "$observations"
  assert_equal 1 "$sleep_calls"
  [[ "$artificial_sleep_ms" -ge 200 ]]
  [[ "$artificial_sleep_ms" -le 500 ]]
}

@test "constraint_enforced accepts complete current-generation webhook status" {
  run constraint_enforced ExampleConstraint example

  assert_success
  assert_match 'ready: 2, expected: 2' "$output"
}

@test "constraint_enforced rejects stale generations" {
  constraint_json='{"metadata":{"generation":4},"status":{"byPod":[{"id":"webhook-a","observedGeneration":3,"operations":["webhook"],"enforced":true},{"id":"webhook-b","observedGeneration":3,"operations":["webhook"],"enforced":true}]}}'

  run constraint_enforced ExampleConstraint example

  assert_failure
  assert_match 'ready: 0, expected: 2' "$output"
}

@test "constraint_enforced rejects audit-only status" {
  constraint_json='{"metadata":{"generation":4},"status":{"byPod":[{"id":"webhook-a","observedGeneration":4,"operations":["audit"],"enforced":true},{"id":"webhook-b","observedGeneration":4,"operations":["audit"],"enforced":true}]}}'

  run constraint_enforced ExampleConstraint example

  assert_failure
  assert_match 'ready: 0, expected: 2' "$output"
}

@test "constraint_enforced rejects incomplete webhook status" {
  constraint_json='{"metadata":{"generation":4},"status":{"byPod":[{"id":"webhook-a","observedGeneration":4,"operations":["webhook"],"enforced":true}]}}'

  run constraint_enforced ExampleConstraint example

  assert_failure
  assert_match 'ready: 1, expected: 2' "$output"
}

@test "constraint_enforced rejects current entries that are not enforced" {
  constraint_json='{"metadata":{"generation":4},"status":{"byPod":[{"id":"webhook-a","observedGeneration":4,"operations":["webhook"],"enforced":true},{"id":"webhook-b","observedGeneration":4,"operations":["webhook"],"enforced":false}]}}'

  run constraint_enforced ExampleConstraint example

  assert_failure
  assert_match 'ready: 1, expected: 2' "$output"
}

@test "constraint_enforced rejects current entries with enforcement errors" {
  constraint_json='{"metadata":{"generation":4},"status":{"byPod":[{"id":"webhook-a","observedGeneration":4,"operations":["webhook"],"enforced":true},{"id":"webhook-b","observedGeneration":4,"operations":["webhook"],"enforced":true,"errors":[{"message":"failed to cache constraint"}]}]}}'

  run constraint_enforced ExampleConstraint example

  assert_failure
  assert_match 'ready: 1, expected: 2' "$output"
}

@test "constraint_enforced rejects statuses for non-current webhook pods" {
  constraint_json='{"metadata":{"generation":4},"status":{"byPod":[{"id":"webhook-a","observedGeneration":4,"operations":["webhook"],"enforced":true},{"id":"terminated-webhook","observedGeneration":4,"operations":["webhook"],"enforced":true}]}}'

  run constraint_enforced ExampleConstraint example

  assert_failure
  assert_match 'ready: 2, expected: 2' "$output"
}

@test "constraint_enforced rejects missing status" {
  constraint_json='{"metadata":{"generation":4}}'

  run constraint_enforced ExampleConstraint example

  assert_failure
  assert_match 'ready: 0, expected: 2' "$output"
}

@test "constraint_enforced rejects pod API errors" {
  pods_api_status=1

  run constraint_enforced ExampleConstraint example

  assert_failure
  assert_match 'error gathering pods' "$output"
}

@test "constraint_enforced rejects constraint API errors" {
  constraint_api_status=1

  run constraint_enforced ExampleConstraint example

  assert_failure
  assert_match 'Error gathering constraint ExampleConstraint example' "$output"
}

@test "constraint_enforced accepts readiness through the persistent API proxy" {
  KUBERNETES_API_PROXY=http://127.0.0.1:8001

  run constraint_enforced ExampleConstraint example

  assert_success
  assert_match 'ready: 2, expected: 2' "$output"
}

@test "constraint_enforced rejects pod API errors through the persistent API proxy" {
  KUBERNETES_API_PROXY=http://127.0.0.1:8001
  pods_api_status=1

  run constraint_enforced ExampleConstraint example

  assert_failure
  assert_match 'error gathering pods' "$output"
}

@test "constraint_enforced rejects constraint API errors through the persistent API proxy" {
  KUBERNETES_API_PROXY=http://127.0.0.1:8001
  constraint_api_status=1

  run constraint_enforced ExampleConstraint example

  assert_failure
  assert_match 'Error gathering constraint ExampleConstraint example' "$output"
}

@test "manifest_identity distinguishes names and defaults namespaces" {
  local first="${BATS_TEST_TMPDIR}/first.yaml"
  local second="${BATS_TEST_TMPDIR}/second.yaml"
  local first_identity
  local second_identity
  cat >"$first" <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: example
spec: {}
YAML
  cat >"$second" <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: other
  namespace: default
spec: {}
YAML

  manifest_identity first_identity "$first"
  manifest_identity second_identity "$second"

  assert_equal "v1/Pod/default/example" "$first_identity"
  assert_equal "v1/Pod/default/other" "$second_identity"
}

@test "manifest_identity rejects a resource without a name" {
  local manifest="${BATS_TEST_TMPDIR}/unnamed.yaml"
  cat >"$manifest" <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  namespace: default
spec: {}
YAML

  run manifest_identity identity "$manifest"

  assert_failure
  assert_match 'unable to determine resource identity' "$output"
}
