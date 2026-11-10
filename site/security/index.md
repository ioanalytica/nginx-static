# Security overview

What the chart does for the security of a site, what has to be switched on,
and what it leaves to the site's image and to the cluster on purpose.

## What the chart does

| Measure | What it does | Described under |
|---|---|---|
| Values schema | Helm checks the values of every install and upgrade and refuses, for one, a switch given as text, which would not do what it says. | [Upgrading](/operations/upgrading) |
| Signed releases | A release signs the chart with Sigstore cosign, and the chart can be installed by the digest that was verified. | [Verify a release](/security/verify) |

## Opt-in

| Measure | What it does | Setting |
|---|---|---|
| [Security context](/security/security-context) | The pod and container security contexts are empty by default. The page gives the settings that pass the `restricted` Pod Security Standard with an image that runs NGINX as a non-root user. | `podSecurityContext`, `containerSecurityContext` |
| Pinned image | A digest pins the release to one build of the site's image. See [The image](/reference/image). | `image.digest` |

## Left to other layers

- **The image** is the site's own: the chart ships none. Rules that deny
  hidden files or paths that scanners probe belong in its NGINX
  configuration, where they hold whichever ingress controller is in front;
  [The image](/reference/image) has an example.
- **TLS** ends at the ingress controller. The pod serves plain HTTP inside
  the cluster.
- **Network policies** are the namespace's: the chart renders none.

## Reporting

[Report a vulnerability](/security/reporting) says how to report one
privately, which versions get fixes and what the policy covers.
