# Security overview

What the chart and the base image do for the security of a site, what has to
be switched on, and what is left to the site's image and to the cluster on
purpose.

## What the chart and the base image do

| Measure | What it does | Described under |
|---|---|---|
| A minimal image | The base image is one static NGINX binary: no TLS and no OpenSSL, no modules that proxy, no shell, no package manager. | [The image](/reference/image) |
| Hidden files | The base image answers every path with a component that starts with a dot with 403. | [The image](/reference/image) |
| Daily scan | The base image is scanned every day for known vulnerabilities in the libraries NGINX is linked with. | [Report a vulnerability](/security/reporting) |
| Values schema | Helm checks the values of every install and upgrade and refuses, for one, a switch given as text, which would not do what it says. | [Upgrading](/operations/upgrading) |
| Signed releases | A release signs the base image and the chart with Sigstore cosign; both can be used by the digest that was verified. | [Verify a release](/security/verify) |

## Opt-in

| Measure | What it does | Setting |
|---|---|---|
| [Security context](/security/security-context) | The pod and container security contexts are empty by default. The page gives the settings the base image is made for: the `restricted` Pod Security Standard and a read-only root filesystem. | `podSecurityContext`, `containerSecurityContext`, `extraVolumes`, `extraVolumeMounts` |
| Pinned image | A digest pins the release to one build of the site's image. See [The image](/reference/image). | `image.digest` |

## Left to other layers

- **The site's image** is the site's own, built on the base image or not.
  Rules that deny paths that scanners probe belong in its NGINX
  configuration, where they hold whichever ingress controller is in front;
  [The image](/reference/image) has an example.
- **TLS** ends at the ingress controller. The pod serves plain HTTP inside
  the cluster.
- **Network policies** are the namespace's: the chart renders none.

## Reporting

[Report a vulnerability](/security/reporting) says how to report one
privately, which versions get fixes and what the policy covers.
