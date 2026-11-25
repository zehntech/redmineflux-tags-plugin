# Release Notes — flux_tags

## Public release – 25 Nov 2026
- First public release on GitHub. The whole plugin is now licensed under the GNU GPL v2.

## [Unreleased]

### Fixed
- Tags with the same name in different capitals (`bug`, `Bug`, `BUG`) can no longer be created by requests that arrive at the same moment: tag creation and renaming now take turns per name, so there is always one tag

### Removed
- **Tag merge**: merging tags is gone, from the administration page earlier and now from the REST API too (`POST /api/v1/flux_tags/tags/merge`), its API description and its code

### Security
- **Security review (#122319)**: the REST API needs the REST switch and an API key in the header (not in the address); creating, renaming and deleting tags is for administrators (a "Manage tags" role in one project no longer reaches the whole library); retagging a project needs the right on that project; retagging an issue needs the right to edit that issue (form, editor, bulk edit and API alike); a request without `tag_list` no longer removes all tags
- Tag lists, counts, contexts, suggestions and the project tag filter only describe records and projects the reader may see; the record list of a tag is paged in the database
- The API description (`/flux_tags/api_doc`, `/tag-api.yaml`) needs a login and is no longer a public file; the plugin no longer answers every `OPTIONS` request of the site
- Tag names are cleaned (invisible and control characters, 60 characters, 30 per request); the old `POST /update_issue_tags` keeps the same limits and returns a short summary; the CSV export neutralises formulas; `%` and `_` in the autocomplete are no wildcards
- The tag filter of the issue, project and time entry lists is one sub-select (it loaded every tag and tagged record before); the PDF "Parent task" column hides a parent the reader may not see; copying an issue copies its tags only for someone who may set tags; the Google Fonts import was removed
- 26 security tests and a 76-check attack script added; a few old tests were updated to the new rules
- **SEC-001 / rtg-010**: CSRF verification restored on the admin tag actions (rename, merge, delete).
- **SEC-002 / rtg-010**: The REST API no longer shows tags, counts or contexts of Password Manager entries a user cannot see; "Manage Tags" users cannot change tags on such entries.

### Performance
- The tag lists are filtered, sorted and paged in the database; the page loads one page at a time.

### Features
- **Redesigned tag pages** (default Redmine theme, Redmine 5, 6 and 7 from one set of files): new tag input without jQuery UI, Select2 or CDN files; inline editor and chips on the issue page; bulk edit with separate add / remove; a few tags in the issue list sidebar (list or colored tags, "View all" opens the issue list with a tag filter and the Tags column).
- **Tag administration page**: search, sort, usage counts, "Unused" filter, create, rename, delete, select all matching tags across pages, tag detail panel (where a tag is used), "Delete all unused".
- **Tag color and description**: new migration `20261010000001_rf_flux_tags_add_color_and_description_to_tags` adds `tags.rf_flux_tags_color` and `tags.rf_flux_tags_description`.
- **History entry** when tags change through the issue page editor or bulk edit (the issue form already wrote one).
- **API documentation** at `/flux_tags/api_doc` now covers every `/api/v1/flux_tags` endpoint.
- **rtg-010**: Compatibility with the Redmineflux Password Manager (shared tag tables): a "Password Tags" tab under Administration » Plugins » Tags when that plugin is installed (with a warning while it is not yet compatible), and `password_entries` as a tag context in the REST API.

### Bug Fixes
- Unused tags are no longer deleted automatically when an issue is saved (the REST API already behaved this way); they are only deleted on purpose.
- Tag autocomplete responses are no longer cacheable (rtg-001).
- The tags of an issue, project or time entry can only be set through forms, bulk edit or the REST API by users who have the matching `manage_*_tags` permission.
- Merging tags and deleting a tag through the REST API work on Redmine 5 (`taggings_count` is read-only there).
- The issue page no longer puts the user's API key into the page.
- **rtg-010**: Merging tags no longer tags a record twice and keeps the usage count right.
- **rtg-010**: Uninstalling the plugin (`VERSION=0`) completes instead of stopping half way, and keeps the tag tables while another plugin still uses them.
- **rtg-010**: The `taggings_count` migration runs on PostgreSQL; the first migration stops with a clear message on a half-made or foreign tag schema.
- **rtg-010**: Bulk delete from the right-click menu returns to the tab it was made in.

---

## [6.1.0] — 2026-03-26

### Features
- Initial plugin release: {list core features}
