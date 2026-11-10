# Try it locally

The chart in a throwaway [k3d](https://k3d.io) cluster on one machine: a
site behind Traefik, and an alias host that redirects to it. It takes about
a minute, most of it for pulling the images. Tested with k3d 5.9 and
k3s 1.37.

> **A cluster to try the chart in.** The chart ships no image: a release
> names the image of the site it serves. Here the stock
> [unprivileged NGINX image](https://hub.docker.com/r/nginxinc/nginx-unprivileged)
> stands in for one, and its welcome page for the site. Nothing here is a
> setup to keep.

| Part | What it does here |
| --- | --- |
| The site | one pod of `nginxinc/nginx-unprivileged`, listening on port 8080 as a non-root user |
| Ingress | class `traefik`, host `site.localhost` |
| Redirect | a Traefik Middleware and IngressRoute that send `www.site.localhost` to the site, with the request path |
| Traefik | ships with k3s; listens on the ports 8080 (HTTP) and 8443 (HTTPS) of this machine |

## What you need

- Docker
- [k3d](https://k3d.io), `kubectl` 1.31 or later (for `wait --for=create`),
  [Helm](https://helm.sh) 3.8 or later and `curl` 7.85 or later, which
  resolves every name under `localhost` to this machine by itself
- the ports 8080 and 8443 free on the host

## 1. A cluster

```sh
k3d cluster create nginx-static --image rancher/k3s:v1.37.2-k3s1 \
  -p "127.0.0.1:8080:80@loadbalancer" -p "127.0.0.1:8443:443@loadbalancer"
```

The image is the k3s this page is tested with; without it, the k3s depends on
how k3d was built. The two `-p` map the ports 8080 and 8443 of the host to
the ports 80 and 443 of the cluster's load balancer, where Traefik listens,
and bind them to the loopback address: the site is reachable from this
machine only. k3d makes `k3d-nginx-static` the current `kubectl` context.

k3s installs Traefik in the background after the cluster has started. The
redirect below is made of Traefik's own resource kinds, which exist only once
Traefik is installed, so wait for it:

```sh
kubectl -n kube-system wait --for=create deployment/traefik --timeout=5m
kubectl -n kube-system rollout status deployment/traefik --timeout=5m
```

## 2. Install

```sh
url=https://raw.githubusercontent.com/ioanalytica/nginx-static/main/examples/k3d
kubectl create namespace site
kubectl label namespace site pod-security.kubernetes.io/enforce=restricted
helm install demo oci://ghcr.io/ioanalytica/charts/nginx-static \
  --namespace site \
  -f $url/values.yaml
```

The label has Kubernetes refuse any pod in the namespace that does not meet
the `restricted` Pod Security Standard: no root user, no privilege
escalation, no capabilities.

Without `--version`, Helm installs the latest release. The values file holds
what stands in for a site and what k3d needs:

| Value | Why |
| --- | --- |
| `image.*` | the stock unprivileged NGINX image in place of a site's image |
| `probes.liveness.httpGet.path: /` | the chart asks a site's image for `/healthz`, which the stock image does not have; its welcome page answers instead |
| `podSecurityContext`, `containerSecurityContext` | the settings of the `restricted` Pod Security Standard, which the namespace created below enforces |
| `autoscaling.enabled`, `pdb.enabled` | off: one pod on one node |
| `ingress.className: traefik` | the controller k3s ships |
| `ingress.hosts` | the site's host, `site.localhost` |
| `redirect.*` | `www.site.localhost` redirects to `http://site.localhost:8080` |

Wait until the site is ready:

```sh
kubectl -n site rollout status deployment/demo-nginx-static --timeout=5m
```

## 3. The site

```sh
curl -s http://site.localhost:8080/ | grep '<title>'
```

```
<title>Welcome to nginx!</title>
```

Traefik picks a new Ingress up within a second or two; a `404` right after
the rollout means it has not yet.

## 4. The redirect

The redirect answers on Traefik's HTTPS entry point, `websecure`. No
certificate is set up here, so Traefik presents its own self-signed one, and
`-k` has curl accept it:

```sh
curl -sk -o /dev/null -w '%{http_code} %{redirect_url}\n' 'https://www.site.localhost:8443/docs/page?x=1'
```

```
301 http://site.localhost:8080/docs/page?x=1
```

The path and the query string are kept. With the class `nginx` the chart
renders the redirect as a second Ingress for ingress-nginx instead, whose
redirect annotation sends every request to the target URL itself, without
the path.

What the chart deployed for the two hosts:

```sh
kubectl -n site get ingress,ingressroute,middleware -o name
```

```
ingress.networking.k8s.io/demo-nginx-static
ingressroute.traefik.io/demo-nginx-static-redirect
middleware.traefik.io/demo-nginx-static-redirect-preserve-path
```

## Clean up

```sh
k3d cluster delete nginx-static
```

## From here

- [Install](https://nginx-static.ioanalytica.com/guide/install) the chart
  with the image of a site of your own.
- The [image](https://nginx-static.ioanalytica.com/reference/image) page
  says what the chart expects of it.
- [Ingress classes](https://nginx-static.ioanalytica.com/features/ingress)
  compares the three classes and their redirects.
