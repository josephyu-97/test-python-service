---
id: uniqueserviceselector
title: Unique Service Selector
---

# Unique Service Selector

## Description
Requires Services with non-empty selectors to have unique selectors within a namespace. Services without selectors are ignored. Selectors are considered the same if they have identical keys and values. Selectors may share a key/value pair so long as there is at least one distinct key/value pair between them.
https://kubernetes.io/docs/concepts/services-networking/service/#defining-a-service

## Template
```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8suniqueserviceselector
  annotations:
    metadata.gatekeeper.sh/title: "Unique Service Selector"
    metadata.gatekeeper.sh/version: 1.0.3
    metadata.gatekeeper.sh/requires-sync-data: |
      "[
        [
          {
            "groups":[""],
            "versions": ["v1"],
            "kinds": ["Service"]
          }
        ]
      ]"
    description: >-
      Requires Services with non-empty selectors to have unique selectors within
      a namespace. Services without selectors are ignored. Selectors are
      considered the same if they have identical keys and values.
      Selectors may share a key/value pair so long as there is at least one
      distinct key/value pair between them.

      https://kubernetes.io/docs/concepts/services-networking/service/#defining-a-service
spec:
  crd:
    spec:
      names:
        kind: K8sUniqueServiceSelector
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8suniqueserviceselector

        identical(obj, review) {
          obj.metadata.namespace == review.object.metadata.namespace
          obj.metadata.name == review.object.metadata.name
        }

        violation[{"msg": msg}] {
          input.review.kind.kind == "Service"
          input.review.kind.version == "v1"
          input.review.kind.group == ""

          selector := input.review.object.spec.selector
          count(selector) > 0

          namespace := input.review.object.metadata.namespace
          other := data.inventory.namespace[namespace]["v1"]["Service"][name]
          not identical(other, input.review)

          other_selector := other.spec.selector
          count(other_selector) > 0
          selector == other_selector

          msg := sprintf("same selector as service <%v> in namespace <%v>", [name, namespace])
        }

```

### Usage
```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/uniqueserviceselector/template.yaml
```
## Examples
<details>
<summary>unique-service-selector</summary>

<details>
<summary>constraint</summary>

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sUniqueServiceSelector
metadata:
  name: unique-service-selector
  labels:
    owner: admin.agilebank.demo

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/uniqueserviceselector/samples/unique-service-selector/constraint.yaml
```

</details>

<details>
<summary>example-allowed</summary>

```yaml
apiVersion: v1
kind: Service
metadata:
  name: gatekeeper-test-service-disallowed
  namespace: default
spec:
  ports:
    - port: 443
  selector:
    key: other-value

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/uniqueserviceselector/samples/unique-service-selector/example_allowed.yaml
```

</details>
<details>
<summary>same-namespace-identical-selector</summary>

```yaml
apiVersion: v1
kind: Service
metadata:
  name: gatekeeper-test-service-disallowed
  namespace: default
spec:
  ports:
    - port: 443
  selector:
    key: value

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/uniqueserviceselector/samples/unique-service-selector/example_disallowed.yaml
```

</details>
<details>
<summary>cross-namespace-identical-selector</summary>

```yaml
apiVersion: v1
kind: Service
metadata:
  name: gatekeeper-test-service-disallowed
  namespace: default
spec:
  ports:
    - port: 443
  selector:
    key: value

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/uniqueserviceselector/samples/unique-service-selector/example_disallowed.yaml
```

</details>
<details>
<summary>mixed-namespace-identical-selectors</summary>

```yaml
apiVersion: v1
kind: Service
metadata:
  name: gatekeeper-test-service-disallowed
  namespace: default
spec:
  ports:
    - port: 443
  selector:
    key: value

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/uniqueserviceselector/samples/unique-service-selector/example_disallowed.yaml
```

</details>
<details>
<summary>one-violation-per-same-namespace-service</summary>

```yaml
apiVersion: v1
kind: Service
metadata:
  name: gatekeeper-test-service-disallowed
  namespace: default
spec:
  ports:
    - port: 443
  selector:
    key: value

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/uniqueserviceselector/samples/unique-service-selector/example_disallowed.yaml
```

</details>
<details>
<summary>omitted-selector-does-not-participate</summary>

```yaml
apiVersion: v1
kind: Service
metadata:
  name: selector-omitted-candidate
  namespace: default
spec:
  ports:
    - port: 443

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/uniqueserviceselector/samples/unique-service-selector/selector_omitted.yaml
```

</details>
<details>
<summary>empty-selector-does-not-participate</summary>

```yaml
apiVersion: v1
kind: Service
metadata:
  name: selector-empty-candidate
  namespace: default
spec:
  ports:
    - port: 443
  selector: {}

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/uniqueserviceselector/samples/unique-service-selector/selector_empty.yaml
```

</details>
<details>
<summary>selected-service-ignores-selectorless-inventory</summary>

```yaml
apiVersion: v1
kind: Service
metadata:
  name: gatekeeper-test-service-disallowed
  namespace: default
spec:
  ports:
    - port: 443
  selector:
    key: value

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/uniqueserviceselector/samples/unique-service-selector/example_disallowed.yaml
```

</details>
<details>
<summary>compound-selector-key-order-independent</summary>

```yaml
apiVersion: v1
kind: Service
metadata:
  name: compound-selector-candidate
  namespace: default
spec:
  ports:
    - port: 443
  selector:
    app: store
    tier: frontend

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/uniqueserviceselector/samples/unique-service-selector/compound_selector.yaml
```

</details>
<details>
<summary>partial-subset-superset-and-overlap-allowed</summary>

```yaml
apiVersion: v1
kind: Service
metadata:
  name: compound-selector-candidate
  namespace: default
spec:
  ports:
    - port: 443
  selector:
    app: store
    tier: frontend

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/uniqueserviceselector/samples/unique-service-selector/compound_selector.yaml
```

</details>
<details>
<summary>update-inventoried-service-itself</summary>

```yaml
apiVersion: v1
kind: Service
metadata:
  name: compound-selector-candidate
  namespace: default
spec:
  ports:
    - port: 443
  selector:
    app: store
    tier: frontend

```

Usage

```shell
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/uniqueserviceselector/samples/unique-service-selector/compound_selector.yaml
```

</details>


</details>