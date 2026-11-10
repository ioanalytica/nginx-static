// Copyright IO ANALYTICA. SPDX-License-Identifier: Apache-2.0
import { copyFileSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitepress';
import { pageHeadings, repoUrl, repositoryLinks } from './links';

const siteRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = resolve(siteRoot, '..');

// The chart icon doubles as the favicon; it is read from the repository root
// instead of being copied into public/.
const icon = resolve(repoRoot, 'icon.png');

export default defineConfig({
  lang: 'en-US',
  title: 'nginx-static',
  description:
    'A Helm chart that serves a static website from an NGINX image on Kubernetes, with autoscaling, an Ingress for ingress-nginx or Traefik, and a redirect from alias hosts, and a minimal NGINX base image built from source without TLS.',
  cleanUrls: true,
  // No `base`: the site is served from the root of its own domain (siteUrl in
  // links.ts), set as the custom domain in the repository's Pages settings,
  // not from the project path under github.io.
  head: [['link', { rel: 'icon', type: 'image/png', href: '/favicon.png' }]],
  markdown: {
    config(md) {
      md.use(repositoryLinks);
      md.use(pageHeadings);
    },
  },
  vite: {
    plugins: [
      {
        name: 'nginx-static-favicon',
        configureServer(server) {
          server.middlewares.use('/favicon.png', (_req, res) => {
            res.setHeader('Content-Type', 'image/png');
            res.end(readFileSync(icon));
          });
        },
      },
    ],
  },
  buildEnd(config) {
    copyFileSync(icon, join(config.outDir, 'favicon.png'));
  },
  themeConfig: {
    siteTitle: 'nginx-static',
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Install', link: '/guide/install' },
      { text: 'Parameters', link: '/reference/parameters' },
      { text: 'GitHub', link: repoUrl },
    ],
    sidebar: [
      {
        text: 'Getting Started',
        items: [
          { text: 'Introduction', link: '/guide/' },
          { text: 'Try it locally', link: '/guide/try-locally' },
          { text: 'Install', link: '/guide/install' },
        ],
      },
      {
        text: 'Features',
        items: [
          { text: 'Ingress', link: '/features/ingress' },
          { text: 'Redirect', link: '/features/redirect' },
          { text: 'Autoscaling', link: '/features/autoscaling' },
          { text: 'Resources and probes', link: '/features/resources' },
        ],
      },
      {
        text: 'Security',
        items: [
          { text: 'Overview', link: '/security/' },
          { text: 'Security context', link: '/security/security-context' },
          { text: 'Verify a release', link: '/security/verify' },
          { text: 'Report a vulnerability', link: '/security/reporting' },
        ],
      },
      {
        text: 'Operations',
        items: [{ text: 'Upgrading', link: '/operations/upgrading' }],
      },
      {
        text: 'Reference',
        items: [
          { text: 'Parameters', link: '/reference/parameters' },
          { text: 'The image', link: '/reference/image' },
          { text: 'Versioning', link: '/reference/versioning' },
          { text: 'Changelog', link: '/reference/changelog' },
          { text: 'Contributing', link: '/reference/contributing' },
          { text: 'License', link: '/reference/license' },
        ],
      },
    ],
    socialLinks: [{ icon: 'github', link: repoUrl }],
    search: { provider: 'local' },
    // A page made of one file's sections names that file as `source`, so the
    // edit link opens what holds its text; a page with text of its own next
    // to such sections sets `editPage`. The function runs in the browser,
    // without this module's constants.
    editLink: {
      pattern: ({ filePath, frontmatter }) =>
        `https://github.com/ioanalytica/nginx-static/edit/main/${
          frontmatter.source && !frontmatter.editPage ? frontmatter.source : `site/${filePath}`
        }`,
      text: 'Edit this page on GitHub',
    },
    footer: {
      message:
        'Distributed under the Apache-2.0 license. NGINX, Traefik and other names are trademarks of their owners; this project is not affiliated with or endorsed by them.',
      copyright: 'Copyright © 2024-present IO ANALYTICA',
    },
    outline: { level: [2, 3], label: 'On this page' },
  },
});
