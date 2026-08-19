# Visual Baseline Registry

This directory registers references only after a page has been explicitly accepted as finished. Do not bulk-capture the site.

For each accepted route, add one manifest entry with:

- route and approval date;
- production commit SHA;
- desktop viewport and reference path;
- mobile viewport and reference path;
- reviewer and short scope note.

Store references below `references/<route-id>/`. A later layout release compares only affected registered routes. Differences in layout, typography, header, footer, spacing, overflow, or page end require review; a changed screenshot is never approved automatically.