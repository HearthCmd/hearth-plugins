# Hearth plugins

The plugin catalog for [Hearth Cmd](https://hearthcmd.com). Each plugin
connects your agents to an outside service — your calendar, your files, your
smart home — through a declared, permissioned set of actions.

Install one on a host with:

```bash
hearth plugin install verge_labs/google_calendar_oauth
```

Browsing this page **is** the discovery mechanism for now: find the plugin you
want below, copy its slug, and install it. There is no `hearth plugin search`
yet.

---

## Available plugins

| Slug | Name | Auth | What it does |
|---|---|---|---|
| `verge_labs/google_calendar_oauth` | Google Calendar | OAuth | Create and manage Google Calendar events. Connects as you. |
| `verge_labs/google_calendar` | Google Calendar (Service Account) | Service account | Same, for Google Workspace acting as any user. |
| `verge_labs/google_drive_oauth` | Google Drive | OAuth | Read and write Drive files. Limited to files Hearth creates or you explicitly open. |
| `verge_labs/google_drive` | Google Drive (Service Account) | Service account | Same, for Workspace-wide access. |
| `verge_labs/google_people_oauth` | Google Contacts | OAuth | Look up family, neighbours, the plumber, the kids' school. |
| `verge_labs/google_people` | Google People (Service Account) | Service account | Look up people in a Workspace organization. |
| `verge_labs/home_assistant` | Home Assistant | API key | Control Home Assistant entities — lights, scenes, climate. |
| `verge_labs/github` | GitHub | API key | Read and write GitHub issues, pull requests, files, and commits. |

Pick the **OAuth** variant unless you administer a Google Workspace domain. It
connects as a single ordinary Google account and needs no domain-wide
delegation. Each connection authenticates as exactly one account — for a second
account, make a second connection.

---

## What a plugin is

A plugin is **declarative**: a `manifest.yaml` describing HTTP calls, plus an
optional `skill.md` that teaches an agent how to use them. There is no
executable and no plugin process — the Hearth daemon makes the calls itself.

That is a deliberate constraint, not a limitation we intend to lift casually.
A manifest can only do what it declares, and every verb in it is subject to
your permission rules. Arbitrary code running as your daemon user is a very
different risk, so binary plugins cannot be published here at all; they install
from a local archive, where a human handled the file.

```
plugins/<namespace>/<name>/
  manifest.yaml     # required — verbs, credentials, config schema
  skill.md          # optional — agent-facing usage notes
```

The directory path must equal the manifest's `plugin_slug`. The index builder
and the daemon both enforce this.

### Compatibility

A manifest may declare `min_daemon_version`. It means "this plugin needs a
runtime feature that older hearth binaries don't have" — for example
`verge_labs/google_drive_oauth` uses the `||` fallback operator in its
templates, which older binaries parse as a literal path. Declaring the floor
turns a confusing runtime error into a refusal at install time telling you to
run `hearth update`.

This is distinct from `manifest_schema`, which says which *format* the
manifest is written in.

---

## Releases

`index.json` is **not** committed. It is generated at release time and
uploaded as a release asset, because a committed index can drift from the
manifests it claims to describe.

```bash
scripts/release.sh 2026.07.21
```

That writes `dist/index.json`, `dist/catalog.tar.gz`, and (once signing is
wired up) `dist/index.json.sig`. Create a GitHub release on the tag and upload
all three.

Both artifacts are **reproducible**: the index has sorted keys and no
timestamp, and the tarball is built with a fixed mtime and owner. Rebuilding
an unchanged tree yields byte-identical files, so "do these artifacts match
this tree?" is answerable by rebuilding and comparing hashes.

### index.json

```json
{
  "schema": 1,
  "catalog_version": "2026.07.21",
  "plugins": {
    "verge_labs/google_drive_oauth": {
      "version": "0.1.3",
      "display_name": "Google Drive",
      "description": "Read and write files in Google Drive…",
      "auth_scheme": "oauth2_user",
      "manifest_schema": 2,
      "min_daemon_version": "1.1.0",
      "files": {
        "manifest.yaml": "<sha256 hex>",
        "skill.md": "<sha256 hex>"
      }
    }
  }
}
```

The index carries the sha256 of every published file, so one signature over
this one file covers the whole catalog **including version numbers**. That is
what makes a rollback attack — serving an old, vulnerable plugin — detectable.
Per-file signatures would not, because every old file remains validly signed.

The CLI additionally cross-checks the index's `version` against the extracted
`manifest.yaml` and refuses on mismatch, so a bad index build fails loudly
instead of installing something mislabelled.

---

## Contributing

Community plugin authoring isn't open yet — the signing and review process
that would make third-party plugins safe to distribute doesn't exist. If
you've built something you'd like to see here, open an issue.
