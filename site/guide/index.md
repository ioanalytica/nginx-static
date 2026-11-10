---
source: chart/README.md
editPage: true
---

# Introduction

<!--@include: ../../chart/README.md#intro-->

nginx-static is a Helm chart and a base image. A release names the image of
the site it serves, an NGINX with the site's files in it, and the chart puts
what a site needs around it. The base image is what a site's image is built
on: NGINX from source, without TLS, as one static binary.
[The image](/reference/image) says how a site's image is built, and what the
chart expects of one that is built on something else.

## Features

<!--@include: ../../chart/README.md#features-->

## What a release runs

| Resource | Rendered | Described under |
|---|---|---|
| Deployment of the site's image | always | [The image](/reference/image), [Resources and probes](/features/resources) |
| Service | always | [Parameters](/reference/parameters) |
| HorizontalPodAutoscaler | with `autoscaling.enabled`, the default | [Autoscaling](/features/autoscaling) |
| PodDisruptionBudget | with `pdb.enabled`, the default | [Autoscaling](/features/autoscaling) |
| Ingress for the site | with `ingress.enabled`, the default | [Ingress](/features/ingress) |
| Redirect from alias hosts | with `redirect.enabled` | [Redirect](/features/redirect) |

## Prerequisites

<!--@include: ../../chart/README.md#prerequisites-->

## Next steps

- [Try it locally](/guide/try-locally): the chart in a throwaway k3d cluster.
- [Install](/guide/install) the chart with the image of a site.
- [Parameters](/reference/parameters): where each group of values is described.
