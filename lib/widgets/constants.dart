import 'package:flutter/material.dart';

/// Corner radius shared by the rounded [ListTile]s in the links/backlinks panel.
const listTileRadius = BorderRadius.all(Radius.circular(12));

/// Note kinds that represent the app's own structural taxonomy (daily
/// journal, pages, projects, …) rather than a user-defined entity.
const structuralNoteKinds = {'daily', 'note', 'project', 'article', 'research'};
