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
