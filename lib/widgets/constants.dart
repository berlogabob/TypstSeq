import 'package:flutter/material.dart';

/// Corner radius shared by the rounded [ListTile]s in the links/backlinks panel.
const listTileRadius = BorderRadius.all(Radius.circular(12));

/// Note kinds that represent the app's own structural taxonomy (daily
/// journal, pages, projects, …) rather than a user-defined entity.
const structuralNoteKinds = {'daily', 'note', 'project', 'article', 'research'};

/// The icon representing a note of the given [kind] — person/place/org entities
/// and structural kinds. Used by inline reference chips and entity lists so a
/// person, place, project, etc. reads at a glance.
IconData iconForKind(String? kind) => switch (kind) {
  'person' => Icons.person_outline,
  'place' => Icons.location_on_outlined, // map pin / locator
  'org' || 'organization' || 'company' => Icons.business_outlined,
  'project' => Icons.work_outline,
  'article' => Icons.article_outlined,
  'daily' => Icons.event_note,
  _ => Icons.description_outlined, // generic note reference
};
