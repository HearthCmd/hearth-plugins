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

That writes `dist/index.json` and `dist/catalog.tar.gz`. Sign the index (see
below), then create a GitHub release on the tag and upload all three files.
The CLI resolves them by exact filename, so don't rename them.

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

## Signing

TLS proves you reached github.com. It does not prove github.com served what we
published — a compromised repo, a stolen credential, or a bad upload all serve
perfectly valid TLS. The signature closes that gap, and it is the only reason
`hearth plugin install <name>` is meaningfully safer than piping a URL into a
shell.

`index.json` is signed with Ed25519. `index.json.sig` is the raw 64-byte
detached signature. Because the index carries a hash of every published file,
one signature covers the whole catalog.

### Setup, once

Requires real OpenSSL — macOS ships LibreSSL, which cannot do Ed25519:

```bash
brew install openssl@3
scripts/keygen.sh ~/secure/
```

That prints the public key as hex. Paste it into hearth-cmd's
`cli/plugin_catalog_verify.go`:

```go
var trustedCatalogKeys = []string{
    "…hex…",
}
```

**The private key is the whole security model.** Anyone holding it can publish
a catalog every hearth binary installs without question. It must never exist
on the relay server, on a build box, in CI, or in this repo. Generate it where
it will live so it never has to travel.

### Each release

Signing is deliberately not part of `release.sh`: the build runs wherever the
repo lives, the key lives in cold storage somewhere else, and wiring them
together would mean copying the key onto the build box.

```bash
# on the build machine
scripts/release.sh 2026.07.21
#   → copy dist/index.json and dist/catalog.tar.gz to the signing machine

# on the signing machine
scripts/sign-index.sh index.json ~/secure/hearth-catalog-signing.key
#   → upload index.json, index.json.sig, catalog.tar.gz to the release
```

`sign-index.sh` verifies what it just produced before handing it back — a
signature that doesn't check out is worth catching before publication, not
after every host starts refusing to install.

### Rotation

**Rotation is a two-release process, not a swap.** The trusted keys are
compiled into each binary, so:

1. Ship a hearth release trusting **both** the old and new keys.
2. Wait for it to propagate. Binaries that never update keep trusting only
   the old key.
3. Ship a release trusting only the new key.

Signing with a key that isn't in a host's binary makes the catalog
uninstallable for that host, which is why step 1 cannot be skipped.

The honest limitation: there is **no revocation channel**. A binary trusting a
compromised key keeps trusting it until it updates. The lever that forces
updates is the server-side `HEARTH_MIN_CLI` gate.

---

## Contributing

Community plugin authoring isn't open yet — the signing and review process
that would make third-party plugins safe to distribute doesn't exist. If
you've built something you'd like to see here, open an issue.
