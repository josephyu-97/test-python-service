#!/usr/bin/env bats

load helpers

TESTS_DIR=library
BATS_TESTS_DIR=test/bats
WAIT_TIME=300
SLEEP_TIME=5
READINESS_SLEEP_TIME=0.2

EXPECTED_POLICY_COUNT=49
EXPECTED_CONSTRAINT_COUNT=69
EXPECTED_INVENTORY_COUNT=21
EXPECTED_ALLOWED_COUNT=89
EXPECTED_DISALLOWED_COUNT=91
CLEAN_CMD="echo cleaning..."

teardown() {
  bash -c "${CLEAN_CMD}"
  kubectl delete constrainttemplate --all
}

setup() {
  kubectl config set-context --current --namespace default
}

@test "all policies are listed in kustomization.yaml" {
  pushd library/general/
  kustomize edit add resource $(find ./ -type d -maxdepth 1 -mindepth 1 -exec basename {} \;)
  run git diff --quiet kustomization.yaml
  assert_success
  popd

  pushd library/pod-security-policy/
  kustomize edit add resource $(find ./ -type d -maxdepth 1 -mindepth 1 -exec basename {} \;)
  run git diff --quiet kustomization.yaml
  assert_success
  popd
}

@test "gatekeeper-controller-manager is running" {
  wait_for_process ${WAIT_TIME} ${SLEEP_TIME} "kubectl -n gatekeeper-system wait --for=condition=Ready --timeout=60s pod -l control-plane=controller-manager"
}

@test "gatekeeper-audit is running" {
  wait_for_process ${WAIT_TIME} ${SLEEP_TIME} "kubectl -n gatekeeper-system wait --for=condition=Ready --timeout=60s pod -l control-plane=audit-controller"
}

@test "namespace label webhook is serving" {
  cert=$(mktemp)
  CLEAN_CMD="${CLEAN_CMD}; rm ${cert}"
  wait_for_process ${WAIT_TIME} ${SLEEP_TIME} "get_ca_cert ${cert}"

  kubectl run temp --image=curlimages/curl -- tail -f /dev/null
  kubectl wait --for=condition=Ready --timeout=60s pod temp
  kubectl cp ${cert} temp:/tmp/cacert

  wait_for_process ${WAIT_TIME} ${SLEEP_TIME} "kubectl exec -it temp -- curl -f --cacert /tmp/cacert --connect-timeout 1 --max-time 2  https://gatekeeper-webhook-service.gatekeeper-system.svc:443/v1/admitlabel"
  kubectl delete pod temp
}

@test "constrainttemplates crd is established" {
  wait_for_process ${WAIT_TIME} ${SLEEP_TIME} "kubectl wait --for condition=established --timeout=60s crd/constrainttemplates.templates.gatekeeper.sh"
}

@test "waiting for validating webhook" {
  wait_for_process ${WAIT_TIME} ${SLEEP_TIME} "kubectl get validatingwebhookconfigurations.admissionregistration.k8s.io gatekeeper-validating-webhook-configuration"
}

@test "unset default storageclasses so tests function properly" {
  kubectl get storageclass --no-headers=true -o custom-columns=":metadata.name" | while read line; do
    kubectl annotate storageclass $line storageclass.kubernetes.io/is-default-class-
  done
}

@test "applying sync config" {
  kubectl apply -f ${BATS_TESTS_DIR}/sync.yaml
}

@test "waiting for namespaces to be synced using metrics endpoint" {
  kubectl run temp --image=curlimages/curl -- tail -f /dev/null
  kubectl wait --for=condition=Ready --timeout=60s pod temp

  num_namespaces=$(kubectl get ns -o json | jq '.items | length')
  local pod_ip="$(kubectl -n gatekeeper-system get pod -l gatekeeper.sh/operation=webhook -ojson | jq --raw-output '[.items[].status.podIP][0]' | sed 's#\.#-#g')"
  wait_for_process ${WAIT_TIME} ${SLEEP_TIME} "kubectl exec -it temp -- curl http://${pod_ip}.gatekeeper-system.pod:8888/metrics | grep 'gatekeeper_sync{kind=\"Namespace\",status=\"active\"} ${num_namespaces}'"
  kubectl delete pod temp
}

@test "testing constraint templates" {
  local discovered_policies
  local discovered_constraints
  local discovered_inventory
  local discovered_allowed
  local discovered_disallowed
  local attempted_policies=0
  local attempted_constraints=0
  local attempted_inventory=0
  local attempted_allowed=0
  local attempted_disallowed=0

  discovered_policies=$(find "$TESTS_DIR" -mindepth 2 -maxdepth 2 -type d | wc -l | tr -d '[:space:]')
  discovered_constraints=$(find "$TESTS_DIR" -type f -path '*/samples/*/constraint.yaml' | wc -l | tr -d '[:space:]')
  discovered_inventory=$(find "$TESTS_DIR" -type f -path '*/samples/*/example_inventory*.yaml' | wc -l | tr -d '[:space:]')
  discovered_allowed=$(find "$TESTS_DIR" -type f -path '*/samples/*/example_allowed*.yaml' | wc -l | tr -d '[:space:]')
  discovered_disallowed=$(find "$TESTS_DIR" -type f -path '*/samples/*/example_disallowed*.yaml' | wc -l | tr -d '[:space:]')

  echo "discovered fixtures: policies=${discovered_policies}, constraints=${discovered_constraints}, inventory=${discovered_inventory}, allowed=${discovered_allowed}, disallowed=${discovered_disallowed}"
  assert_equal "$EXPECTED_POLICY_COUNT" "$discovered_policies"
  assert_equal "$EXPECTED_CONSTRAINT_COUNT" "$discovered_constraints"
  assert_equal "$EXPECTED_INVENTORY_COUNT" "$discovered_inventory"
  assert_equal "$EXPECTED_ALLOWED_COUNT" "$discovered_allowed"
  assert_equal "$EXPECTED_DISALLOWED_COUNT" "$discovered_disallowed"

  # Keep one authenticated API connection available for the many readiness
  # observations instead of starting two kubectl clients for every attempt.
  local proxy_log="${BATS_TEST_TMPDIR}/kubectl-proxy.log"
  kubectl proxy --port=8001 >"$proxy_log" 2>&1 &
  local proxy_pid=$!
  CLEAN_CMD="${CLEAN_CMD}; kill ${proxy_pid} 2>/dev/null || true"
  wait_for_process 10 ${READINESS_SLEEP_TIME} "curl -fsS http://127.0.0.1:8001/version >/dev/null"
  export KUBERNETES_API_PROXY=http://127.0.0.1:8001

  # Templates do not enforce anything without constraints. Install the verified
  # kustomization once so Gatekeeper can reconcile them in parallel, while the
  # loop below still exercises every policy and its constraints in isolation.
  wait_for_process ${WAIT_TIME} ${SLEEP_TIME} "kubectl apply -k $TESTS_DIR"

  for policy in "$TESTS_DIR"/*/*; do
    if [ -d "$policy" ]; then
      local policy_group=$(basename "$(dirname "$policy")")
      local template_name=$(basename "$policy")
      echo "running integration test against policy group: $policy_group, constraint template: $template_name"
      attempted_policies=$((attempted_policies + 1))
      local kind=$(yq e .metadata.name "$policy"/template.yaml)
      for sample in "$policy"/samples/*; do
        echo "testing sample constraint: $(basename "$sample")"

        # Inventory describes pre-existing cluster state and must not be
        # rejected by the constraint it is intended to exercise. A single
        # kubectl process can safely create all inventory for this sample.
        local -a inventory_arguments=()
        for inventory in "$sample"/example_inventory*.yaml; do
          if [[ -e "$inventory" ]]; then
            attempted_inventory=$((attempted_inventory + 1))
            inventory_arguments+=( -f "$inventory" )
          fi
        done
        if ((${#inventory_arguments[@]} > 0)); then
          run kubectl apply "${inventory_arguments[@]}"
          assert_success
          local inventory_created_count
          inventory_created_count=$(grep -cE ' created$' <<<"$output")
          assert_equal "$((${#inventory_arguments[@]} / 2))" "$inventory_created_count"
        fi

        # Apply one constraint at a time so policy assertions remain isolated.
        attempted_constraints=$((attempted_constraints + 1))
        wait_for_process ${WAIT_TIME} ${SLEEP_TIME} "kubectl apply -f ${sample}/constraint.yaml"
        local name=$(yq e .metadata.name "$sample"/constraint.yaml)
        wait_for_process ${WAIT_TIME} ${READINESS_SLEEP_TIME} "constraint_enforced $kind $name"

        # Server-side preflights are independent once readiness is established.
        # Run them concurrently, recording one status per fixture, then retain
        # the existing per-fixture create/deny assertions below.
        local preflight_dir="${BATS_TEST_TMPDIR}/preflight-${attempted_constraints}"
        local allowed_index=0
        local disallowed_index=0
        mkdir -p "$preflight_dir"
        for allowed in "$sample"/example_allowed*.yaml; do
          if [[ -e "$allowed" ]]; then
            attempted_allowed=$((attempted_allowed + 1))
            (
              if kubectl apply -f "$allowed" --dry-run=server &> /dev/null; then
                printf '0\n'
              else
                printf '%s\n' "$?"
              fi
            ) >"${preflight_dir}/allowed-${allowed_index}" &
            allowed_index=$((allowed_index + 1))
          fi
        done
        for disallowed in "$sample"/example_disallowed*.yaml; do
          if [[ -e "$disallowed" ]]; then
            attempted_disallowed=$((attempted_disallowed + 1))
            (
              if kubectl apply -f "$disallowed" --dry-run=server &> /dev/null; then
                printf '0\n'
              else
                printf '%s\n' "$?"
              fi
            ) >"${preflight_dir}/disallowed-${disallowed_index}" &
            disallowed_index=$((disallowed_index + 1))
          fi
        done
        wait

        local -a pending_allowed=()
        allowed_index=0
        for allowed in "$sample"/example_allowed*.yaml; do
          if [[ -e "$allowed" ]]; then
            if [[ "$(<"${preflight_dir}/allowed-${allowed_index}")" == 0 ]]; then
              pending_allowed+=( "$allowed" )
            fi
            allowed_index=$((allowed_index + 1))
          fi
        done

        # Apply resources with distinct identities together. Duplicate fixture
        # identities are assigned to later waves so every create retains the
        # existing "created" assertion and deletion cleanup.
        while ((${#pending_allowed[@]} > 0)); do
          local -A allowed_wave_identities=()
          local -a allowed_wave=()
          local -a next_allowed_wave=()
          local allowed_identity
          for allowed in "${pending_allowed[@]}"; do
            manifest_identity allowed_identity "$allowed"
            if [[ -v "allowed_wave_identities[$allowed_identity]" ]]; then
              next_allowed_wave+=( "$allowed" )
            else
              allowed_wave_identities["$allowed_identity"]=1
              allowed_wave+=( "$allowed" )
            fi
          done

          local -a allowed_arguments=()
          for allowed in "${allowed_wave[@]}"; do
            echo "Applying ${allowed} with contents:"
            cat "$allowed"
            allowed_arguments+=( -f "$allowed" )
          done
          run kubectl apply "${allowed_arguments[@]}"
          assert_success
          local allowed_created_count
          allowed_created_count=$(grep -cE ' created$' <<<"$output")
          assert_equal "${#allowed_wave[@]}" "$allowed_created_count"
          kubectl delete --ignore-not-found "${allowed_arguments[@]}"
          pending_allowed=( "${next_allowed_wave[@]}" )
        done

        disallowed_index=0
        for disallowed in "$sample"/example_disallowed*.yaml; do
          if [[ -e "$disallowed" ]]; then
            if [[ "$(<"${preflight_dir}/disallowed-${disallowed_index}")" == 0 ]]; then
              echo "Applying ${disallowed} with contents:"
              cat ${disallowed}
              run kubectl apply -f "$disallowed"
              assert_match_either 'denied the request' 'no matches for kind' "${output}"
              assert_failure
              # delete resource
              run kubectl delete --ignore-not-found -f "$disallowed"
            fi
            disallowed_index=$((disallowed_index + 1))
          fi
        done
        rm -rf "$preflight_dir"

        # delete inventory resources
        if ((${#inventory_arguments[@]} > 0)); then
          kubectl delete --ignore-not-found "${inventory_arguments[@]}"
        fi

        # delete constraint
        wait_for_process ${WAIT_TIME} ${SLEEP_TIME} "kubectl delete -f ${sample}/constraint.yaml"

      done
    fi
  done

  echo "attempted fixtures: policies=${attempted_policies}, constraints=${attempted_constraints}, inventory=${attempted_inventory}, allowed=${attempted_allowed}, disallowed=${attempted_disallowed}"
  assert_equal "$discovered_policies" "$attempted_policies"
  assert_equal "$discovered_constraints" "$attempted_constraints"
  assert_equal "$discovered_inventory" "$attempted_inventory"
  assert_equal "$discovered_allowed" "$attempted_allowed"
  assert_equal "$discovered_disallowed" "$attempted_disallowed"
}
