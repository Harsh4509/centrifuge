# Deduplication guidelines

The selected [Sherlock judging guidelines, §4](judging-guidelines.md#4-duplication-guidelines) govern duplication. Engagement context cannot override these rules.

## Comparison requirements

The duplication guidelines assume we have a "target issue", and the "potential duplicate" of that issue needs to meet the following requirements to be considered a duplicate.

1. Identify the root cause
2. Identify at least a Low impact
3. Identify a valid attack path or vulnerability path

Only when the "potential duplicate" meets all three requirements will the "potential duplicate" be duplicated with the "target issue", and all duplicates will be awarded the highest severity identified among the duplicates.

If the report does not meet all three requirements, do not group it with the target issue. Assess whether it duplicates another issue separately. Assess its True Finding, scope, known, and severity verdicts under their respective rules.

**Root cause groupings**

Issues that appear in multiple places, even in different components, may have the same root cause:

1. Issues with the same logic mistake.
2. Issues with the same conceptual mistake.

   > Example: different untrusted external admins can steal funds.

If the underlying code implementations, impact or fixes are different, then they may be treated separately.

**Identifies the core issue:** In case of issues that have a large number of duplicates, Issues that identify the core issue and show a valid impact should be grouped.

Source for every comparison requirement above: [judging guidelines, §4](judging-guidelines.md#4-duplication-guidelines). The three requirements apply to the **potential duplicate** relative to the **target issue**.

The Low impact criterion uses the complete [severity set](severity-set.json), identifier `severity-def:low-v7`. Severity measurement rules are in [judging guidelines, §3.4](judging-guidelines.md#34-severity).

## Report context

“Root Cause”, “Attack Path” and “Vulnerability Path” have the meanings in the [judging glossary, §6](judging-guidelines.md#6-glossary). [§5.10, item 3](judging-guidelines.md#510-best-practices) asks reports to combine repeated occurrences of one root cause and use judgment where occurrences differ.

[Prior disclosures and reports](prior-reports.md) supply evidence for the separate known-status assessment under [§3.3](judging-guidelines.md#33-known). A prior report's issue grouping or severity label does not replace §4 or the selected severity set.
