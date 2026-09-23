# Upstream translation reuse

This imports existing translations only. `mapping.json` links Tsumiru keys to
reviewed source keys and records the English text at both ends. Sources are
pinned in `import_upstream.py` and `coverage.json`. `provenance.json` identifies
the source of every imported locale/key pair. Attribution and license texts
are bundled with the app in `assets/licenses/`.

Run from the repository root with Python 3.11+ and uv:

```sh
uv run scripts/translations/import_upstream.py --fetch --write
uv run scripts/translations/import_upstream.py
uv run --with polib==1.2.0 python -m unittest discover -s scripts/translations -v
flutter gen-l10n
```

The first command downloads missing catalogs at pinned revisions and fills
missing values. The second checks provenance, expected English, coverage and
whether any mapped imports are still missing. The cache is kept under the
ignored `.local-translation-import/` directory. A different location can be
passed with `--cache`.

Existing nonempty values, including translations inherited from a base locale,
are preserved. Regional eligibility uses the catalogs before the import, so a
new base translation does not prevent a region-specific import in the same run.
Norwegian Bokmål (`nb` and `nb_NO`) uses upstream Bokmål catalogs from Norway;
Nynorsk is not substituted. Simplified and Traditional Chinese use separate
catalogs. Generic `zh` is left unchanged to avoid adding Simplified fallbacks to
Traditional Chinese. Gan Chinese has no matching upstream catalog.

The mapping prefers reader/library terminology from Mihon, server terminology
from WebUI, and Komikku's additional features. Komikku's inherited catalog is
also checked as a fallback; this snapshot supplied no additional values beyond
the preferred sources. Ambiguous contexts such as library grouping “Default”
are left unmapped. A few equivalent phrases, such as “User Name”/“Username”,
have explicit notes. Missing, empty, fuzzy and unchanged-English translations
are skipped, even when an English-looking word might be valid in the language.

This pass imports static text only. Plurals, placeholders, markup, Android
resource aliases and unsupported escapes are skipped. Android XML entities and
string escapes are decoded; translation wording is otherwise unchanged.
Flutter generation checks the resulting ARB syntax. Native-speaker review and
rendered layout checks remain separate work.

When a translator corrects an imported value, remove its entry from
`provenance.json`: it is no longer an exact upstream import. Run with `--write`
to refresh the report. The importer will preserve the corrected value. Without
that provenance update, checks deliberately fail instead of attributing an
edited translation to an upstream source. When updating source revisions,
review English changes and mapping context before accepting new imports.

`coverage.json` compares effective nonempty coverage to `fe452d18`, including
regional inheritance. It does not assess translation quality, nor discount
pre-existing translations that equal English. `imported` counts explicit values;
coverage gains also include inheritance into locales such as `pt_PT`.

## Coverage after this import

6,017 new values across 22 locale files; 1,190 English keys.

| Locale | Before | After | Remaining |
| --- | ---: | ---: | ---: |
| ar | 237 | 508 | 682 |
| de | 38 | 417 | 773 |
| es | 203 | 506 | 684 |
| fil | 0 | 347 | 843 |
| fr | 203 | 503 | 687 |
| gan | 0 | 0 | 1190 |
| gan_Hant | 0 | 0 | 1190 |
| id | 92 | 458 | 732 |
| it | 203 | 494 | 696 |
| ja | 366 | 611 | 579 |
| ko | 31 | 428 | 762 |
| nb | 0 | 289 | 901 |
| nb_NO | 64 | 326 | 864 |
| nl | 0 | 356 | 834 |
| pt | 361 | 600 | 590 |
| pt_BR | 361 | 607 | 583 |
| pt_PT | 361 | 600 | 590 |
| ru | 203 | 505 | 685 |
| ta | 355 | 588 | 602 |
| th | 9 | 336 | 854 |
| tr | 129 | 469 | 721 |
| uk | 203 | 476 | 714 |
| vi | 357 | 606 | 584 |
| zh | 1091 | 1091 | 99 |
| zh_Hans | 1091 | 1095 | 95 |
| zh_Hant | 1091 | 1095 | 95 |
