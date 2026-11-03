# P4: connectors (OpenLabTwin + GitHub Projects)

Parent: docs/plans/2026-11-03-entities-boards/README.md primitive 4. Thesis rule 1: external entities are read-only in TyLog; edits go through the source's own API/UI.

## Connector interface (lib/connectors/connector.dart)
`abstract class Connector { String get id; Future<void> refresh(); List<ExternalEntity> entities(); List<NoteRef> incoming(String day); }`
ExternalEntity = {id ('olt:place:R15'), kind, title, aliases, partOf (external ids), properties, url?}. Cached per device under appSupport/connectors/<id>/ (never in the synced vault, like OLT today). Exposed to the index as virtual read-only notes under `ext/<connector>/` paths via the P2 composite storage? NO: simpler, render-only: the index gets an `externalEntities` list merged into childrenByParent/tree/whiteboard pickers and search; links from notes to them use their id.

## P4-A OLT places
- Extend lib/olt/olt_cache.dart places select to `id,name,kind,code,parent_id,tier`; build place entities: id `olt:place:<code or id>`, title name, alias code, partOf parent place, kind 'place'.
- Existing OLT client/OTP sign-in reused. Refresh with the existing OLT cache cadence.
- UI: Library Tree view and the P3 tree show OLT places (read-only badge "OpenLabTwin"); place page = read-only entity page (header + children + linked references); TyLog notes can be put "part of" an OLT place (stored by external id).
## P4-B OLT items/assets/stock
- Read items (name, kind, unit), assets (tag, serial, condition, seen_at) + asset_place view, stock view; on a place page show "Assets here" and "Stock" sections; assets as entities `olt:asset:<tag>` part_of their place.
## P4-C GitHub Projects v2
- Port GitDoIt GraphQL (fetchProjectsFromGitHub, fetchProjectBoardFromGitHub, setProjectItemStatus) into lib/github/github_projects.dart; a TyLog board with `scope.github_project` shows the project's Status columns and items; moving a card updates the Status field (it is the user's own project: write allowed, logged as a Decision).
