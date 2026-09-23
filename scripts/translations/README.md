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
uv run --with polib==1.2.0 --with babel==2.18.0 python -m unittest discover -s scripts/translations -v
flutter gen-l10n
flutter test test/l10n/upstream_translations_test.dart
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
also checked and supplies the age-rating badge in this pass. Ambiguous contexts such as library grouping “Default”
are left unmapped. A few equivalent phrases, such as “User Name”/“Username”,
have explicit notes. Missing, empty, fuzzy and unchanged-English translations
are skipped unless `unchanged.json` explicitly allows that locale/key or a
language-neutral name/unit. Unchanged-English detection compares the source
text before format conversion, so renamed placeholders cannot bypass it.

The second pass also imports explicitly mapped `%s`/`%d` arguments and simple
whole-message cardinal plurals. Conversion specs record argument positions,
Tsumiru names and types, and required exact selectors. Indexed arguments may
be reordered. `#` becomes an explicit count placeholder. Flutter treats `=1`
and `one` as aliases, so only `=1` is emitted when both would contain the same
source text. Count interpolation is retained for languages whose `one` category
also includes numbers such as 21.

The converter rejects missing locale categories, blank branches, malformed or
changed argument formats, and hardcoded counts incompatible with their plural
category. Babel supplies CLDR categories; focused tests exercise the generated
Flutter localizations at 0, 1, 2, 3, 11 and 21. Source plurals are still reviewed
for meaning: yesterday/tomorrow strings, legacy `select` messages and special
zero meanings without matching upstream text remain excluded. Arabic next-chapter
count is explicitly excluded because its source zero branch means end of chapters. Nested ICU,
markup, arbitrary number formatting and unsupported escapes are not converted.
Existing values remain unchanged. Native-speaker and rendered-layout checks
remain separate work.

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

## Coverage after both imports

6,774 imported values in total; 757 added in the second pass against
`dc04b2c1`. There are 1,190 English keys.

| Locale | Original | After pass 1 | After pass 2 | Remaining |
| --- | ---: | ---: | ---: | ---: |
| ar | 237 | 508 | 543 | 647 |
| de | 38 | 417 | 489 | 701 |
| es | 203 | 506 | 542 | 648 |
| fil | 0 | 347 | 386 | 804 |
| fr | 203 | 503 | 537 | 653 |
| gan | 0 | 0 | 0 | 1190 |
| gan_Hant | 0 | 0 | 0 | 1190 |
| id | 92 | 458 | 512 | 678 |
| it | 203 | 494 | 530 | 660 |
| ja | 366 | 611 | 647 | 543 |
| ko | 31 | 428 | 485 | 705 |
| nb | 0 | 289 | 313 | 877 |
| nb_NO | 64 | 326 | 349 | 841 |
| nl | 0 | 356 | 408 | 782 |
| pt | 361 | 600 | 634 | 556 |
| pt_BR | 361 | 607 | 642 | 548 |
| pt_PT | 361 | 600 | 634 | 556 |
| ru | 203 | 505 | 538 | 652 |
| ta | 355 | 588 | 614 | 576 |
| th | 9 | 336 | 367 | 823 |
| tr | 129 | 469 | 508 | 682 |
| uk | 203 | 476 | 501 | 689 |
| vi | 357 | 606 | 641 | 549 |
| zh | 1091 | 1091 | 1091 | 99 |
| zh_Hans | 1091 | 1095 | 1096 | 94 |
| zh_Hant | 1091 | 1095 | 1096 | 94 |
