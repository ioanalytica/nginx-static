#!/usr/bin/env python3
"""Check the order and the rights of the release workflow's jobs.

    check-release-workflow.py RELEASE_YML BUILD_IMAGE_YML

One line per broken rule, exit status 1 if there is any:

- sign is the one job with an OIDC token, and build-image.yml asks for none:
  every certificate of a release names release.yml
- the chart waits for the image and its smoke test, sign for the image and
  the chart, tag for sign, release for sign and tag, try-locally for tag,
  and nothing waits for try-locally
- every job sits downstream of the gate
- release is the one job that can write to the repository
- nothing but the tag job sets a tag in the registry: the image and the
  chart are pushed by their digests
- no build argument carries a secret: provenance records build arguments
"""

import sys

import yaml

release = yaml.safe_load(open(sys.argv[1]))["jobs"]
build_text = open(sys.argv[2]).read()
build = yaml.safe_load(build_text)["jobs"]
problems = []


def needs(job):
    """The jobs a job waits for, as a set."""
    n = release[job].get("needs", [])
    return {n} if isinstance(n, str) else set(n)


def upstream(job, seen=None):
    """Every job a job waits for, directly or not."""
    seen = seen if seen is not None else set()
    for n in needs(job):
        if n not in seen:
            seen.add(n)
            upstream(n, seen)
    return seen


for job in ("gate", "prep", "image", "smoke", "chart", "sign", "tag", "release", "try-locally"):
    if job not in release:
        problems.append(f"release.yml has no job {job}")
if problems:
    print("\n".join(problems))
    sys.exit(1)

oidc = [name for name, job in release.items() if (job.get("permissions") or {}).get("id-token") == "write"]
if oidc != ["sign"]:
    problems.append(f"the jobs with an OIDC token are {oidc}, not sign alone")
for job in build.values():
    if (job.get("permissions") or {}).get("id-token"):
        problems.append("build-image.yml asks for an OIDC token; its certificates would name another workflow")
if "image" not in needs("smoke"):
    problems.append("smoke does not wait for image")
if not {"image", "smoke"} <= needs("chart"):
    problems.append("chart does not wait for the image and its smoke test")
for job in ("image", "chart"):
    if job not in needs("sign"):
        problems.append(f"sign does not wait for {job}")
if "sign" not in needs("tag"):
    problems.append("tag does not wait for sign")
if not {"sign", "tag"} <= needs("release"):
    problems.append("release does not wait for sign and tag")
if "tag" not in needs("try-locally"):
    problems.append("try-locally does not wait for tag")
for name in release:
    if name != "gate" and "gate" not in upstream(name):
        problems.append(f"{name} does not sit downstream of the gate")
    if "try-locally" in needs(name):
        problems.append(f"{name} waits for try-locally")
writers = [name for name, job in release.items() if (job.get("permissions") or {}).get("contents") == "write"]
if writers != ["release"]:
    problems.append(f"the jobs that can write to the repository are {writers}, not release alone")
# Nothing but the tag job sets a tag: the build pushes by digest, the chart
# goes through the runner's registry and is copied by its digest, and oras
# tag and oras push with a tag stand in the tag job or in the scripts it
# runs.
if "push-by-digest=true" not in build_text or "oras manifest push" not in build_text:
    problems.append("build-image.yml does not push by digest")
if "sbom: true" not in build_text or "provenance: mode=max" not in build_text:
    problems.append("build-image.yml does not ask for an SBOM and provenance")
if "secrets." in str((release["image"].get("with") or {}).get("build-args", "")):
    problems.append("job image passes a secret as a build argument; provenance records build arguments")
for name, job in list(release.items()) + list(build.items()):
    for step in job.get("steps") or []:
        run = str(step.get("run", ""))
        if name != "tag" and ("oras tag" in run or "oras push" in run or "release-tag-" in run or "release-artifacthub-metadata" in run):
            problems.append(f"job {name} sets a tag outside the tag job")
        if "secrets." in str((step.get("with") or {}).get("build-args", "")):
            problems.append(f"job {name} passes a secret as a build argument; provenance records build arguments")
        if "helm push" in run and "oci://localhost:" not in run:
            problems.append(f"job {name} pushes the chart to a registry other than the runner's, which would tag it")
push = "".join(str(step.get("run", "")) for step in release["chart"].get("steps") or [])
if "oras cp" not in push or "@$digest" not in push:
    problems.append("the chart job does not copy the chart into the registry by its digest")
print("\n".join(problems))
sys.exit(1 if problems else 0)
