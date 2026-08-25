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
