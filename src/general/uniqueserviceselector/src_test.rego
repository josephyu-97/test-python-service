package k8suniqueserviceselector

test_no_data {
  inp := {"review": review(service("candidate", "prod", {"app": "store"}))}
  results := violation with input as inp
  count(results) == 0
}

test_update_same_service {
  candidate := service("candidate", "prod", {"app": "store"})
  inp := {"review": review(candidate)}
  inv := tmp_data([candidate])

  results := violation with input as inp with data.inventory as inv
  count(results) == 0
}

test_same_namespace_collision {
  inp := {"review": review(service("candidate", "prod", {"app": "store"}))}
  inv := tmp_data([service("local-duplicate", "prod", {"app": "store"})])

  results := violation with input as inp with data.inventory as inv
  results == {{"msg": "same selector as service <local-duplicate> in namespace <prod>"}}
}

test_cross_namespace_not_collision {
  inp := {"review": review(service("candidate", "prod", {"app": "store"}))}
  inv := tmp_data([service("remote-duplicate", "staging", {"app": "store"})])

  results := violation with input as inp with data.inventory as inv
  count(results) == 0
}

test_mixed_namespaces_reports_only_local_collision {
  inp := {"review": review(service("candidate", "prod", {"app": "store"}))}
  inv := tmp_data([
    service("local-duplicate", "prod", {"app": "store"}),
    service("remote-duplicate", "staging", {"app": "store"}),
  ])

  results := violation with input as inp with data.inventory as inv
  results == {{"msg": "same selector as service <local-duplicate> in namespace <prod>"}}
}

test_one_collision_per_distinct_same_namespace_service {
  inp := {"review": review(service("candidate", "prod", {"app": "store"}))}
  inv := tmp_data([
    service("local-duplicate-one", "prod", {"app": "store"}),
    service("local-duplicate-two", "prod", {"app": "store"}),
  ])

  results := violation with input as inp with data.inventory as inv
  results == {
    {"msg": "same selector as service <local-duplicate-one> in namespace <prod>"},
    {"msg": "same selector as service <local-duplicate-two> in namespace <prod>"},
  }
}

test_no_collision_for_different_selectors {
  inp := {"review": review(service("candidate", "prod", {"app": "store"}))}
  inv := tmp_data([service("other", "prod", {"app": "accounts"})])

  results := violation with input as inp with data.inventory as inv
  count(results) == 0
}

test_compound_selector_collision_independent_of_key_order {
  inp := {"review": review(service("candidate", "prod", {"app": "store", "tier": "frontend"}))}
  inv := tmp_data([service("local-duplicate", "prod", {"tier": "frontend", "app": "store"})])

  results := violation with input as inp with data.inventory as inv
  results == {{"msg": "same selector as service <local-duplicate> in namespace <prod>"}}
}

test_partial_subset_superset_and_overlapping_selectors_do_not_collide {
  inp := {"review": review(service("candidate", "prod", {"app": "store", "tier": "frontend"}))}
  inv := tmp_data([
    service("partial-overlap", "prod", {"app": "store", "tier": "backend"}),
    service("subset", "prod", {"app": "store"}),
    service("superset", "prod", {"app": "store", "tier": "frontend", "environment": "production"}),
    service("other-overlap", "prod", {"tier": "frontend", "environment": "production"}),
  ])

  results := violation with input as inp with data.inventory as inv
  count(results) == 0
}

test_omitted_selector_candidate_does_not_collide {
  inp := {"review": review(service_without_selector("candidate", "prod"))}
  inv := tmp_data([
    service_without_selector("selector-omitted", "prod"),
    service("selector-empty", "prod", {}),
    service("selected", "prod", {"app": "store"}),
  ])

  results := violation with input as inp with data.inventory as inv
  count(results) == 0
}

test_empty_selector_candidate_does_not_collide {
  inp := {"review": review(service("candidate", "prod", {}))}
  inv := tmp_data([
    service_without_selector("selector-omitted", "prod"),
    service("selector-empty", "prod", {}),
    service("selected", "prod", {"app": "store"}),
  ])

  results := violation with input as inp with data.inventory as inv
  count(results) == 0
}

test_selected_candidate_does_not_collide_with_selectorless_services {
  inp := {"review": review(service("candidate", "prod", {"app": "store"}))}
  inv := tmp_data([
    service_without_selector("selector-omitted", "prod"),
    service("selector-empty", "prod", {}),
  ])

  results := violation with input as inp with data.inventory as inv
  count(results) == 0
}

test_no_service_selector_with_unrelated_inventory {
  inp := {"review": review(service_without_selector("kubernetes", "default"))}
  inv := data_networkpolicy("default")

  results := violation with input as inp with data.inventory as inv
  count(results) == 0
}

review(srv) = output {
  output = {
    "kind": {
      "kind": "Service",
      "version": "v1",
      "group": "",
    },
    "namespace": srv.metadata.namespace,
    "name": srv.metadata.name,
    "object": srv,
  }
}

service_without_selector(name, ns) = out {
  out = {
    "kind": "Service",
    "apiVersion": "v1",
    "metadata": {
      "name": name,
      "namespace": ns,
    },
    "spec": {
      "clusterIP": "10.43.0.1",
      "clusterIPs": ["10.43.0.1"],
      "ports": [
        {
          "name": "https",
          "port": 443,
          "protocol": "TCP",
          "targetPort": 6443,
        },
      ],
      "sessionAffinity": "None",
      "type": "ClusterIP",
    },
  }
}

service(name, ns, selector) = out {
  out = {
    "kind": "Service",
    "apiVersion": "v1",
    "metadata": {
      "name": name,
      "namespace": ns,
    },
    "spec": {"selector": selector},
  }
}

data_networkpolicy(ns) = out {
  out = {
    "namespace": {
      ns: {
        "v1": {
          "NetworkPolicy": {
            "default-network-policy": {
              "apiVersion": "networking.k8s.io/v1",
              "kind": "NetworkPolicy",
              "metadata": {
                "name": "default-network-policy",
                "namespace": ns,
              },
              "spec": {
                "ingress": [
                  {
                    "from": [
                      {
                        "podSelector": {},
                      },
                    ],
                  },
                ],
                "podSelector": {},
                "policyTypes": ["Ingress"],
              },
            },
          },
        },
      },
    },
  }
}

tmp_data(services) = out {
  namespaces := {ns | ns = services[_].metadata.namespace}
  out = {
    "namespace": {
      ns: {
        "v1": {
          "Service": flatten_by_name(services, ns),
        },
      } | ns := namespaces[_]
    },
  }
}

flatten_by_name(services, ns) = out {
  out = {o.metadata.name: o | o = services[_]; o.metadata.namespace = ns}
}
