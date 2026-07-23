---
name: google_drive_oauth
description: >
  Use when reading or writing files in a Google Drive account via a
  hearth resource connection — including editing the contents of native
  Google Docs, Sheets, and Slides. Covers listing, searching, downloading,
  uploading, organising, and editing files through the google_drive_oauth plugin.
---

# Google Drive plugin

Invoke via `hearth resource invoke <connection> <verb> '<args-json>'`.

`<connection>` is the name shown in your resource list — either the slug
(e.g. `my_drive`) or the connection UUID. Both resolve. Examples below
use `my_drive`; substitute the connection you were actually granted.

## Passing arguments

Args are **one JSON object**, quoted as a single shell argument. There is no
`--arg` flag. Omit the object entirely for a verb that takes no args:

```
hearth resource invoke my_drive list_files
hearth resource invoke my_drive get_file_metadata '{"file_id":"<id>"}'
```

Args whose name ends in `_json` take a **string containing JSON**, so that
JSON is escaped inside the outer object (`"items_json": "[{\"id\":\"a\"}]"`,
not a nested array). No Drive verb currently takes a `_json` arg — every arg
here is a plain string — but the rule holds if one is added.

## Finding files

Start with a search rather than a listing when you know what you're looking for:

```
hearth resource invoke my_drive search_files '{"query":"name contains '\''budget'\''"}'
hearth resource invoke my_drive search_files '{"query":"fullText contains '\''Q3 revenue'\''"}'
hearth resource invoke my_drive search_files '{"query":"mimeType = '\''text/plain'\''"}'
```

Drive query syntax uses single quotes, which collide with the single quotes
wrapping the JSON. The `'\''` sequence above closes, escapes, and reopens the
shell quote. Double-quoting the whole argument and escaping the inner double
quotes works too:

```
hearth resource invoke my_drive search_files "{\"query\":\"name contains 'budget'\"}"
```

Queries follow Google's Drive query syntax:
https://developers.google.com/drive/api/guides/search-files

To list the contents of a known folder, use the folder's Drive ID (from its
URL or from a previous search result):

```
hearth resource invoke my_drive list_folder_contents '{"folder_id":"1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms"}'
```

Pass `"folder_id": "root"` for the top of My Drive.

## Reading file content

For plain text, Markdown, code, CSV, PDF — use `download_file`:

```
hearth resource invoke my_drive download_file '{"file_id":"<id>"}'
```

For Google Workspace files (Docs, Sheets, Slides) — use `export_file` with
a target MIME type:

```
# Google Doc → plain text
hearth resource invoke my_drive export_file '{"file_id":"<id>","mime_type":"text/plain"}'

# Google Doc → Word
hearth resource invoke my_drive export_file '{"file_id":"<id>","mime_type":"application/vnd.openxmlformats-officedocument.wordprocessingml.document"}'

# Google Sheet → CSV
hearth resource invoke my_drive export_file '{"file_id":"<id>","mime_type":"text/csv"}'

# Any file → PDF
hearth resource invoke my_drive export_file '{"file_id":"<id>","mime_type":"application/pdf"}'
```

`download_file` on a Google Workspace file returns an error — use `export_file`
for those types.

## Getting a file's metadata

Before moving, renaming, or trashing a file, read its current state:

```
hearth resource invoke my_drive get_file_metadata '{"file_id":"<id>"}'
```

The response includes `parents` (the current parent folder IDs) — you need
this for `move_file`.

## Creating files

`create_file` creates a metadata-only record and returns the new file's `id`.
You must supply a `parent_id`; pass `"root"` for My Drive root.

```
# Create an empty text file
hearth resource invoke my_drive create_file '{
  "name": "notes.md",
  "mime_type": "text/markdown",
  "parent_id": "root"
}'

# Create an empty Google Doc
hearth resource invoke my_drive create_file '{
  "name": "Draft",
  "mime_type": "application/vnd.google-apps.document",
  "parent_id": "<folder_id>"
}'
```

To set the file's content immediately, follow with `upload_file_content`:

```
hearth resource invoke my_drive upload_file_content '{
  "file_id": "<id>",
  "mime_type": "text/markdown",
  "content": "# My document\n\nContent here."
}'
```

`upload_file_content` replaces the entire file content. It works for plain
text and other non-binary formats. For Google Docs/Sheets, write to a plain
text file and let the user convert, or use the Docs API (not this plugin).

## Organising files

Rename:
```
hearth resource invoke my_drive rename_file '{"file_id":"<id>","name":"New name.md"}'
```

Move (requires the current parent ID — get it from `get_file_metadata`):
```
hearth resource invoke my_drive move_file '{
  "file_id": "<id>",
  "new_parent_id": "<destination_folder_id>",
  "old_parent_id": "<current_parent_id>"
}'
```

Create a folder:
```
hearth resource invoke my_drive create_folder '{"name":"2026 Reports","parent_id":"root"}'
```

Trash (recoverable from Drive's Trash):
```
hearth resource invoke my_drive trash_file '{"file_id":"<id>"}'
```

Trashing is always preferred over permanent deletion. There is no
permanent-delete verb — use the Drive web UI for that.

## Sharing files

```
# Share with a specific user
hearth resource invoke my_drive share_file '{
  "file_id": "<id>",
  "role": "writer",
  "type": "user",
  "email_address": "colleague@example.com"
}'

# Share with everyone in a domain
hearth resource invoke my_drive share_file '{
  "file_id": "<id>",
  "role": "reader",
  "type": "domain",
  "email_address": "vergelabs.org"
}'

# Make publicly readable
hearth resource invoke my_drive share_file '{
  "file_id": "<id>",
  "role": "reader",
  "type": "anyone",
  "email_address": ""
}'
```

Roles: `reader`, `commenter`, `writer`, `fileOrganizer`, `organizer`, `owner`.

`email_address` is required on every `share_file` call — pass an empty string
when `type` is `anyone`.

## Editing Google Docs, Sheets & Slides

Beyond storing files, this plugin edits the *contents* of native Google
Workspace files through the Docs, Sheets, and Slides APIs. The verbs are
prefixed by type: `doc_*`, `sheet_*`, `slides_*`.

You can edit any Doc, Sheet, or Slides file the user shares with you by link —
paste the file's ID into the relevant verb. You can also create a fresh file
and edit it:

```
# Create an empty Google Doc, capture its id from the response
hearth resource invoke my_drive create_file '{"name":"Neighbor letter","mime_type":"application/vnd.google-apps.document"}'
# Edit it by that id
hearth resource invoke my_drive doc_append_text '{"document_id":"<id>","text_json":"\"Dear neighbor,\\n\\nThanks for ...\""}'
```

(create_file's `parent_id` is optional — omit it to land in the connection's
base folder.)

### The `_json` text rule — read this first

Editing request bodies are assembled as raw JSON and the engine does **not**
escape your values. So every free-text field is passed as a `_json` argument
whose value is the **JSON encoding** of your text — i.e. run the text through a
JSON string encoder, surrounding quotes included. The plain word `Hello`
becomes the value `"Hello"`; multi-line text keeps its `\n` escapes. This lets
your content carry quotes, newlines, and Unicode safely. Spreadsheet data uses
the same rule via `values_json` (a JSON-encoded 2D array of rows).

Concretely, to append the two lines `Dear neighbor,` / `Thanks for ...` you set
`text_json` to `"Dear neighbor,\n\nThanks for ..."` — which, once that value is
itself placed inside the argument object, appears as the doubly-escaped
`"\"Dear neighbor,\\n\\nThanks for ...\""` shown above. When in doubt, JSON-
encode the text once and let the argument object's own JSON quoting stack on
top.

### Google Docs

To READ a Doc's text, prefer `export_file` (Doc → text/plain) when Hearth
created the file; for a file the user shared, use `doc_get` (it returns the full
structured document — also the source of the character indices for precise
edits).

```
# Append text to the end of the doc
hearth resource invoke my_drive doc_append_text '{"document_id":"<id>","text_json":"\"\\n## Next steps\\n\""}'

# Fill a placeholder throughout the doc (case-sensitive find/replace)
hearth resource invoke my_drive doc_replace_text '{"document_id":"<id>","find_json":"\"[[NAME]]\"","replace_json":"\"Jane Doe\""}'

# Delete text by replacing it with the empty string
hearth resource invoke my_drive doc_replace_text '{"document_id":"<id>","find_json":"\"DRAFT — \"","replace_json":"\"\""}'
```

`doc_replace_text` is the workhorse for template documents: author a Doc with
`[[PLACEHOLDER]]` tokens, then replace each one.

### Google Sheets

`range` is A1 notation, e.g. `Sheet1!A1:D100`. If a tab name contains spaces or
punctuation, percent-encode the range (space → `%20`, `'` → `%27`); simple
ranges need no encoding.

```
# Discover the tab names first
hearth resource invoke my_drive sheet_get '{"spreadsheet_id":"<id>"}'

# Read a range
hearth resource invoke my_drive sheet_read_range '{"spreadsheet_id":"<id>","range":"Sheet1!A1:C10"}'

# Overwrite a range (values_json is a JSON 2D array of rows)
hearth resource invoke my_drive sheet_update_range '{"spreadsheet_id":"<id>","range":"Sheet1!A1","values_json":"[[\"Item\",\"Qty\"],[\"Bolts\",40]]"}'

# Append rows to the bottom of a table
hearth resource invoke my_drive sheet_append_rows '{"spreadsheet_id":"<id>","range":"Sheet1!A1","values_json":"[[\"Nuts\",100]]"}'

# Clear a range's values (formatting is kept)
hearth resource invoke my_drive sheet_clear_range '{"spreadsheet_id":"<id>","range":"Sheet1!A2:C99"}'

# Add a new tab
hearth resource invoke my_drive sheet_add_tab '{"spreadsheet_id":"<id>","title":"2026 Budget"}'
```

Values are interpreted as if typed into the UI: `42` becomes a number,
`2026-01-01` a date, and a string starting with `=` a formula. For update and
append, the range's top-left cell is just the anchor — you don't need to size
the range to the data.

### Google Slides

```
# Inspect slides and their element objectIds
hearth resource invoke my_drive slides_get '{"presentation_id":"<id>"}'

# Fill placeholders across the whole deck (great for template decks)
hearth resource invoke my_drive slides_replace_text '{"presentation_id":"<id>","find_json":"\"{{CLIENT}}\"","replace_json":"\"The Smiths\""}'

# Add a slide (layout optional; defaults to TITLE_AND_BODY)
hearth resource invoke my_drive slides_add_slide '{"presentation_id":"<id>","layout":"TITLE_ONLY"}'
```

To put fresh text on a new slide, add the slide, then either run
`slides_replace_text` against its layout placeholder text, or read `slides_get`
for the new text box's objectId. To insert into a specific shape by its
objectId, use `slides_insert_text`:

```
hearth resource invoke my_drive slides_insert_text '{"presentation_id":"<id>","object_id":"<shape_object_id>","text_json":"\"Q3 Results\""}'
```

### Copying files (templates)

`copy_file` duplicates a file — the backbone of template workflows: keep a
master template Doc/Sheet, copy it, then fill the copy with `doc_replace_text` /
`sheet_update_range`.

```
hearth resource invoke my_drive copy_file '{"file_id":"<template_id>","name":"Invoice — Smith"}'
# then edit the returned copy's id
```

`parent_id` is optional — omit it to land in the base folder. On this OAuth
connection `copy_file` works on files **Hearth created**; to copy a template the
user made by hand, use the service-account plugin.

### Comments

Read a file's comment thread, add a comment, or reply to one.

```
hearth resource invoke my_drive comment_list '{"file_id":"<id>"}'
hearth resource invoke my_drive comment_create '{"file_id":"<id>","content_json":"\"Looks good — one typo in para 2.\""}'
hearth resource invoke my_drive comment_reply '{"file_id":"<id>","comment_id":"<comment_id>","content_json":"\"Fixed, thanks.\""}'
```

Comment and reply text follow the same `_json` rule. On this OAuth connection,
comments are reachable only on files **Hearth created**.

### Precise Docs edits

When append and find/replace aren't enough, edit by character index — get the
indices from `doc_get`:

```
# Insert text at an index (1 = start of body)
hearth resource invoke my_drive doc_insert_text_at '{"document_id":"<id>","index":25,"text_json":"\"inserted \""}'

# Delete the content in the range [start, end)
hearth resource invoke my_drive doc_delete_range '{"document_id":"<id>","start_index":10,"end_index":20}'

# Format a range: style_json is a Docs TextStyle object, fields names what you set
hearth resource invoke my_drive doc_format_text '{"document_id":"<id>","start_index":1,"end_index":12,"style_json":"{\"bold\":true}","fields":"bold"}'
hearth resource invoke my_drive doc_format_text '{"document_id":"<id>","start_index":1,"end_index":40,"style_json":"{\"link\":{\"url\":\"https://example.com\"}}","fields":"link"}'
```

`style_json` is a raw JSON object (a Docs `TextStyle`); `fields` must name
exactly the keys you set. This verb is character styling only — headings and
other paragraph styles aren't exposed.

### Sheets tab management

`sheet_id` is the numeric id from `sheet_get` (not the tab's title):

```
hearth resource invoke my_drive sheet_duplicate_tab '{"spreadsheet_id":"<id>","sheet_id":0,"new_title":"2027 copy"}'
hearth resource invoke my_drive sheet_delete_tab '{"spreadsheet_id":"<id>","sheet_id":123456}'
```

### What you can reach

- **Docs / Sheets / Slides**: read and edit **any** such file the user shares
  by link — the `doc_*`/`sheet_*`/`slides_*` verbs cover pre-existing files, not
  just ones Hearth created.
- **General Drive operations** (`list_files`, `search_files`,
  `get_file_metadata`, `download_file`, `export_file`, `create_file`, `move`,
  `trash`, `share`) are limited to files **Hearth created**. So `search_files`
  and `list_files` only surface Hearth's own files — if the user wants you to
  work on one of their existing files, **ask them for its link** rather than
  trying to search for it.

### Explain the access model when it trips the user up

The user sees their entire Drive; you do not. A common trap: they say "open the
Budget file in my Drive" or "the PDF I just uploaded," assuming you see what
they see — not realizing you're limited to files you created, plus Google Docs,
Sheets, and Slides they hand you by link. When you hit this — a file you can't
find, or a Drive call that fails on something the user clearly expects you to
reach — don't just surface a raw error. Briefly explain how your access works
and how to unblock you:

- **A Google Doc, Sheet, or Slides**: ask for its share link (or the browser
  URL). Pull the file ID out of it and use the `doc_*`/`sheet_*`/`slides_*`
  verbs — you can read and edit it directly, no setup needed.
- **Any other file** (PDF, Word/Excel/PowerPoint, image, an entire folder), or
  searching/browsing their Drive at large: you can't reach these unless you
  created them. Say so plainly, and offer what you *can* do — e.g. they can
  paste the contents to you directly, or an administrator can set up the
  Workspace (service-account) connection, which isn't limited this way.

Frame it as Hearth keeping your Drive access deliberately narrow — a privacy
boundary, not a malfunction — so the user understands it's working as intended.

## File IDs vs names

Drive uses opaque file IDs, not paths. Whenever you need to act on a file
you haven't seen yet:
1. `search_files` or `list_folder_contents` to find it
2. Copy the `id` from the result
3. Pass that `id` to the target verb

Never guess or construct a file ID.

## list_files returns 50 results

`list_files` returns the 50 most recently modified non-trashed files. There
is no pagination in v1. For targeted results, use `search_files` or
`list_folder_contents` instead.
