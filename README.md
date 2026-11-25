<p align="center">
  <img src="https://www.redmineflux.com/wp-content/uploads/2025/10/Redmineflux-logo.svg" alt="Redmineflux" width="280" />
</p>

<h1 align="center">Redmineflux Tags Plugin</h1>

<p align="center">
  <strong>Freeform issue tagging, cross-project filtering, and a shared tag library for Redmine — without changing your tracker or category configuration.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Redmine-6.x%20%7C%207.x-red?logo=ruby&logoColor=white" alt="Redmine 6.x | 7.x" />
  <img src="https://img.shields.io/badge/JavaScript-jQuery%20UI-F7DF1E?logo=javascript&logoColor=black" alt="JavaScript" />
  <img src="https://img.shields.io/badge/license-GPL%20v2-blue" alt="License: GPL v2" />
</p>

<p align="center">
  <a href="https://www.redmineflux.com/product/redmine-plugins/tags-plugin/">Website</a> ·
  <a href="https://www.redmineflux.com/knowledge-base/">Knowledge Base</a> ·
  <a href="#rest-api">API</a> ·
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

It also includes centralized tag administration (rename, delete), tag filters and columns in Redmine's lists, autocomplete, and a REST API for tags and for the tags of each issue, project and time entry.

## Table of Contents

- [Installation](#installation)
- [Getting Started](#getting-started)
- [Features](#features)
- [Permissions](#permissions)
- [Settings](#settings)
- [REST API](#rest-api)
- [Password Manager Compatibility](#password-manager-compatibility)
- [Good to Know](#good-to-know)
- [Uninstallation](#uninstallation)
- [Libraries](#libraries)
- [Licence](#licence)

## Installation

### Which branch to install

Your Redmine version is shown under **Administration → Information**. Install the release branch for your Redmine major version:

| Redmine | Plugin version | Branch to install |
|---------|----------------|-------------------|
| 7.x | 7.x.y | `release/7.0.0` |
| 6.x | 6.x.y | `release/6.0.0` |
| 5.x | 5.x.y (legacy, security fixes only) | `release/5.0.0` |

Releases are tagged on their branch. `master` is the development trunk and is not meant for production installs.

### Requirements

| Redmine | Ruby | Rails (comes with Redmine) |
|---------|------|----------------------------|
| 7.0 | 3.2 – 4.0 | 8.1 |
| 6.1 | 3.2 – 3.4 | 7.2 |
| 6.0 | 3.1 – 3.3 | 7.2 |
| 5.1 (legacy line) | 2.7 – 3.2 | 6.1 |

- A database supported by Redmine. The plugin uses the tables `tags` and `taggings` (the acts-as-taggable-on schema).
- The gems `acts-as-taggable-on`, `will_paginate` and `redmineflux_icon_compat`, installed by `bundle install` from the plugin's `Gemfile`.
- The Tags field of the **bulk edit** form loads the Select2 library from `cdn.jsdelivr.net`, so the browser needs access to that site for this one field.

### Install

```sh
# 1. Put the plugin in the plugins directory. The folder must be named flux_tags
#    (the plugin id; the API description is also read from plugins/flux_tags).
#    Use release/7.0.0 on Redmine 7.x, release/6.0.0 on Redmine 6.x.
cd /path/to/redmine/plugins
git clone -b release/7.0.0 https://github.com/zehntech/redmineflux-tags-plugin.git flux_tags

# 2. Install the gems
cd /path/to/redmine
bundle install

# 3. Run the plugin migrations
bundle exec rake redmine:plugins:migrate RAILS_ENV=production

# 4. Restart Redmine (for Passenger; otherwise restart your application server)
touch tmp/restart.txt
```

If the `tags` / `taggings` tables already exist (for example created by the Redmineflux Password Manager), the migration checks that they are acts-as-taggable-on tables, keeps them and adds only the missing columns.

## Getting Started

1. As an administrator, open `Administration → Plugins → Redmineflux Tags plugin → Configure` and decide whether tags are shown in colour.
2. Give roles the permissions they need under `Administration → Roles and permissions` (see [Permissions](#permissions)).
3. Open an issue, project or time entry form and add tags in the Tags field. Autocomplete suggests existing tags; typing a new name creates the tag.
4. Use the **Tags** filter and column in the issue list, the spent time list and the project list.
5. Rename or delete tags on the plugin's settings tabs (`Issue Tags`, `Time Entry Tags`, `Project Tags`).

## Features

### Tagging
- A **Tags** field (tag-it input with autocomplete, up to 30 tags per field) on the issue form, the time entry form and the project form
- **Issue page**: a *Tags* row with the issue's tags. People with "Edit issues" or "Edit own issues" plus "Manage issues tags" see an **Add** link that edits the tags in place (see [Good to Know](#good-to-know) for how it saves)
- **Bulk edit** of issues: a Tags field; the chosen tags replace the tags of every selected issue (an empty field changes nothing)
- Changing an issue's tags through the issue form or bulk edit adds a **journal entry** ("Tag list") to the issue history
- **Copying an issue** copies its tags
- **Issue search** also finds issues by tag name
- Autocomplete suggests the tags used on issues and on time entries the user can see, and the tags used on any project

### Lists, filters and exports
- A **Tags** filter (is, is not, none, any) and a **Tags** column in the issue list, the spent time list and the project list
- Tags in the lists link to the same list filtered by that tag
- The Tags column is included in **CSV** exports of these lists and in the **PDF** export of the issue list; a tag list that starts with `=`, `+`, `-` or `@` is written as text in the CSV so spreadsheets do not run it as a formula
- Optional **coloured tags** (each tag gets a fixed light colour derived from its name)

### Tag administration (administrators)
- Settings tabs **Issue Tags**, **Time Entry Tags** and **Project Tags** list the tags used on that kind of record, 10 per page
- **Rename** a tag (names are unique ignoring capital letters) and **delete** tags, one per row or several at once (select rows, right-click, Delete). Renaming or deleting a tag applies everywhere it is used
- A **Password Tags** tab when the Redmineflux Password Manager is installed (see [Password Manager Compatibility](#password-manager-compatibility))
- Merging tags is available through the REST API

### Languages
- English, German and Arabic

## Permissions

The plugin defines five permissions. They have no translated label, so Redmine shows the humanised name under `Administration → Roles and permissions`.

| Permission | Label shown | Where it is listed | What it controls |
|------------|-------------|--------------------|------------------|
| `view_tags` | View tags | Project (no module) | Defined but not checked anywhere; granting it changes nothing |
| `manage_tags` | Manage tags | Project (no module) | REST API: create, rename, merge and delete tags. Having it in a role of **any** project is enough |
| `manage_project_tags` | Manage project tags | Project (no module) | Shows the Tags field on the project form; REST API: set a project's tags. Having it in a role of any project is enough |
| `manage_issues_tags` | Manage issues tags | Issue tracking | Shows the Tags field on the issue form (if held in any project), the issue page's **Add** link and the bulk-edit Tags field (in that project); REST API: set an issue's tags in that project |
| `manage_time_entries_tags` | Manage time entries tags | Time tracking | Shows the Tags field on the time entry form (if held in any project); REST API: set a time entry's tags in that project |

- Administrators can do everything; the settings tabs and the rename/delete pages are for administrators only.
- In the forms these permissions only **show or hide** the Tags field. The `tag_list` attribute itself is accepted from anyone who may edit the issue, project or time entry, also through Redmine's own REST API (`issue[tag_list]`, `project[tag_list]`, `time_entry[tag_list]`).

## Settings

`Administration → Plugins → Redmineflux Tags plugin → Configure` (administrators only):

| Tab | What it does |
|-----|--------------|
| General | **Use colored tag** (`issues_use_colors`, off by default): show tags as coloured labels |
| Issue Tags | Tags used on issues: rename, delete, bulk delete |
| Time Entry Tags | Tags used on time entries: rename, delete, bulk delete |
| Project Tags | Tags used on projects: rename, delete, bulk delete |
| Password Tags | Only when the Redmineflux Password Manager is installed: tags used on password entries, or a message saying what to run while that plugin is not yet compatible |

A tag that is not used on any record is not listed on these tabs.

## REST API

### Tags API (`/api/v1/flux_tags`)

All endpoints answer JSON in the form `{"success": true, "data": {...}}` or `{"success": false, "error": {"message": "..."}}`.

**Authentication**: an API key is required on every call, sent in the `X-Redmine-API-Key` header (recommended) or as `?key=` in the URL (keys in URLs end up in server logs). A browser session or HTTP Basic login is refused with `401`; a locked user's key is refused too. The plugin reads the key itself and does not check Redmine's **Enable REST web service** setting, but when **Authentication required** is on, Redmine only lets an API-key call through to the plugin if **Enable REST web service** is on, so keep it enabled.

| Action | Method | Endpoint | Parameters | Who may call |
|--------|--------|----------|------------|--------------|
| List tags | GET | `/api/v1/flux_tags/tags` | `q` (name contains), `context` (`issues`, `projects`, `time_entries`, `password_entries`), `page`, `per_page` (default 25, at most 100) | Any user with a valid key |
| Get a tag | GET | `/api/v1/flux_tags/tags/:id` | — | Any user with a valid key |
| Create a tag | POST | `/api/v1/flux_tags/tags` | `name` or `tag[name]`; an existing tag with the same name (ignoring capital letters) is returned instead | `manage_tags` or administrator |
| Rename a tag | PATCH / PUT | `/api/v1/flux_tags/tags/:id` | `name` or `tag[name]` | `manage_tags` or administrator |
| Delete a tag | DELETE | `/api/v1/flux_tags/tags/:id` | — (removes it from every record) | `manage_tags` or administrator |
| Merge tags | POST | `/api/v1/flux_tags/tags/merge` | `tag_ids` (at least 2), `name` or `tag[name]` of the target (an existing tag or a new one) | `manage_tags` or administrator |
| Records with a tag | GET | `/api/v1/flux_tags/tags/:id/records` | `type` (`issues`, `projects`, `time_entries`; required), `page`, `per_page` | Any user with a valid key; only records the user can see are listed |
| Tags of an issue | GET / PATCH / PUT | `/api/v1/flux_tags/issues/:issue_id/tags` | `tag_list` or `tags` (array or comma-separated) for PATCH / PUT | Read: the issue must be visible. Write: also `manage_issues_tags` in its project |
| Tags of a project | GET / PATCH / PUT | `/api/v1/flux_tags/projects/:project_id/tags` | same | Read: the project must be visible. Write: also `manage_project_tags` |
| Tags of a time entry | GET / PATCH / PUT | `/api/v1/flux_tags/time_entries/:time_entry_id/tags` | same | Read: the time entry must be visible. Write: also `manage_time_entries_tags` in its project |

- PATCH / PUT on a record **replaces** its whole tag list. These changes add no journal entry to an issue.
- A tag in a list carries `id`, `name`, `taggings_count` and `contexts`.

```sh
# List tags whose name contains "bug"
curl -H "X-Redmine-API-Key: YOUR_KEY" "https://redmine.example.com/api/v1/flux_tags/tags?q=bug"

# Set the tags of issue 42
curl -X PATCH -H "X-Redmine-API-Key: YOUR_KEY" -H "Content-Type: application/json" \
  -d '{"tag_list": ["backend", "urgent"]}' \
  "https://redmine.example.com/api/v1/flux_tags/issues/42/tags"
```

### Administrator pages and API description

- `GET`, `PUT` and `DELETE /tags/:id` belong to the administrator pages: they need an administrator's **browser session** (with the page's security token for changes) and do not accept an API key.
- The Swagger page `/flux_tags/api_doc` and its description file `/tag-api.yaml` describe only these `/tags/:id` routes, not the `/api/v1/flux_tags` API. Both are served **without login**, even when Redmine requires authentication.

## Password Manager Compatibility

The Redmineflux Password Manager (from its shared-tags release) stores the tags of password entries in the same `tags` / `taggings` tables as this plugin, so a tag means the same thing on issues, projects, time entries and passwords.

- **Install order does not matter.** Whichever plugin is migrated first creates the tables; the other one finds them and adds only what is missing.
- **Password Tags tab.** When the Password Manager is installed, `Administration → Plugins → Redmineflux Tags plugin → Configure` shows a fifth tab listing the tags used on password entries (rename and delete work as on the other tabs and apply to the tag everywhere). If the Password Manager is installed but still keeps its tags in its own tables, or columns are missing, the tab says what to run instead.
- **Privacy.** Through the REST API, a user who is not an administrator never sees a tag, a count or a `password_entries` context of a password entry they cannot see in the vault, and cannot rename, merge or delete a tag used on such entries. Password entries themselves are listed only by the Password Manager's own API (`type=password_entries` on `/records` is refused).
- **Name length.** A tag used on password entries cannot be renamed to more than the vault's limit (60 characters unless the Password Manager defines another).
- **Changes made here.** Renaming, merging or deleting a tag that is used on password entries publishes the `password_tags_changed.flux_tags` notification (action, tag ids and names, new name, password entry ids, user id) for the Password Manager's audit.
- **Unused tags.** A tag whose last use on a password entry was removed stays in the tag table until the next clean-up described under [Good to Know](#good-to-know).

Without the Password Manager nothing of this is visible and the plugin works as before.

## Good to Know

- **Unused tags are deleted instance-wide.** Saving an issue edit that includes the tag list (the issue form with the Tags field, or Redmine's issue REST API with `issue[tag_list]`), or a bulk edit that sets tags, deletes every tag that has no tagging left, anywhere in Redmine. This includes tags created through the API and not used yet, and tags last used on a password entry. The `/api/v1/flux_tags` API and the issue page's **Add** editor do not run this clean-up.
- **The issue page's Add editor uses the API key.** It saves through `POST /update_issue_tags.json` and authenticates with the viewer's API key, which the issue page includes in its script and sends as `?key=` in the URL. It therefore works only when **Enable REST web service** is on, the key can appear in web-server logs, and this save adds no journal entry.
- **Assets on every page.** `tag-it.js`, `jquery.tagit.css` and `flux_tags.css` are loaded on every Redmine page.
- **Project tags are not filtered by visibility.** The project form's tag autocomplete and the values of the project list's Tags filter include the tags of all projects, also projects the user cannot see.

## Uninstallation

Roll back the migrations **before** removing the folder (the rollback needs the plugin), and take a database backup first.

```sh
cd /path/to/redmine

# 1. Roll back the plugin migrations
bundle exec rake redmine:plugins:migrate NAME=flux_tags VERSION=0 RAILS_ENV=production

# 2. Remove the plugin
rm -rf plugins/flux_tags

# 3. Restart Redmine
touch tmp/restart.txt
```

- If no other plugin uses the `tags` / `taggings` tables, the rollback drops both tables with all tags.
- If the Redmineflux Password Manager is installed, or the tables hold taggings of other record types, the tables are kept: the rollback deletes every issue, project and time-entry tagging (whichever plugin created it) and recounts the usage of the remaining tags. The columns added by the later migrations stay.

## Libraries

This plugin uses the following libraries/gems:

- `acts-as-taggable-on` for tagging models and associations
- `will_paginate` for pagination in the settings tabs
- `redmineflux_icon_compat` for icons shared by Redmineflux plugins
- `tag-it` (jQuery UI tag input, bundled) for interactive tag entry and autocomplete
- Select2 (loaded from `cdn.jsdelivr.net`) for the bulk-edit Tags field
- Swagger UI assets (bundled) for the API description page

## Licence

- The whole plugin (Ruby and ERB code, JavaScript, CSS, images and documentation) is licensed under the GNU General Public License v2 – see [`LICENSE`](LICENSE) and [`LICENSING-NOTICE.txt`](LICENSING-NOTICE.txt).
- Third-party libraries keep their own licences – see [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).
- "Redmineflux" and its logo are trademarks of Zehntech Technologies Inc.

## Release Notes

See [RELEASE_NOTES.md](RELEASE_NOTES.md).

## Reference

For additional information, see:

https://www.redmineflux.com/knowledge-base/plugins/tag-plugin/

## More from Redmineflux

This plugin is free. Redmineflux also makes paid Redmine plugins, bundles and a managed Redmine Cloud:

- **Paid plugins** – Agile Board, Gantt Chart, Timesheet, Helpdesk, Test Case Management, Invoice and more: [see all plugins and prices](https://www.redmineflux.com/redmine-plugins-pricing/)
- **Bundles** – several plugins together at a lower price: [compare bundles](https://www.redmineflux.com/redmine-plugin-combos-pricing/)
- **Managed Redmine Cloud** – Redmine with our plugins, hosted and maintained for you: [Redmineflux Cloud](https://www.redmineflux.com/cloud-redmine/)
- **AI for Redmine** – Crux Chat, Crux Agents and the MCP Server: [AI project management for Redmine](https://www.redmineflux.com/ai-project-management-for-redmine/)

**Need help?** GitHub issues are turned off for this repository. Please email
support@redmineflux.com or use the [contact page](https://www.redmineflux.com/contact-us/).
Plugin page: [Tags plugin on redmineflux.com](https://www.redmineflux.com/product/redmine-plugins/tags-plugin/)

