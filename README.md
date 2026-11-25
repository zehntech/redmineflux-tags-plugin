<p align="center">
  <img src="https://www.redmineflux.com/wp-content/uploads/2025/10/Redmineflux-logo.svg" alt="Redmineflux" width="280" />
</p>

<h1 align="center">Redmineflux Tags Plugin</h1>

<p align="center">
  <strong>Freeform issue tagging, cross-project filtering, and a shared tag library for Redmine — without changing your tracker or category configuration.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Redmine-7.x-red?logo=ruby&logoColor=white" alt="Redmine 7.x" />
  <img src="https://img.shields.io/badge/version-7.0.0-blue" alt="Version" />
  <img src="https://img.shields.io/badge/Ruby-3.1+-CC342D?logo=ruby&logoColor=white" alt="Ruby" />
  <img src="https://img.shields.io/badge/Rails-7.x-CC0000?logo=rubyonrails&logoColor=white" alt="Rails" />
  <img src="https://img.shields.io/badge/JavaScript-ES6+-F7DF1E?logo=javascript&logoColor=black" alt="JavaScript" />
  <img src="https://img.shields.io/badge/license-GPL%20v2-blue" alt="License: GPL v2" />
</p>

<p align="center">
  <a href="https://www.redmineflux.com/product/redmine-plugins/tags-plugin/">Website</a> ·
  <a href="https://www.redmineflux.com/knowledge-base/">Knowledge Base</a> ·
  <a href="#api">API</a> ·
  <a href="#installation">Installation</a>
</p>

---

# Overview

## Redmineflux Tag Plugin

## Introduction

The Redmineflux Tag Plugin adds flexible tagging across your Redmine instance so teams can organize and retrieve data faster.

You can apply tags to:

- Issues
- Time entries
- Projects

It also includes centralized tag administration (rename, delete), autocomplete support, and API documentation for tag endpoints.

## Table of Contents

- [Installation](#installation)
- [Getting Started](#getting-started)
- [Features](#features)
- [API Access](#api-access)
- [Uninstallation](#uninstallation)
- [Version Compatibility](#version-compatibility)
- [Libraries](#libraries)

## Installation

To install the Redmineflux Tag Plugin, follow these steps:

1. Ensure you have a working Redmine installation.
2. Place the plugin in your Redmine `plugins` directory and keep the folder name as `flux_tags`.
3. Install plugin dependencies:

```sh
bundle install
```

4. Run database migrations.

Production:

```sh
RAILS_ENV=production bundle exec rails redmine:plugins:migrate
```

Development:

```sh
RAILS_ENV=development bundle exec rails redmine:plugins:migrate
```

5. Restart your Redmine server.

```sh
rails s
```

## Getting Started

1. As an administrator, verify plugin settings in:
   `Administration -> Plugins -> Redmineflux Tags plugin -> Configure`
2. Enable permissions as needed for roles:
   - `manage_project_tags`
   - `manage_issues_tags`
   - `manage_time_entries_tags`
3. Open an issue, project, or time entry form and start adding tags using the tag input field.
4. Use autocomplete to select existing tags or create new ones directly from the input.
5. From the plugin settings tabs (`Issue Tags`, `Time Entry Tags`, `Project Tags`), manage tags: search, sort, see how often each tag is used, create, rename (with color and description) and delete, open a tag to see where it is used, and clear out unused tags.

## Features

- Tagging for issues, time entries, and projects
- Shared tags with the Redmineflux Password Manager (see [Password Manager Compatibility](#password-manager-compatibility))
- One tag input everywhere (plain JavaScript, no jQuery UI or CDN): chips, autocomplete with usage counts, keyboard support, right-to-left languages
- Inline tag editor on the issue page, with a History entry for every change
- Bulk edit: add tags to, or remove tags from, many issues at once, with a History entry per issue
- Tag administration page: search, sort, usage counts, unused filter, create, rename, delete, select across pages, tag detail panel
- Per-tag color and description (stored in `tags.rf_flux_tags_color` / `tags.rf_flux_tags_description`)
- "Delete all unused" for tags that are on no record (unused tags are never deleted automatically)
- A few tags (most used) in the issue list sidebar, as a list or as colored tags, with "View all" opening the issue list filtered by tags
- Optional colored tag display setting
- REST API for tags, issues, projects and time entries, documented at `/flux_tags/api_doc`

## Security

The plugin went through a full security review; the fixes are covered by the tests in `test/`.

- **Tag library**: renaming, merging and deleting tags is for administrators (pages and API). "Manage tags" in one project is not a right over the tags of every project.
- **Tagging**: the tag right *and* the right to edit that record, on the issue form, the editor, bulk edit and the API; a project needs the right on that project.
- **What a reader learns**: tag lists, counts, suggestions and filters only describe records (and projects) the reader may see. Tags that are used nowhere stay in the list.
- **API**: key in the `X-Redmine-API-Key` header only, REST switch honoured; the API description needs a login and is not a public file.
- **Input**: tag names are cleaned (control and invisible characters), limited in length and number; odd values give a 4xx, not a server error; `%` and `_` in the autocomplete are ordinary characters.
- **Output**: names, descriptions and colours are escaped or checked everywhere; the CSV export neutralises cells starting with `=`, `+`, `-`, `@`; the page loads no font or script from another site.

Tests: `test/security/tg_security_test.rb` (26 tests) and the black-box attack script `test/security/live_attack_check.py` (76 checks, run on Redmine 5, 6 and 7). A penetration test by an independent party has not been done.

## Naming

Everything added by the redesigned pages starts with `rf_flux_tags` (files, classes, routes, DOM ids, CSS classes, JS globals, i18n keys, settings and the two new `tags` columns), so it cannot clash with Redmine or with another plugin that shares the tag tables.

## API Access

- Interactive API docs: `/flux_tags/api_doc` (sign in first)
- OpenAPI YAML: `/tag-api.yaml` (sign in first)
- Base path: `/api/v1/flux_tags` (tags, records of a tag, and the tags of issues, projects and time entries)
- The REST API must be switched on (**Administration > Settings > API**) and your API key goes in the `X-Redmine-API-Key` header. A key in the address is not accepted and a browser session alone is not enough.

Who may do what through the API (the same rules as the pages):

| Action | Needs |
|--------|-------|
| Create, rename, delete tags | an administrator |
| List tags, see a tag and its records | a signed-in key; only tags and records of things the key's user may see are returned (counts too) |
| Change the tags of an **issue** | `manage_issues_tags` in the project and the right to edit that issue (`edit_issues`, or `edit_own_issues` for an issue of your own) |
| Change the tags of a **project** | `manage_project_tags` on that project |
| Change the tags of a **time entry** | `manage_time_entries_tags` in the project and the right to edit that time entry |

A change request must send `tag_list` (an empty list on purpose removes all tags); names are cleaned (no invisible characters), up to 60 characters each and 30 per request.

## Password Manager Compatibility

The Redmineflux Password Manager (from its shared-tags release) stores the tags of password entries in the same `tags` / `taggings` tables as this plugin, so a tag means the same thing on issues, projects, time entries and passwords.

- **Install order does not matter.** Whichever plugin is migrated first creates the tables; the other one finds them and adds only what is missing.
- **Password Tags tab.** When the Password Manager is installed, `Administration -> Plugins -> Redmineflux Tags plugin -> Configure` shows a fifth tab listing the tags used on password entries (rename and delete work as on the other tabs and apply to the tag everywhere). If the Password Manager is installed but still keeps its tags in its own tables, or columns are missing, the tab says what to run instead.
- **Privacy.** Through the REST API, a user who is not an administrator never sees a tag, a count or a `password_entries` context of a password entry they cannot see in the vault, and cannot rename or delete a tag used on such entries. Password entries themselves are listed only by the Password Manager's own API.
- **Name length.** A tag used on password entries cannot be renamed to more than 60 characters (the vault's limit).
- **Changes made here.** Renaming, merging or deleting a tag that is used on password entries publishes the `password_tags_changed.flux_tags` notification (action, tag ids and names, new name, password entry ids, user id) for the Password Manager's audit.
- **Note:** a tag whose last use on a password entry was removed stays in the tag list, like any unused tag.

Without the Password Manager nothing of this is visible and the plugin works as before.

## Uninstallation

To uninstall the Redmineflux Tag Plugin:

1. Remove the `flux_tags` directory from `plugins`.
2. Roll back plugin migrations (take a DB backup first):

```sh
RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=flux_tags VERSION=0
```

   If another plugin still uses the `tags` / `taggings` tables (for example the Redmineflux Password Manager), they are kept: only the issue, project and time entry tags are removed.

3. Restart Redmine.

## Version Compatibility

Supported Redmine versions:

- 4.x
- 5.x
- 6.x
- 7.x

## Libraries

This plugin uses the following libraries/gems:

- `acts-as-taggable-on` for tagging models and associations
- `will_paginate` for pagination behavior in listing interfaces
- `tag-it` (jQuery UI tag input) for interactive tag entry/autocomplete
- Swagger UI assets for API documentation rendering

## Reference

For additional information, see:

https://www.redmineflux.com/knowledge-base/plugins/tag-plugin/

## Licence

- The whole plugin (Ruby and ERB code, JavaScript, CSS, images and documentation) is licensed under the GNU General Public License v2 – see [`LICENSE`](LICENSE) and [`LICENSING-NOTICE.txt`](LICENSING-NOTICE.txt).
- Third-party libraries keep their own licences – see [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).
- "Redmineflux" and its logo are trademarks of Zehntech Technologies Inc.

## More from Redmineflux

This plugin is free. Redmineflux also makes paid Redmine plugins, bundles and a managed Redmine Cloud:

- **Paid plugins** – Agile Board, Gantt Chart, Timesheet, Helpdesk, Test Case Management, Invoice and more: [see all plugins and prices](https://www.redmineflux.com/redmine-plugins-pricing/)
- **Bundles** – several plugins together at a lower price: [compare bundles](https://www.redmineflux.com/redmine-plugin-combos-pricing/)
- **Managed Redmine Cloud** – Redmine with our plugins, hosted and maintained for you: [Redmineflux Cloud](https://www.redmineflux.com/cloud-redmine/)
- **AI for Redmine** – Crux Chat, Crux Agents and the MCP Server: [AI project management for Redmine](https://www.redmineflux.com/ai-project-management-for-redmine/)

**Need help?** GitHub issues are turned off for this repository. Please email
support@redmineflux.com or use the [contact page](https://www.redmineflux.com/contact-us/).
Plugin page: [Tags plugin on redmineflux.com](https://www.redmineflux.com/product/redmine-plugins/tags-plugin/)

