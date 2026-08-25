package k8sdisallowedtags

test_input_allowed_container {
    inp := { "review": input_review(input_container_allowed), "parameters": {"tags": ["latest", "testing"]}}
    results := violation with input as inp
    count(results) == 0
}
test_input_allowed_dual_container {
    inp := { "review": input_review(input_container_dual_allowed), "parameters": {"tags": ["latest", "testing"]}}
    results := violation with input as inp
    count(results) == 0
}
test_input_denied_container_emtpy {
    inp := { "review": input_review(input_container_denied_empty), "parameters": {"tags": ["latest", "testing"]}}
    results := violation with input as inp
    count(results) == 1
}
test_input_denied_container_empty_with_port {
    inp := { "review": input_review(input_container_denied_empty_with_port), "parameters": {"tags": ["latest", "testing"]}}
    results := violation with input as inp
    count(results) == 1
}
test_input_denied_container_latest {
    inp := { "review": input_review(input_container_denied_latest), "parameters": {"tags": ["latest", "testing"]}}
    results := violation with input as inp
    count(results) == 1
}
test_input_denied_container_testing {
    inp := { "review": input_review(input_container_denied_testing), "parameters": {"tags": ["latest", "testing"]}}
    results := violation with input as inp
    count(results) == 1
}
test_input_denied_dual_container_empty_tag {
    inp := { "review": input_review(array.concat(input_container_denied_empty, input_container_denied_latest)), "parameters": {"tags": ["latest", "testing"]}}
    results := violation with input as inp
    count(results) == 2
}
test_input_denied_dual_container_2tags {
    inp := { "review": input_review(array.concat(input_container_denied_testing, input_container_denied_latest)), "parameters": {"tags": ["latest", "testing"]}}
    results := violation with input as inp
    count(results) == 2
}
test_input_denied_mixed_container_empty {
    inp := { "review": input_review(array.concat(input_container_allowed, input_container_denied_empty)), "parameters": {"tags": ["latest", "testing"]}}
    results := violation with input as inp
    count(results) == 1
}
test_input_denied_mixed_container_latest {
    inp := { "review": input_review(array.concat(input_container_allowed, input_container_denied_latest)), "parameters": {"tags": ["latest", "testing"]}}
    results := violation with input as inp
    count(results) == 1
}

# init containers
test_input_allowed_container {
    inp := { "review": input_init_review(input_container_allowed), "parameters": {"tags": ["latest", "testing"]}}
    results := violation with input as inp
    count(results) == 0
}
test_input_allowed_dual_container {
    inp := { "review": input_init_review(input_container_dual_allowed), "parameters": {"tags": ["latest", "testing"]}}
    results := violation with input as inp
    count(results) == 0
}
test_input_denied_container_emtpy {
    inp := { "review": input_init_review(input_container_denied_empty), "parameters": {"tags": ["latest", "testing"]}}
    results := violation with input as inp
    count(results) == 1
}
test_input_denied_container_latest {
    inp := { "review": input_init_review(input_container_denied_latest), "parameters": {"tags": ["latest", "testing"]}}
    results := violation with input as inp
    count(results) == 1
}
test_input_denied_container_testing {
    inp := { "review": input_init_review(input_container_denied_testing), "parameters": {"tags": ["latest", "testing"]}}
    results := violation with input as inp
    count(results) == 1
}
test_input_denied_dual_container_empty_tag {
    inp := { "review": input_init_review(array.concat(input_container_denied_empty, input_container_denied_latest)), "parameters": {"tags": ["latest", "testing"]}}
    results := violation with input as inp
    count(results) == 2
}
test_input_denied_dual_container_2tags {
    inp := { "review": input_init_review(array.concat(input_container_denied_testing, input_container_denied_latest)), "parameters": {"tags": ["latest", "testing"]}}
    results := violation with input as inp
    count(results) == 2
}
test_input_denied_mixed_container_empty {
    inp := { "review": input_init_review(array.concat(input_container_allowed, input_container_denied_empty)), "parameters": {"tags": ["latest", "testing"]}}
    results := violation with input as inp
    count(results) == 1
}
test_input_denied_mixed_container_latest {
    inp := { "review": input_init_review(array.concat(input_container_allowed, input_container_denied_latest)), "parameters": {"tags": ["latest", "testing"]}}
    results := violation with input as inp
    count(results) == 1
}
test_input_denied_mixed_container_with_some_exempt_image {
    inp := { "review": input_init_review(array.concat(input_container_exempt, input_container_denied_latest)), "parameters": {"tags": ["latest", "testing"], "exemptImages": ["exempt:latest"]}}
    results := violation with input as inp
    count(results) == 2
}
test_input_denied_dual_container_with_all_exempt_image {
    inp := { "review": input_init_review(array.concat(input_container_exempt, input_container_denied_latest)), "parameters": {"tags": ["latest", "testing"], "exemptImages": ["exempt:latest", "exempt:testing"]}}
    results := violation with input as inp
    count(results) == 1
}
test_input_allowed_dual_container_with_exempt_image {
    inp := { "review": input_init_review(input_container_exempt), "parameters": {"tags": ["latest", "testing"], "exemptImages": ["exempt:latest", "exempt:testing"]}}
    results := violation with input as inp
    count(results) == 0
}

input_review(containers) = output {
    output = {
      "object": {
        "metadata": {
            "name": "nginx"
        },
        "spec": {
            "containers": containers,
        }
      }
     }
}

input_init_review(containers) = output {
    output = {
      "object": {
        "metadata": {
            "name": "nginx"
        },
        "spec": {
            "initContainers": containers,
        }
      }
     }
}

input_container_allowed = [
{
    "name": "nginx",
    "image": "nginx:1.0.0",
}]

input_container_denied_empty = [
{
    "name": "nginx",
    "image": "nginx",
}]

input_container_denied_empty_with_port = [
{
    "name": "nginx",
    "image": "nginx:443/nginx",
}] 

input_container_denied_latest = [
{
    "name": "nginx",
    "image": "nginx:latest",
}]


input_container_denied_testing = [
{
    "name": "other",
    "image": "other:testing",
}]

input_container_dual_allowed = [
{
    "name": "nginx",
    "image": "nginx:1.0.0",
},
{
    "name": "other",
    "image": "other:2.0.0",
}]
input_container_exempt = [
{
    "name": "exempt",
    "image": "exempt:latest",
}, {
    "name": "exempt",
    "image": "exempt:testing",
}]

# Image reference parsing

test_tagged_digest_disallowed_for_all_container_types {
    image := "host:5000/team/app:latest@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    inp := {"review": input_all_container_types(image, "tagged-digest"), "parameters": {"tags": ["latest"]}}
    results := violation with input as inp

    count(results) == 3
    matching_result_count(results, "uses a disallowed tag") == 3
    matching_result_count(results, "didn't specify an image tag") == 0
    matching_result_count(results, "container <regular-tagged-digest> uses a disallowed tag") == 1
    matching_result_count(results, "container <init-tagged-digest> uses a disallowed tag") == 1
    matching_result_count(results, "container <ephemeral-tagged-digest> uses a disallowed tag") == 1
}

test_digest_only_missing_tag_for_all_container_types {
    image := "host:5000/team/app@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    inp := {"review": input_all_container_types(image, "digest-only"), "parameters": {"tags": ["latest"]}}
    results := violation with input as inp

    count(results) == 3
    matching_result_count(results, "didn't specify an image tag") == 3
    matching_result_count(results, "uses a disallowed tag") == 0
    matching_result_count(results, "container <regular-digest-only> didn't specify an image tag") == 1
    matching_result_count(results, "container <init-digest-only> didn't specify an image tag") == 1
    matching_result_count(results, "container <ephemeral-digest-only> didn't specify an image tag") == 1
}

test_permitted_tags_with_and_without_digests {
    containers := [
        {"name": "permitted", "image": "host:5000/team/app:1.2.3"},
        {"name": "permitted-digest", "image": "host:5000/team/app:1.2.3@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"},
        {"name": "not-latest", "image": "app:notlatest"},
        {"name": "latest-extra", "image": "app:latest-extra"},
        {"name": "case-sensitive", "image": "app:Latest"},
    ]
    inp := {"review": input_review(containers), "parameters": {"tags": ["latest"]}}
    results := violation with input as inp

    count(results) == 0
}

test_untagged_image_after_registry_port_is_missing_tag {
    containers := [{"name": "untagged", "image": "host:5000/team/app"}]
    inp := {"review": input_review(containers), "parameters": {"tags": ["latest"]}}
    results := violation with input as inp

    count(results) == 1
    matching_result_count(results, "didn't specify an image tag") == 1
    matching_result_count(results, "uses a disallowed tag") == 0
}

test_exact_and_wildcard_exempt_digest_references {
    exact_image := "host:5000/team/exact:latest@sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
    wildcard_image := "host:5000/team/wild@sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    containers := [
        {"name": "exact-exempt", "image": exact_image},
        {"name": "wildcard-exempt", "image": wildcard_image},
    ]
    inp := {
        "review": input_review(containers),
        "parameters": {
            "tags": ["latest"],
            "exemptImages": [exact_image, "host:5000/team/wild@sha256:*"],
        },
    }
    results := violation with input as inp

    count(results) == 0
}

matching_result_count(results, message) = n {
    matches := [result | result := results[_]; contains(result.msg, message)]
    n := count(matches)
}

input_all_container_types(image, reference_type) = output {
    output := {"object": {
        "metadata": {"name": "image-reference-parsing"},
        "spec": {
            "containers": [{"name": sprintf("regular-%s", [reference_type]), "image": image}],
            "initContainers": [{"name": sprintf("init-%s", [reference_type]), "image": image}],
            "ephemeralContainers": [{"name": sprintf("ephemeral-%s", [reference_type]), "image": image}],
        },
    }}
}
