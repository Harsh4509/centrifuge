# Context map

| File | Contents and format |
| --- | --- |
| [scope.json](scope.json) | Unchanged scope object; `codebases` contains repository identity, revision and selected files. |
| [statements.json](statements.json) | Unchanged object with `version` and `files`; each source has statements with `id`, `lines`, `quote` and per-dimension levels. |
| [entries.json](entries.json) | Document array; each entry has `id`, `path`, `dimensions`, `description`, `written_for_engagement`, `level`, `visibility` and `sources`. Dimensions use `tf`, `scope`, `known`, `severity`; an empty array denotes background. |
| [severity-set.json](severity-set.json) | Ordered array of severity identifiers, display names and complete definitions. |
| [judging-guidelines.md](judging-guidelines.md) | Selected judging guidelines, unchanged. |
| [scope-rules/centrifuge__protocol-internal.md](scope-rules/centrifuge__protocol-internal.md) | Repository scope rule, unchanged. |
| [deduplication-guidelines.md](deduplication-guidelines.md) | Source-referenced duplication instructions. |
| [finding-report-standard.md](finding-report-standard.md) | Supplied finding-field guidance, unchanged. |

Inventory paths are relative to the workspace root. Statement `lines` refer to the document named by that record’s `path`. The statements file spells the validity dimension `true_finding`; the inventory uses `tf`.

[Lookup examples](queries.md) · [Statement source index](statement-index.md) · [Document map](documents.md) · [Report catalog](prior-reports.md)
