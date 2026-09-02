# Nexus page text

The published mod page copy, kept in git so the description and the build it
describes stay in step.

| file | Nexus field |
| --- | --- |
| `nexus-description.bbcode` | the mod description |
| `nexus-credits.bbcode` | the credits box |

Both are BBCode, pasted into the Nexus editor by hand — there is no automated
upload for page text, only for files (`.github/workflows/nexus-upload.yaml`
handles release assets).

## Updating for a release

Re-check these each time the shipped profile changes, because they state
specifics that go stale:

- the enabled feature count and the list itself, from
  `package/SKSE/Plugins/CommunityShaders/SettingsDefault.json`
- the count of features that are *not shipped*, and the split between developer
  tooling and visual features
- the precompiled shader count, from the staged `precompiled-cache/ShaderCache`
- anything claiming a version number

The description deliberately leads with "this is not a performance mod".
Feature gating is worth only a few percent of compile time; the startup win
comes from the bundled cache. Keep that framing — it is the single biggest
source of misdirected expectations for a mod called "Lite".
