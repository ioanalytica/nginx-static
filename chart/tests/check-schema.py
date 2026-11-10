"""Checks that chart/values.schema.json keeps step with chart/values.yaml.

    check-schema.py CHART_DIR

Helm checks the values of every install, upgrade, template and lint against
the schema, and Artifact Hub shows it as the chart's values reference. Nothing
generates it, so nothing but this check notices a parameter added to
values.yaml and not to the schema, a schema entry whose value is gone, or a
default changed in one file only.

Prints one line per problem and exits 1 if there is any.
"""

import glob
import json
import re
import sys

import yaml

# Entries of this list are single rules with a fixed shape: a host with a
# misspelled key would render an Ingress rule without a host, which matches
# every hostname. Its item schema, and the one of a host's paths, name the
# keys an entry may have and the one it must have. Nowhere else does the
# schema require a key or refuse one it does not list.
STRICT_ITEMS = {"ingress.hosts"}

# The only enums: values of which the chart, the common chart or Kubernetes
# knows a fixed set. A value the schema does not list would be refused before
# the chart could say what it accepts, so a new one has to be added in both
# places.
ENUMS = {
    "ingress.className": ["", "nginx", "nginx-traefik", "traefik"],
    "resourcesPreset": ["", "nano", "micro", "small", "medium", "large", "xlarge", "2xlarge"],
    "ingress.hosts[].paths[].pathType": ["ImplementationSpecific", "Prefix", "Exact"],
}

# Rendered as a template on one path, read as a list on another: the Traefik
# classes take the first entry of redirect.tls (`first`, `len`), which text
# does not have, so the value stays a list.
LIST_ONLY = {"redirect.tls"}

# A template's `if` reads the text "false" as on, so every switch is limited
# to true and false.
SWITCH = re.compile(r"(^|\.)enabled$")


def types(node):
    """The types a schema entry accepts, as a list."""
    t = node.get("type")
    return t if isinstance(t, list) else [t]


def walk(node, path=()):
    """Every property of the schema as (path, node), sections included."""
    for key, child in (node.get("properties") or {}).items():
        yield path + (key,), child
        yield from walk(child, path + (key,))


def lookup(mapping, path):
    """The value at path, or KeyError."""
    for key in path:
        if not isinstance(mapping, dict) or key not in mapping:
            raise KeyError(path)
        mapping = mapping[key]
    return mapping


def schema_node(schema, path):
    """The schema entry of the value at path, or None when it has none."""
    node = schema
    for key in path:
        node = (node.get("properties") or {}).get(key)
        if node is None:
            return None
    return node


def main():
    """Compare the schema of the chart in argv[1] with its values.yaml and
    templates; print the problems and return 1 if there are any."""
    chart = sys.argv[1]
    text = open(f"{chart}/values.yaml").read()
    values = yaml.safe_load(text)
    schema = json.load(open(f"{chart}/values.schema.json"))
    templates = "".join(open(f).read() for f in sorted(glob.glob(f"{chart}/templates/*")))
    problems = []

    if schema.get("$schema") != "http://json-schema.org/draft-07/schema#":
        problems.append(f"$schema is {schema.get('$schema')!r}, expected draft-07")

    # Every documented parameter is in the schema, with the same description.
    params = re.findall(r"^\s*## @param (\S+) (.+)$", text, re.M)
    if len(params) < 50:
        problems.append(f"only {len(params)} @param lines found in values.yaml")
    for param, description in params:
        node = schema_node(schema, param.split("."))
        if node is None:
            problems.append(f"documented in values.yaml, not in the schema: {param}")
        elif node.get("description") != description:
            problems.append(f"the description differs between values.yaml and the schema: {param}")

    documented = {param for param, _ in params}
    props = list(walk(schema))
    for path, node in props:
        name = ".".join(path)
        # Every key of the schema is a key of values.yaml ...
        try:
            default = lookup(values, path)
        except KeyError:
            problems.append(f"in the schema, not in values.yaml: {name}")
            continue
        # ... says what it is ...
        if "type" not in node or not (node.get("description") or node.get("title")):
            problems.append(f"no type, or neither description nor title: {name}")
        # ... and, unless it is a section, is documented in values.yaml and
        # carries its default.
        if "properties" in node:
            if not isinstance(default, dict):
                problems.append(f"a section in the schema, a single value in values.yaml: {name}")
            continue
        if name not in documented:
            problems.append(f"in the schema, without an @param line in values.yaml: {name}")
        if "default" not in node:
            problems.append(f"no default in the schema: {name}")
        elif node["default"] != default or type(node["default"]) is not type(default):
            problems.append(
                f"default differs: {name} is {default!r} in values.yaml, {node['default']!r} in the schema"
            )
        if SWITCH.search(name) and node.get("type") != "boolean":
            problems.append(f"a switch must be limited to true and false: {name}")

    # Every key of values.yaml is in the schema. A map the schema treats as
    # one value (resources, annotations) is not descended into.
    def uncovered(mapping, path=()):
        """Report each key of mapping, a part of values.yaml, that the schema
        lacks, descending where the schema has a section."""
        for key, value in mapping.items():
            node = schema_node(schema, path + (key,))
            if node is None:
                problems.append(f"in values.yaml, not in the schema: {'.'.join(path + (key,))}")
            elif "properties" in node and isinstance(value, dict):
                uncovered(value, path + (key,))

    uncovered(values)

    # Permissive: no key is required and none refused for not being listed,
    # the entries of STRICT_ITEMS excepted.
    def strictness(node, where, inside_strict_items=False):
        """Report `required` and `additionalProperties: false` at node and
        below it, the item schemas of STRICT_ITEMS excepted."""
        if isinstance(node, dict):
            if not inside_strict_items and ("required" in node or node.get("additionalProperties") is False):
                problems.append(f"required or additionalProperties: false at {where or 'the top level'}")
            for key, child in node.items():
                if key == "properties" and isinstance(child, dict):
                    for prop, sub in child.items():
                        strictness(sub, f"{where}.{prop}" if where else prop, inside_strict_items)
                elif key == "items":
                    strictness(child, f"{where}[]", inside_strict_items or where in STRICT_ITEMS)

    strictness(schema, "")

    # Enums: exactly the listed ones.
    found = {}

    def enums(node, where):
        """Collect every enum at node and below it into `found`, keyed by the
        value's path."""
        if isinstance(node, dict):
            if "enum" in node:
                found[where] = node["enum"]
            for prop, sub in (node.get("properties") or {}).items():
                enums(sub, f"{where}.{prop}" if where else prop)
            if "items" in node:
                enums(node["items"], f"{where}[]")

    enums(schema, "")
    if found != ENUMS:
        problems.append(f"enums are {found}, expected {ENUMS}")

    # The ingress classes of the schema are the ones the chart validates.
    allowed = re.search(r'\$allowed := list ((?:"[^"]+" ?)+)', templates)
    chart_classes = re.findall(r'"([^"]+)"', allowed.group(1)) if allowed else []
    if [""] + chart_classes != ENUMS["ingress.className"]:
        problems.append(f"the chart validates the ingress classes {chart_classes}, the schema lists others")

    # Text is a form the chart reads for every value it renders through
    # common.tplvalues.render or merges with common.tplvalues.merge, so the
    # schema may not limit such a value to a list or a map. The call names
    # the value as .Values.x, or as `.` inside `with .Values.x`.
    rendered = set(re.findall(r'tplvalues\.render" *\( *dict "value" \.Values\.([A-Za-z0-9.]+)', templates))
    rendered.update(
        re.findall(
            r'with \.Values\.([A-Za-z0-9.]+) *}}\s*\n[^\n]*tplvalues\.render" *\( *dict "value" \. ',
            templates,
        )
    )
    # Every call has to be in one of these two forms or in one that cannot
    # take text, or a value rendered as a template goes unnoticed here:
    # $annotations is the result of a merge (read below), and a helper's
    # output is a map the chart has merged itself.
    calls = len(re.findall(r'tplvalues\.render" *\( *dict "value" ', templates))
    known = len(
        re.findall(r'tplvalues\.render" *\( *dict "value" (\.Values\.|\. |\$annotations |\(include ")', templates)
    )
    if calls != known:
        problems.append(f"{calls - known} tplvalues.render call(s) name their value in a form this check does not read")
    for merged in re.findall(r'tplvalues\.merge" *\( *dict "values" *\( *list ([^)]*)\)', templates):
        rendered.update(re.findall(r"\.Values\.([A-Za-z0-9.]+)", merged))
    if len(rendered) < 4:
        problems.append(f"only {len(rendered)} values rendered as templates found")
    for name in sorted(rendered - LIST_ONLY):
        node = schema_node(schema, name.split("."))
        if node is None:
            problems.append(f"rendered as a template, not in the schema: {name}")
        elif "string" not in types(node):
            problems.append(f"rendered as a template by the chart, refused as text by the schema: {name}")

    for name in sorted(LIST_ONLY):
        node = schema_node(schema, name.split("."))
        if node is None or node.get("type") != "array":
            problems.append(f"must stay limited to a list: {name}")

    for problem in problems:
        print(problem)
    print(f"{len(params)} documented parameters, {len(props)} schema entries, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
