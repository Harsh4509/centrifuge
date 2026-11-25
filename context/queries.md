# Reference lookups

Run these examples from the workspace root with Python 3. The [context map](README.md) describes the JSON formats.

List documents relevant to one dimension:

```sh
python - <<'PY'
import json
for entry in json.load(open('context/entries.json')):
    if 'known' in entry['dimensions']:
        print(entry['id'], entry['path'], entry['description'], sep='\t')
PY
```

Search statement quotes while retaining the identifier, exact source lines and per-dimension levels:

```sh
python - <<'PY'
import json
needle = 'reservation'
for source in json.load(open('context/statements.json'))['files']:
    for statement in source['statements']:
        if needle.casefold() in statement['quote'].casefold():
            print(statement['id'], source['path'], statement['lines'])
            print(json.dumps(statement['dimensions'], ensure_ascii=False))
            print(statement['quote'], '\n')
PY
```

Retrieve an individual statement by replacing the search condition with `statement['id'] == 'S1'`. Change the inventory dimension to `tf`, `scope` or `severity` for the other document sets. A dimension labels a document's subject; the source text and statement record contain its conditions.

Search complete reports and disclosure text:

```sh
rg -n -i 'reservation|rounding' context/derived context/Centrifuge_vdk_context_docs_final.md context/SPECIFICATION.md centrifuge__protocol-internal/docs/audits/out-of-scope
```

The [report catalog](prior-reports.md) links every report's complete text and original. Report responses and fix status are within those documents.
