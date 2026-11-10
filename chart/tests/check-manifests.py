"""Structural checks over a rendered Helm manifest stream read from stdin.

    helm template ... | check-manifests.py LABEL

Verifies that the resources of one render refer to each other correctly:

  * the Deployment's selector matches its pod labels, and the Service and the
    PodDisruptionBudget select the same pods
  * the HorizontalPodAutoscaler scales the Deployment of the render, and a
    Deployment with an autoscaler sets no replicas
  * every Ingress backend names the Service of the render and one of its
    ports, and the Service's targetPort is a port of the container
  * a probe that names a port names one the container has
  * an IngressRoute refers to a Middleware of the render, and a Certificate
    writes the Secret the IngressRoute reads
  * no two resources share kind and name

These are the failures that `helm lint` accepts and a cluster does not: a
Service that selects no pod answers 503, and nothing says why.

Documents are parsed with a duplicate-key-rejecting loader. PyYAML silently
keeps the last value for a duplicated mapping key, but the strict YAML
parser in Flux's post-renderer refuses the manifest: a template that writes
`annotations:` from two values renders fine, passes helm lint, and breaks
every HelmRelease upgrade once both values carry the same key.
"""

import sys

import yaml


class StrictLoader(yaml.SafeLoader):
    """SafeLoader that fails on duplicate mapping keys instead of last-wins."""

    def construct_mapping(self, node, deep=False):
        seen = set()
        for key_node, _ in node.value:
            key = self.construct_object(key_node, deep=True)
            if key in seen:
                raise yaml.constructor.ConstructorError(
                    None, None, f"duplicate mapping key {key!r}", key_node.start_mark
                )
            seen.add(key)
        return super().construct_mapping(node, deep)


def selects(selector, labels):
    """Whether a matchLabels selector matches a set of labels."""
    return bool(selector) and all(labels.get(k) == v for k, v in selector.items())


def main():
    """Check the manifests on stdin; print the problems and return 1 if any."""
    label = sys.argv[1] if len(sys.argv) > 1 else "manifests"
    raw = sys.stdin.read()
    try:
        docs = [d for d in yaml.load_all(raw, Loader=StrictLoader) if d]
    except yaml.YAMLError as err:
        print(f"FAIL: {label}")
        print(f"      rendered manifests are not strict YAML: {err}")
        return 1

    problems = []
    by_kind = {}
    seen = set()
    for doc in docs:
        key = (doc.get("kind"), doc["metadata"]["name"])
        if key in seen:
            problems.append(f"{key[0]} {key[1]} is rendered twice")
        seen.add(key)
        by_kind.setdefault(doc.get("kind"), []).append(doc)

    deployments = by_kind.get("Deployment", [])
    if len(deployments) != 1:
        problems.append(f"{len(deployments)} Deployments rendered, expected one")
        deployments = deployments[:1]

    for deployment in deployments:
        name = deployment["metadata"]["name"]
        pod = deployment["spec"]["template"]
        pod_labels = pod["metadata"].get("labels") or {}
        if not selects(deployment["spec"]["selector"].get("matchLabels"), pod_labels):
            problems.append(f"Deployment {name}: the selector does not match the pod labels")

        ports = set()
        for container in pod["spec"]["containers"]:
            for port in container.get("ports") or []:
                ports.update({port.get("name"), port.get("containerPort")})
            for probe in ("readinessProbe", "livenessProbe", "startupProbe"):
                for handler in ("httpGet", "tcpSocket", "grpc"):
                    port = ((container.get(probe) or {}).get(handler) or {}).get("port")
                    if port is not None and port not in ports:
                        problems.append(f"Deployment {name}: {probe} names port {port!r}, which the container lacks")

        for service in by_kind.get("Service", []):
            if not selects(service["spec"].get("selector"), pod_labels):
                problems.append(f"Service {service['metadata']['name']} does not select the pods of {name}")
            for port in service["spec"]["ports"]:
                if port.get("targetPort") not in ports:
                    problems.append(
                        f"Service {service['metadata']['name']}: targetPort {port.get('targetPort')!r} is no port of the container"
                    )
        for pdb in by_kind.get("PodDisruptionBudget", []):
            if not selects(pdb["spec"]["selector"].get("matchLabels"), pod_labels):
                problems.append(f"PodDisruptionBudget {pdb['metadata']['name']} does not select the pods of {name}")
            if "minAvailable" not in pdb["spec"] and "maxUnavailable" not in pdb["spec"]:
                problems.append(f"PodDisruptionBudget {pdb['metadata']['name']} sets neither minAvailable nor maxUnavailable")

        hpas = by_kind.get("HorizontalPodAutoscaler", [])
        for hpa in hpas:
            target = hpa["spec"]["scaleTargetRef"]
            if (target.get("kind"), target.get("name")) != ("Deployment", name):
                problems.append(f"HorizontalPodAutoscaler {hpa['metadata']['name']} does not scale Deployment {name}")
            if not hpa["spec"].get("metrics"):
                problems.append(f"HorizontalPodAutoscaler {hpa['metadata']['name']} has no metric")
        if hpas and "replicas" in deployment["spec"]:
            problems.append(f"Deployment {name} sets replicas next to a HorizontalPodAutoscaler")
        if not hpas and "replicas" not in deployment["spec"]:
            problems.append(f"Deployment {name} sets no replicas and has no HorizontalPodAutoscaler")

    services = {
        s["metadata"]["name"]: {p for port in s["spec"]["ports"] for p in (port.get("name"), port.get("port"))}
        for s in by_kind.get("Service", [])
    }
    for ingress in by_kind.get("Ingress", []):
        name = ingress["metadata"]["name"]
        if not ingress["spec"].get("rules"):
            problems.append(f"Ingress {name} has no rules")
        for rule in ingress["spec"].get("rules") or []:
            for path in (rule.get("http") or {}).get("paths") or []:
                backend = path["backend"]["service"]
                port = backend["port"].get("name", backend["port"].get("number"))
                if backend["name"] not in services:
                    problems.append(f"Ingress {name}: backend Service {backend['name']} is not rendered")
                elif port not in services[backend["name"]]:
                    problems.append(f"Ingress {name}: Service {backend['name']} has no port {port!r}")

    middlewares = {m["metadata"]["name"] for m in by_kind.get("Middleware", [])}
    route_secrets = set()
    for route in by_kind.get("IngressRoute", []):
        name = route["metadata"]["name"]
        for rule in route["spec"]["routes"]:
            for middleware in rule.get("middlewares") or []:
                if middleware["name"] not in middlewares:
                    problems.append(f"IngressRoute {name}: Middleware {middleware['name']} is not rendered")
        secret = (route["spec"].get("tls") or {}).get("secretName")
        if secret:
            route_secrets.add(secret)
    for certificate in by_kind.get("Certificate", []):
        if certificate["spec"]["secretName"] not in route_secrets:
            problems.append(
                f"Certificate {certificate['metadata']['name']} writes Secret "
                f"{certificate['spec']['secretName']}, which no IngressRoute reads"
            )

    if problems:
        print(f"FAIL: {label}")
        for problem in problems:
            print(f"      {problem}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
