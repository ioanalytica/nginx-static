---
layout: home
title: nginx-static
titleTemplate: Static websites on NGINX for Kubernetes
source: chart/README.md
editPage: true
hero:
  name: nginx-static
  text: Static websites on NGINX for Kubernetes
  tagline: A Helm chart that serves a static website from the site's own NGINX image, with autoscaling, an Ingress for ingress-nginx or Traefik, and a redirect from alias hosts. And a 2 MB NGINX base image, built from source without TLS, to build the site's image on.
  actions:
    - theme: brand
      text: Install
      link: /guide/install
    - theme: alt
      text: Try it locally
      link: /guide/try-locally
    - theme: alt
      text: Introduction
      link: /guide/
    - theme: alt
      text: GitHub
      link: https://github.com/ioanalytica/nginx-static
features:
  - icon: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3 3 7.5l9 4.5 9-4.5z"/><path d="m3 12 9 4.5 9-4.5"/><path d="m3 16.5 9 4.5 9-4.5"/></svg>'
    title: A base image made for the job
    details: NGINX built from source without TLS and without anything that proxies. One static binary, no shell, no OpenSSL, 2 MB. A site's image copies its files in.
    link: /reference/image
  - icon: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="5" cy="12" r="2"/><circle cx="19" cy="5" r="2"/><circle cx="19" cy="12" r="2"/><circle cx="19" cy="19" r="2"/><path d="M7 12h10"/><path d="M7 11.2 17 6"/><path d="M7 12.8 17 18"/></svg>'
    title: Three ingress classes
    details: ingress-nginx, Traefik, and Traefik's ingress-nginx compatibility provider for the move from one to the other, with the same values.
    link: /features/ingress
  - icon: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h11"/><path d="m11 3 4 4-4 4"/><path d="M20 17H9"/><path d="m13 13-4 4 4 4"/></svg>'
    title: Redirect of alias hosts
    details: Any number of hostnames lead to the site's URL with a permanent redirect and one certificate for all of them. On Traefik the redirect keeps the request path.
    link: /features/redirect
  - icon: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20V10"/><path d="M10 20V4"/><path d="M16 20v-7"/><path d="M22 20H2"/></svg>'
    title: Autoscaling
    details: A HorizontalPodAutoscaler on CPU and memory that scales up fast and down slowly, and a PodDisruptionBudget that keeps the site up through node drains.
    link: /features/autoscaling
  - icon: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="m9 14 2 2 4-4"/></svg>'
    title: Values schema
    details: Helm checks the values of every install and upgrade, and refuses a misspelled host entry or an unknown ingress class before anything is deployed.
    link: /reference/parameters
  - icon: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3 5 6v5c0 4.5 2.9 8.4 7 10 4.1-1.6 7-5.5 7-10V6z"/><path d="m9 12 2 2 4-4"/></svg>'
    title: Signed releases
    details: A release signs the base image and the chart with Sigstore cosign, keyless. The page has the commands that verify them by their digests.
    link: /security/verify
---

## How it fits together

A release is one site. Its Deployment runs the image the release names: an
NGINX with the site's files. The project's base image is what such an image
is built on, with a `COPY` of the files and nothing else;
[The image](/reference/image) says how, and what the chart expects of an
image that is built on something else.

Around it the chart renders a Service, a HorizontalPodAutoscaler, a
PodDisruptionBudget and an Ingress for one of three ingress classes, and on
request a permanent redirect from alias hosts to the site's URL.
[What a release runs](/guide/#what-a-release-runs) lists them.

## Quick start

<!--@include: ../chart/README.md#install-->

[Install](/guide/install) covers pinning a version, and
[Introduction](/guide/#prerequisites) the prerequisites.
