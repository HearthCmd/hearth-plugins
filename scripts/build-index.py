#!/usr/bin/env python3
"""Build index.json from the plugins/ tree.

The index is the only file the hearth CLI parses when installing from this
catalog. It names every plugin, its current version, and the sha256 of each
of its files. One detached signature over this file therefore covers the
entire catalog *including version numbers*, which is what makes rollback
attacks (serving an old vulnerable plugin) detectable — per-file signatures
would not, since every old file remains validly signed.

Deliberately deterministic: sorted keys, no timestamp, LF endings, trailing
newline. Rebuilding an unchanged tree must produce byte-identical output, so
"does this index match these files" is answerable by rebuilding and diffing.
That property is worth more than an embedded build date.

The index is NOT committed. It is generated at release time and uploaded as
a release asset next to catalog.tar.gz. A committed index can silently drift
from the manifests it describes; a generated one cannot.

Usage:
    scripts/build-index.py <catalog_version> [output_path]
"""

import hashlib
import json
import os
import sys

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required: pip install pyyaml (or apt install python3-yaml)")

INDEX_SCHEMA = 1

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLUGINS_DIR = os.path.join(REPO_ROOT, "plugins")

# Files we publish for a plugin. Anything else in the directory is ignored
# rather than silently shipped — an author's scratch notes or editor backups
# must not become part of a signed artifact.
PUBLISHED_FILES = ("manifest.yaml", "skill.md")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


DESCRIPTION_MAX = 240


def short_description(manifest):
    """The manifest description's first paragraph, unwrapped.

    Exists so a browse UI (and the server-side poller in phase 2) can render
    a plugin list without fetching and parsing every manifest.

    Manifest descriptions are hand-wrapped YAML block scalars, so the first
    *line* is usually a sentence fragment ("...via the"). Joining the first
    paragraph and collapsing whitespace gives a usable sentence; the trailing
    paragraphs are AUTH notes and cross-references that belong in the detail
    view, not a list row.
    """
    desc = manifest.get("description") or ""
    paragraph = []
    for line in desc.splitlines():
        line = line.strip()
        if not line:
            if paragraph:
                break
            continue
        paragraph.append(line)
    text = " ".join(paragraph)
    if len(text) <= DESCRIPTION_MAX:
        return text
    # Truncate on a word boundary so the ellipsis doesn't land mid-word.
    clipped = text[:DESCRIPTION_MAX].rsplit(" ", 1)[0]
    return clipped + "…"


def discover_plugins():
    """Yield (slug, directory) for every plugins/<namespace>/<name>/."""
    if not os.path.isdir(PLUGINS_DIR):
        sys.exit("no plugins/ directory at %s" % PLUGINS_DIR)
    for namespace in sorted(os.listdir(PLUGINS_DIR)):
        ns_dir = os.path.join(PLUGINS_DIR, namespace)
        if not os.path.isdir(ns_dir):
            continue
        for name in sorted(os.listdir(ns_dir)):
            plugin_dir = os.path.join(ns_dir, name)
            if not os.path.isfile(os.path.join(plugin_dir, "manifest.yaml")):
                continue
            yield "%s/%s" % (namespace, name), plugin_dir


def build_entry(slug, plugin_dir):
    with open(os.path.join(plugin_dir, "manifest.yaml")) as f:
        manifest = yaml.safe_load(f)

    # The directory path IS the slug. The hearth daemon enforces the same
    # invariant at load time (plugin_registry.go), and the whole install
    # addressing scheme falls apart if the two disagree, so catch it here
    # rather than shipping a catalog that cannot be installed.
    declared = manifest.get("plugin_slug")
    if declared != slug:
        sys.exit("%s: manifest.plugin_slug is %r; must equal its directory path"
                 % (slug, declared))

    version = manifest.get("version")
    if not version:
        sys.exit("%s: manifest has no version" % slug)

    schema = manifest.get("manifest_schema")
    if not schema:
        sys.exit("%s: manifest has no manifest_schema" % slug)

    # Declarative-only through the fetch path. A declarative manifest is YAML
    # describing HTTP calls; a binary plugin is arbitrary code running as the
    # daemon user. Those are different risk classes and must not share a
    # trust path, so a binary plugin cannot enter the catalog at all.
    if manifest.get("executable"):
        sys.exit("%s: declares an executable. Only declarative plugins may be "
                 "published to this catalog; binary plugins install from a "
                 "local archive, where a human handled the file." % slug)

    files = {}
    for filename in PUBLISHED_FILES:
        path = os.path.join(plugin_dir, filename)
        if os.path.isfile(path):
            files[filename] = sha256_file(path)

    entry = {
        "version": str(version),
        "display_name": manifest.get("display_name") or slug,
        "description": short_description(manifest),
        "manifest_schema": int(schema),
        "files": files,
    }
    if manifest.get("auth_scheme"):
        entry["auth_scheme"] = manifest["auth_scheme"]
    if manifest.get("min_daemon_version"):
        entry["min_daemon_version"] = str(manifest["min_daemon_version"])
    return entry


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    catalog_version = sys.argv[1]
    out_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO_ROOT, "index.json")

    plugins = {}
    for slug, plugin_dir in discover_plugins():
        plugins[slug] = build_entry(slug, plugin_dir)

    if not plugins:
        sys.exit("no plugins found under %s" % PLUGINS_DIR)

    index = {
        "schema": INDEX_SCHEMA,
        "catalog_version": catalog_version,
        "plugins": plugins,
    }

    body = json.dumps(index, indent=2, sort_keys=True) + "\n"
    with open(out_path, "w", newline="\n") as f:
        f.write(body)

    print("wrote %s (%d plugins, catalog_version=%s)"
          % (out_path, len(plugins), catalog_version))


if __name__ == "__main__":
    main()
