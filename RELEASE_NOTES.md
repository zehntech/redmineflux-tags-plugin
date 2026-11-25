# Release Notes — flux_tags

## Public release – 25 Nov 2026
- First public release on GitHub. The whole plugin is now licensed under the GNU GPL v2.

## [Unreleased]

### Security
- **SEC-001 / rtg-010**: CSRF verification restored on the admin tag actions (rename, merge, delete).
- **SEC-002 / rtg-010**: The REST API no longer shows tags, counts or contexts of Password Manager entries a user cannot see; "Manage Tags" users cannot change tags on such entries.

### Performance
- (none)

### Features
- **rtg-010**: Compatibility with the Redmineflux Password Manager (shared tag tables): a "Password Tags" tab under Administration » Plugins » Tags when that plugin is installed (with a warning while it is not yet compatible), and `password_entries` as a tag context in the REST API.

### Bug Fixes
- **rtg-010**: Merging tags no longer tags a record twice and keeps the usage count right.
- **rtg-010**: Uninstalling the plugin (`VERSION=0`) completes instead of stopping half way, and keeps the tag tables while another plugin still uses them.
- **rtg-010**: The `taggings_count` migration runs on PostgreSQL; the first migration stops with a clear message on a half-made or foreign tag schema.
- **rtg-010**: Bulk delete from the right-click menu returns to the tab it was made in.

---

## [6.1.0] — 2026-03-26

### Features
- Initial plugin release: {list core features}
