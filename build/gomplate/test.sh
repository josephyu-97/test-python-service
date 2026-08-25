#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

readonly image="${1:-gomplate-container}"
expected_platform="${2:-}"
readonly gomplate_version="${GOMPLATE_VERSION:-3.11.6}"
read -r -a docker_command <<< "${DOCKER:-docker}"

fail() {
  echo "generator image test failed: $*" >&2
  exit 1
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local description="$3"

  if [[ "${actual}" != "${expected}" ]]; then
    fail "${description}: expected '${expected}', got '${actual}'"
  fi
}

run_in_image() {
  "${docker_command[@]}" run --rm --network none "${image}" "$@"
}

run_generation() {
  local checkout="$1"
  local uid="$2"
  local gid="$3"

  "${docker_command[@]}" run --rm \
    --network none \
    --user "${uid}:${gid}" \
    --volume "${checkout}:/gatekeeper-library" \
    "${image}" ./scripts/generate.sh
}

expect_build_failure() {
  local expected_message="$1"
  shift
  local log
  log="$(mktemp)"

  if "${docker_command[@]}" build --progress=plain \
    --file "${repo_root}/build/gomplate/Dockerfile" \
    --target gomplate-download \
    "$@" "${repo_root}" >"${log}" 2>&1; then
    cat "${log}" >&2
    rm -f "${log}"
    fail "invalid build unexpectedly succeeded"
  fi
  if ! grep -Fq "${expected_message}" "${log}"; then
    cat "${log}" >&2
    rm -f "${log}"
    fail "failed build did not report '${expected_message}'"
  fi
  rm -f "${log}"
}

expect_generation_failure() {
  local relative_path="$1"
  local expected_message="$2"
  local original="${test_checkout}/${relative_path}"
  local backup="${failure_backup}/missing"
  local output
  local status=0

  mv "${original}" "${backup}"
  output="$(run_generation "${test_checkout}" 12345 23456 2>&1)" || status=$?
  mv "${backup}" "${original}"

  if [[ "${status}" -eq 0 ]]; then
    fail "generation unexpectedly succeeded without ${relative_path}"
  fi
  if ! grep -Fq "${expected_message}" <<<"${output}"; then
    echo "${output}" >&2
    fail "missing ${relative_path} did not report '${expected_message}'"
  fi
}

repo_root="$(git rev-parse --show-toplevel)"
cd "${repo_root}"

if [[ -n "${expected_platform}" ]]; then
  case "${expected_platform}" in
    linux/amd64)
      expected_docker_arch=amd64
      expected_uname=x86_64
      ;;
    linux/arm64)
      expected_docker_arch=arm64
      expected_uname=aarch64
      ;;
    *) fail "unsupported expected test platform ${expected_platform}" ;;
  esac
else
  expected_platform="$("${docker_command[@]}" image inspect --format '{{.Os}}/{{.Architecture}}' "${image}")"
  case "${expected_platform}" in
    linux/amd64)
      expected_docker_arch=amd64
      expected_uname=x86_64
      ;;
    linux/arm64)
      expected_docker_arch=arm64
      expected_uname=aarch64
      ;;
    *) fail "image has unsupported platform ${expected_platform}" ;;
  esac
fi
readonly expected_docker_arch expected_uname

actual_platform="$("${docker_command[@]}" image inspect --format '{{.Os}}/{{.Architecture}}' "${image}")"
assert_equal "${expected_platform}" "${actual_platform}" "image platform"
assert_equal "${expected_uname}" "$(run_in_image -c 'uname -m')" "runtime architecture"
assert_equal '["/bin/bash"]' "$("${docker_command[@]}" image inspect --format '{{json .Config.Entrypoint}}' "${image}")" "image entrypoint"
assert_equal "${gomplate_version}" "$("${docker_command[@]}" image inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "${image}")" "image version label"
assert_equal "gomplate version ${gomplate_version}" "$(run_in_image -c 'gomplate --version')" "Gomplate version"

checksum_file="build/gomplate/checksums/gomplate-v${gomplate_version}-linux-${expected_docker_arch}.sha256"
[[ -f "${checksum_file}" ]] || fail "missing ${checksum_file}"
artifact="gomplate_linux-${expected_docker_arch}"
expected_checksum="$(awk -v artifact="${artifact}" '$2 == artifact { print $1 }' "${checksum_file}")"
[[ "${expected_checksum}" =~ ^[0-9a-f]{64}$ ]] || fail "invalid checksum in ${checksum_file}"
actual_checksum="$(run_in_image -c 'sha256sum /usr/local/bin/gomplate' | awk '{ print $1 }')"
assert_equal "${expected_checksum}" "${actual_checksum}" "Gomplate binary checksum"

# The single quotes deliberately defer expansion to Bash in the image.
# shellcheck disable=SC2016
run_in_image -c '
  set -eu
  for utility in bash find dirname mkdir gomplate; do
    command -v "${utility}" >/dev/null || {
      echo "missing runtime utility: ${utility}" >&2
      exit 1
    }
  done
  if command -v go >/dev/null || [ -e /usr/local/go/bin/go ] || [ -e /usr/bin/go ]; then
    echo "Go toolchain must not be installed" >&2
    exit 1
  fi
  help="$(gomplate --help 2>&1)"
  for option in --datasource --plugin --input-dir --exec-pipe; do
    echo "${help}" | grep -q -- "${option}" || {
      echo "full Gomplate option is unavailable: ${option}" >&2
      exit 1
    }
  done
'

readonly max_image_size=$((80 * 1024 * 1024))
image_size="$("${docker_command[@]}" image inspect --format '{{.Size}}' "${image}")"
[[ "${image_size}" =~ ^[0-9]+$ ]] || fail "invalid image size '${image_size}'"
if (( image_size > max_image_size )); then
  fail "image is ${image_size} bytes; limit is ${max_image_size} bytes (80 MiB)"
fi
printf 'Image contract: %s, %s bytes, Gomplate %s\n' "${actual_platform}" "${image_size}" "${gomplate_version}"

expect_build_failure \
  "unsupported target platform linux/mips64; supported platforms: linux/amd64, linux/arm64" \
  --build-arg TARGETOS=linux --build-arg TARGETARCH=mips64
expect_build_failure \
  "no committed checksum for gomplate v0.0.0 on linux/${expected_docker_arch}" \
  --build-arg GOMPLATE_VERSION=0.0.0 \
  --build-arg TARGETOS=linux --build-arg "TARGETARCH=${expected_docker_arch}"

mapfile -t tracked_templates < <(git ls-files | grep '^library/.*/template\.yaml$')
assert_equal 49 "${#tracked_templates[@]}" "tracked template count"
if ! git diff --exit-code; then
  fail "the checkout must be clean before the generation contract test"
fi

# This is the same bind-mount and numeric host identity used by make generate,
# with networking disabled to make the offline contract explicit.
run_generation "${repo_root}" "$(id -u)" "$(id -g)"
if ! git diff --exit-code; then
  fail "generation changed tracked output"
fi

# A UID/GID absent from the image's passwd/group files must also work when the
# mounted checkout is writable by that numeric identity.
test_checkout="$(mktemp -d)"
failure_backup="$(mktemp -d)"
trap 'rm -rf "${test_checkout}" "${failure_backup}"' EXIT
git archive --format=tar HEAD | tar -xf - -C "${test_checkout}"
chmod -R a+rwX "${test_checkout}"
run_generation "${test_checkout}" 12345 23456
for template in "${tracked_templates[@]}"; do
  cmp "${repo_root}/${template}" "${test_checkout}/${template}" || \
    fail "arbitrary-UID generation changed ${template}"
done

expect_generation_failure \
  library/general/allowedrepos/kustomization.yaml \
  "library/general/allowedrepos/kustomization.yaml is missing"
expect_generation_failure \
  library/general/allowedrepos/suite.yaml \
  "library/general/allowedrepos/suite.yaml is missing"
expect_generation_failure \
  library/general/allowedrepos/samples \
  "library/general/allowedrepos/samples is missing"
expect_generation_failure \
  src/general/allowedrepos \
  "library/general/allowedrepos is missing the corresponding src/general/allowedrepos folder"
# Gomplate reads src.rego while rendering, so it reports the missing path
# before generate.sh reaches its explicit required-file checks.
expect_generation_failure \
  src/general/allowedrepos/src.rego \
  "src/general/allowedrepos/src.rego"
for source_file in src_test.rego constraint.tmpl; do
  expect_generation_failure \
    "src/general/allowedrepos/${source_file}" \
    "src/general/allowedrepos/${source_file} is missing"
done

echo "Generator image regression checks passed for ${actual_platform}."
