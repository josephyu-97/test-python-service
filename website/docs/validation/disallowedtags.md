---
id: disallowedtags
title: Disallow tags
---

# Disallow tags

## Description
Requires container images to have an image tag different from the ones in the specified list.
https://kubernetes.io/docs/concepts/containers/images/#image-names

## Template
```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sdisallowedtags
  annotations:
    metadata.gatekeeper.sh/title: "Disallow tags"
    metadata.gatekeeper.sh/version: 1.0.3
    description: >-
      Requires container images to have an image tag different from the ones in
      the specified list.

      https://kubernetes.io/docs/concepts/containers/images/#image-names
spec:
  crd:
    spec:
      names:
        kind: K8sDisallowedTags
      validation:
        # Schema for the `parameters` field
        openAPIV3Schema:
          type: object
          properties:
            exemptImages:
              description: >-
                Any container that uses an image that matches an entry in this list will be excluded
                from enforcement. Prefix-matching can be signified with `*`. For example: `my-image-*`.
                It is recommended that users use the fully-qualified Docker image name (e.g. start with a domain name)
                in order to avoid unexpectedly exempting images from an untrusted repository.
              type: array
              items:
                type: string
            tags:
              type: array
              description: Disallowed container image tags.
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sdisallowedtags

        import data.lib.exempt_container.is_exempt

        violation[{"msg": msg}] {
            container := input_containers[_]
            not is_exempt(container)
            tag := image_tag(container.image)
            tag == input.parameters.tags[_]
            msg := sprintf("container <%v> uses a disallowed tag <%v>; disallowed tags are %v", [container.name, container.image, input.parameters.tags])
        }

        violation[{"msg": msg}] {
            container := input_containers[_]
            not is_exempt(container)
            not image_tag(container.image)
            msg := sprintf("container <%v> didn't specify an image tag <%v>", [container.name, container.image])
        }

        image_tag(image) = tag {
            image_without_digest := split(image, "@")[0]
            components := split(image_without_digest, "/")
            final_component := components[count(components) - 1]
            tag_parts := split(final_component, ":")
            count(tag_parts) > 1
            tag := tag_parts[count(tag_parts) - 1]
        }

        input_containers[c] {
            c := input.review.object.spec.containers[_]
        }
        input_containers[c] {
            c := input.review.object.spec.initContainers[_]
        }
        input_containers[c] {
            c := input.review.object.spec.ephemeralContainers[_]
        }
      libs:
        - |
          package lib.exempt_container

          is_exempt(container) {
              exempt_images := object.get(object.get(input, "parameters", {}), "exemptImages", [])
              img := container.image
              exemption := exempt_images[_]
              _matches_exemption(img, exemption)
          }

          _matches_exemption(img, exemption) {
              not endswith(exemption, "*")
              exemption == img
          }

          _matches_exemption(img, exemption) {
              endswith(exemption, "*")
              prefix := trim_suffix(exemption, "*")
              startswith(img, prefix)
          }


```

### Usage
```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/disallowedtags/template.yaml
```
## Examples
<details>
<summary>disallowed-tags</summary>

<details>
<summary>constraint</summary>

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDisallowedTags
metadata:
  name: container-image-must-not-have-latest-tag
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces:
      - "default"
  parameters:
    tags: ["latest"]
    exemptImages: ["openpolicyagent/opa-exp:latest", "openpolicyagent/opa-exp2:latest"]

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/disallowedtags/samples/container-image-must-not-have-latest-tag/constraint.yaml
```

</details>

<details>
<summary>allowed</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: opa-allowed
spec:
  containers:
    - name: opa
      image: openpolicyagent/opa:0.9.2
      args:
        - "run"
        - "--server"
        - "--addr=localhost:8080"

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/disallowedtags/samples/container-image-must-not-have-latest-tag/example_allowed.yaml
```

</details>
<details>
<summary>exempt-images-with-disallowed-tags</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: opa-exempt-allowed
spec:
  containers:
    - name: opa-exp
      image: openpolicyagent/opa-exp:latest
      args:
        - "run"
        - "--server"
        - "--addr=localhost:8080"
    - name: opa-init
      image: openpolicyagent/init:v1
      args:
        - "run"
        - "--server"
        - "--addr=localhost:8080"
    - name: opa-exp2
      image: openpolicyagent/opa-exp2:latest
      args:
        - "run"
        - "--server"
        - "--addr=localhost:8080"

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/disallowedtags/samples/container-image-must-not-have-latest-tag/example_exempt_image_w_disallowed_tag.yaml
```

</details>
<details>
<summary>no-tag</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: opa-disallowed
spec:
  containers:
    - name: opa
      image: openpolicyagent/opa
      args:
        - "run"
        - "--server"
        - "--addr=localhost:8080"

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/disallowedtags/samples/container-image-must-not-have-latest-tag/example_no_tag.yaml
```

</details>
<details>
<summary>no-tag-with-port</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: opa-disallowed-4
spec:
  containers:
    - name: opa
      image: openpolicyagent:443/opa
      args:
        - "run"
        - "--server"
        - "--addr=localhost:8080"

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/disallowedtags/samples/container-image-must-not-have-latest-tag/example_no_tag_w_port.yaml
```

</details>
<details>
<summary>single-disallowed-tag</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: opa-disallowed-2
spec:
  containers:
    - name: opa
      image: openpolicyagent/opa:latest
      args:
        - "run"
        - "--server"
        - "--addr=localhost:8080"

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/disallowedtags/samples/container-image-must-not-have-latest-tag/example_disallowed_tag.yaml
```

</details>
<details>
<summary>single-disallowed-tag-ephemeral</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: opa-disallowed-ephemeral
spec:
  containers:
    - name: opa
      image: openpolicyagent/opa:0.9.2
      args:
        - "run"
        - "--server"
        - "--addr=localhost:8080"
  ephemeralContainers:
    - name: opa
      image: openpolicyagent/opa:latest
      args:
        - "run"
        - "--server"
        - "--addr=localhost:8080"

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/disallowedtags/samples/container-image-must-not-have-latest-tag/disallowed_tag_ephemeral.yaml
```

</details>
<details>
<summary>some-disallow-tags</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: opa-disallowed-3
spec:
  containers:
    - name: opa
      image: openpolicyagent/opa-exp:latest
      args:
        - "run"
        - "--server"
        - "--addr=localhost:8080"
    - name: opa-init
      image: openpolicyagent/init:latest
      args:
        - "run"
        - "--server"
        - "--addr=localhost:8080"
    - name: opa-exp2
      image: openpolicyagent/opa-exp2:latest
      args:
        - "run"
        - "--server"
        - "--addr=localhost:8080"
    - name: opa-monitor
      image: openpolicyagent/monitor:latest
      args:
        - "run"
        - "--server"
        - "--addr=localhost:8080"

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/disallowedtags/samples/container-image-must-not-have-latest-tag/example_some_disallowed_tags.yaml
```

</details>
<details>
<summary>tagged-digest-all-container-types</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: tagged-digest-all-container-types
  namespace: default
spec:
  containers:
    - name: regular-tagged-digest
      image: host:5000/team/app:latest@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  initContainers:
    - name: init-tagged-digest
      image: host:5000/team/app:latest@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  ephemeralContainers:
    - name: ephemeral-tagged-digest
      image: host:5000/team/app:latest@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/disallowedtags/samples/container-image-must-not-have-latest-tag/tagged_digest_all_container_types.yaml
```

</details>
<details>
<summary>digest-only-all-container-types</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: digest-only-all-container-types
  namespace: default
spec:
  containers:
    - name: regular-digest-only
      image: host:5000/team/app@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  initContainers:
    - name: init-digest-only
      image: host:5000/team/app@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  ephemeralContainers:
    - name: ephemeral-digest-only
      image: host:5000/team/app@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/disallowedtags/samples/container-image-must-not-have-latest-tag/digest_only_all_container_types.yaml
```

</details>
<details>
<summary>permitted-tags-with-and-without-digests</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: permitted-tags
  namespace: default
spec:
  containers:
    - name: permitted
      image: host:5000/team/app:1.2.3
    - name: permitted-digest
      image: host:5000/team/app:1.2.3@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
    - name: not-latest
      image: app:notlatest
    - name: latest-extra
      image: app:latest-extra
    - name: case-sensitive
      image: app:Latest

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/disallowedtags/samples/container-image-must-not-have-latest-tag/permitted_tags.yaml
```

</details>
<details>
<summary>untagged-images-and-allowed-tag-substrings</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: untagged-and-tag-substrings
  namespace: default
spec:
  containers:
    - name: untagged
      image: app
    - name: untagged-with-registry-port
      image: host:5000/team/app
    - name: not-latest
      image: app:notlatest
    - name: latest-extra
      image: app:latest-extra

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/disallowedtags/samples/container-image-must-not-have-latest-tag/untagged_and_tag_substrings.yaml
```

</details>


</details><details>
<summary>digest-reference-exemptions</summary>

<details>
<summary>constraint</summary>

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDisallowedTags
metadata:
  name: container-image-digest-exemptions
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces:
      - "default"
  parameters:
    tags: ["latest"]
    exemptImages:
      - "host:5000/team/exact:latest@sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
      - "host:5000/team/wild@sha256:*"

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/disallowedtags/samples/container-image-must-not-have-latest-tag/constraint_digest_exemptions.yaml
```

</details>

<details>
<summary>exact-and-wildcard-exempt-digest-references</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: exempt-digest-references
  namespace: default
spec:
  containers:
    - name: exact-exempt
      image: host:5000/team/exact:latest@sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
    - name: wildcard-exempt
      image: host:5000/team/wild@sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/disallowedtags/samples/container-image-must-not-have-latest-tag/exempt_digest_references.yaml
```

</details>


</details>