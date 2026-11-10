# Contributing to nginx-static

Thanks for helping. Bug reports and pull requests are welcome.

## Where things go

- **Bugs and feature requests**: [open an issue](https://github.com/ioanalytica/nginx-static/issues/new/choose).
  For a bug, the chart version, the ingress class and the values that differ
  from the defaults usually decide where to look.
- **Security issues**: never in a public issue — see [SECURITY.md](SECURITY.md).
- **The image of a site** is not part of this project: its files and its own
  NGINX configuration belong to whoever builds it. The base image it is
  built on is; [The image](chart/README.md#the-image) describes both.

## What is where

| Path | What it holds |
|---|---|
| `chart/` | The Helm chart: `templates/`, `values.yaml`, `values.schema.json`, its `README.md` and `CHANGELOG.md`, and its tests in `tests/` |
| `docker/` | The base image: `Dockerfile`, the configuration it ships in `rootfs/`, the keys NGINX's source is checked against in `keys/`, and its tests in `tests/` |
| `examples/sites/` | The values of real sites, which the tests render |
| `examples/k3d/` | The page "Try it locally" and its values file |
| `tests/try-locally/` | The run of that page in a k3d cluster |
| `tests/ci/` | The tests of the workflows and of the scripts a release runs |
| `scripts/` | The scripts of the release workflow |
| `.github/cve-scan-accepted.yaml` | Findings the daily scan does not fail on, each with a reason and an expiry date |
| `site/` | The documentation site, see [The documentation site](#the-documentation-site) |
| `.github/workflows/` | The tests, the release build, the daily scan, the page's run and the site's build |

## Running the tests

The tests are shell scripts. They need `helm`, `docker`, `jq`,
[`yq`](https://github.com/mikefarah/yq) (the Go one, not the Python wrapper of
the same name) and Python 3 with PyYAML; the checks of the scripts and the
Dockerfiles need [shellcheck](https://www.shellcheck.net/) and
[hadolint](https://github.com/hadolint/hadolint) as well. Each block of commands
starts in the repository root.

### Chart

```sh
helm dependency update chart/
helm lint chart/ --set ingress.className=nginx
./chart/tests/template-test.sh
./chart/tests/schema-test.sh
```

- `helm dependency update` fetches the `common` subchart, which is not checked
  in. Everything below needs it.
- `helm lint` names an ingress class because the chart's defaults name none,
  which the chart refuses on purpose.
- `template-test.sh` renders the chart with many sets of values, the ones in
  `examples/` among them, and checks that the resources of a render refer to
  each other and that each ingress class renders what the README says.
- `schema-test.sh` compares `chart/values.schema.json` with
  `chart/values.yaml`: every documented value has its entry, with the same
  description and default. It also checks that the schema lets through the
  forms in which values reach the chart, and refuses what the chart cannot
  use.

### Image

```sh
docker build -t nginx-static:test ./docker
./docker/tests/smoke-test.sh nginx-static:test
```

The build compiles NGINX, which takes a minute or two, checks the source
against the keys in `docker/keys/`, and fails if the binary is not static or
has TLS in it, or if the shipped configuration does not load. The smoke test
starts the image on a read-only root filesystem without capabilities and
probes it: what it answers, what it logs, and that the image holds NGINX,
its configuration and nothing else. It then builds a site's image on it from
`docker/tests/site/`, as the README describes one.

### Workflows and release scripts

```sh
./tests/ci/test.sh
./tests/ci/shellcheck.sh
git ls-files -z '*Dockerfile' | xargs -0 hadolint
```

- `test.sh` holds every workflow to the project's rules (actions pinned by
  commit, a time limit per job, least permissions) and tests the scripts a
  release runs, against a stand-in for the registry.
- `shellcheck.sh` runs shellcheck over every shell script, `hadolint` checks
  the Dockerfiles.

Continuous integration runs all three blocks on every pull request, as the
jobs `chart-test`, `smoke-test`, `shellcheck` and `hadolint` of
[`.github/workflows/test.yml`](.github/workflows/test.yml).

### Try it locally

```sh
image="ghcr.io/ioanalytica/nginx-static:$(sed -n 's/^version: *//p' chart/Chart.yaml)"
docker build -t "$image" ./docker
tests/try-locally/run.sh --import "$image" ./chart
```

The page [Try it locally](examples/k3d/README.md) runs as written: `run.sh`
creates the page's k3d cluster, runs every shell block of the page against
the chart of the checkout, compares what the commands print with what the
page shows, and deletes the cluster again. The chart names the base image of
its own version, which the registry has only once that version is released,
so the image is built from the checkout under that name and loaded into the
cluster (`--import`). It needs `docker`, `k3d`,
`kubectl`, `helm` and `curl`, and the ports 8080 and 8443 free; the cluster
gets a kubeconfig of its own, so the current `kubectl` context stays as it
is. Continuous integration runs it on a pull request that changes the chart,
the image, `examples/k3d/` or the runner
([`.github/workflows/try-locally.yml`](.github/workflows/try-locally.yml)).
It is the one test that meets a real ingress controller.

## Pull requests

A pull request is easiest to review when it:

- covers one change, with a test that fails without it: a case in
  `chart/tests/template-test.sh` for the chart, in
  `docker/tests/smoke-test.sh` for the image;
- documents a new value with a `## @param` comment in `chart/values.yaml` and,
  where it needs more than a line, in the section of `chart/README.md` that
  covers it, and gives it its entry in `chart/values.schema.json`, which is
  written by hand: type, the description of the `@param` line and the default
  of `values.yaml`. A changed default is changed in both files.
  `./chart/tests/schema-test.sh` names what is missing; keep the entry as
  permissive as its neighbours, since Helm refuses an install whose values
  the schema does not accept;
- keeps the `<!-- #region name -->` and `<!-- #endregion name -->` comments of
  the READMEs around their sections: the documentation site shows the sections
  by these names;
- adds its lines under `## Unreleased` in
  [`chart/CHANGELOG.md`](chart/CHANGELOG.md) when it changes the chart or
  the image, and leaves the chart version alone, see
  [Versions and releases](#versions-and-releases);
- uses the commit style of the history: a plain imperative summary
  (`Add …`, `Fix …`, `Let …`), with the reason in the body. The commit of a
  release starts with `Version <chart version>: `;
- has every commit signed off, see [Sign your commits (DCO)](#sign-your-commits-dco).

Code, comments, documentation and commit messages are in English.

### Security fixes are worded as hardening

A changelog entry, a commit message and a pull request say what is stricter or
safer now and that upgrading is recommended. They do not describe how an
earlier release could be attacked: installations upgrade at their own pace,
and such a description would point at the ones that have not yet.

A vulnerability that is not public is reported privately first, not fixed in a
public pull request; see [SECURITY.md](SECURITY.md).

## Versions and releases

The chart follows [Semantic Versioning](https://semver.org/), and the chart
version is also the tag of the base image;
[Chart versions](chart/README.md#chart-versions) has the details.

A change to the chart or the image reaches users with the next chart version. The pull
request that makes the change does not raise the version. It adds its lines
under `## Unreleased` at the top of
[`chart/CHANGELOG.md`](chart/CHANGELOG.md), with that heading if it is not
there yet, and says in them what a user of the chart notices. Changes to the
repository alone go under a `### Project and CI` subheading, which the
release leaves out of what Artifact Hub shows.

A release is a pull request of its own. It

1. sets `version` in `chart/Chart.yaml`;
2. sets the tag of the `nginx-static` entry in `artifacthub.io/images`
   there, which must equal `version`: the chart version is the image's tag;
3. turns `## Unreleased` in `chart/CHANGELOG.md` into the heading of that
   version, so that no line is left under `## Unreleased` when it is merged:
   `scripts/changelog-release.sh <version>`.

`./chart/tests/template-test.sh` fails while the two places in
`chart/Chart.yaml` disagree, and when the changelog has neither a section
for the version nor an Unreleased one. The templates take the image's tag
from the chart version itself.

After its merge the maintainers push a tag with the version's name on that
commit (`0.3.0`, without a `v`), and the release workflow
(`.github/workflows/release.yml`) runs:

1. the tests, as a gate for everything that follows;
2. the base image, built for each platform and pushed to the registry under
   its digest, with an SBOM and provenance, and the smoke test on the built
   image;
3. the chart, packaged and pushed under its digest;
4. one job that signs the image and the chart;
5. only then the tags: the version on the image and the chart, and `latest`
   on the image;
6. the GitHub release, with the changelog entry of the version as its notes,
   and "Try it locally" against what was published.

A failed job can be re-run. [Verify a release](README.md#verify-a-release)
has the commands that check the signatures afterwards.

Where a change calls for it, a release candidate comes first: the tag
`<version>-rc.1` on the same commit runs the whole release and publishes
chart and image at the candidate's version, without moving `latest`. A fix goes to `main` by pull request, and
the next candidate, `-rc.2`, on the new head. The release is then tagged on
the commit its last candidate tested.

Tag the release pull request's merge commit by its hash, not whatever
`origin/main` is by then, and push the tag as a step of its own:

```sh
git fetch origin
git merge-base --is-ancestor <commit> origin/main   # the commit is on main
git rev-parse '<version>-rc.1^{commit}'             # after a candidate: the same commit
git tag <version> <commit>
git push origin <version>
```

Renovate opens the pull requests for new versions of GitHub Actions, the
tools the workflows install, NGINX and the Alpine the base image is built
with, the k3s of the page "Try it locally" and the site's packages
(`.github/renovate.json`). The `common` chart the chart depends on moves by
hand, with a release.

A new NGINX release of the stable branch comes as one pull request that
raises `NGINX_VERSION` in `docker/Dockerfile` and `appVersion` in
`chart/Chart.yaml`, which the template test holds equal; it needs its line
under `## Unreleased`. A new stable branch waits for approval on Renovate's
dashboard. The libraries NGINX is linked with are not pinned: every release
build installs Alpine's current packages. When the daily scan reports a fix
for one of them, the next release brings it; a release with nothing else in
it is fine.

A tag is never moved and a version is never published a second time: a
deployment that pins a version would not see the change. The release workflow
refuses a version that is in the registry already. Any change after a
release, however small, gets the next version.

## The documentation site

The site at [nginx-static.ioanalytica.com](https://nginx-static.ioanalytica.com)
is built with [VitePress](https://vitepress.dev/) from `site/` and needs
Node.js 22.18 or later:

```sh
cd site
npm ci --ignore-scripts
npm run dev      # http://localhost:5173, reloads on every change
```

Most pages show sections of `README.md` and `chart/README.md` by region
(`<!-- #region name -->`) instead of copying them, and `chart/CHANGELOG.md`,
`CONTRIBUTING.md`, `SECURITY.md` and `examples/k3d/README.md` whole. So each
text has one source: edit the file and the page follows.

A pull request that changes the site or a file it shows runs these in
continuous integration:

```sh
site/tests/site-test.sh
(cd site && npm run build)
site/scripts/check-links.sh site/.vitepress/dist
```

## Sign your commits (DCO)

Every commit must carry a `Signed-off-by` line, certifying the
[Developer Certificate of Origin](https://developercertificate.org/): that you
wrote the change or otherwise have the right to submit it under the license of
the part it changes. `git commit -s` adds the line from your git name and
e-mail.

There is no contributor license agreement.

## License

nginx-static is licensed under the [Apache License 2.0](LICENSE). A
contribution is accepted under that license. NGINX, which the base image
contains, is licensed under the 2-clause BSD license.

## Conduct

Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md).
