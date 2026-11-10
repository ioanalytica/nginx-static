<!-- Copyright IO ANALYTICA. SPDX-License-Identifier: Apache-2.0 -->
<!--
  The home page's hero image: the install command of chart/README.md's
  Quick Start. It names no version: the site is built from main, where a
  version can stand before its release is published.
-->
<template>
  <figure class="hero-terminal">
    <div class="bar" aria-hidden="true"><span /><span /><span /></div>
    <pre><code><span class="c"># a static site from its own NGINX image</span>
<span class="p">$</span> helm install my-site \
    oci://ghcr.io/ioanalytica/charts/nginx-static \
    --namespace websites --create-namespace \
    --set image.registry=registry.example.com \
    --set image.repository=sites/my-site \
    --set image.tag=1.0.0 \
    --set ingress.className=traefik \
    --set 'ingress.hosts[0].host=www.example.com'</code></pre>
  </figure>
</template>

<style scoped>
.hero-terminal {
  position: relative;
  margin: 0;
  width: min(100%, 480px);
  border-radius: 12px;
  background: var(--nginx-static-terminal-bg);
  box-shadow: var(--vp-shadow-4);
  overflow: hidden;
  text-align: left;
}

.bar {
  display: flex;
  gap: 6px;
  padding: 12px 14px 0;
}

.bar span {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: var(--nginx-static-terminal-dot);
}

pre {
  margin: 0;
  padding: 14px 18px 18px;
  overflow-x: auto;
  font-family: var(--vp-font-family-mono);
  font-size: 13px;
  line-height: 1.65;
  color: var(--nginx-static-terminal-text);
}

.c {
  color: var(--nginx-static-terminal-comment);
}

.p {
  color: var(--nginx-static-terminal-prompt);
  user-select: none;
}

@media (max-width: 640px) {
  pre {
    font-size: 12px;
  }
}
</style>
