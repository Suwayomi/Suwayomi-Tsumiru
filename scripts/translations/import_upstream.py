#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["polib==1.2.0", "babel==2.18.0"]
# ///
"""Import reviewed upstream translations: uv run scripts/translations/import_upstream.py --help."""
import argparse
import json
from pathlib import Path
import re
import urllib.request
import xml.etree.ElementTree as ET

import polib

from formats import convert, validate_spec

ROOT = Path(__file__).resolve().parents[2]
DATA = Path(__file__).resolve().parent
NOTICE_KEY = '@@x_translationNotice'
TRANSLATION_NOTICE = (
    'This file includes translations adapted from upstream PO and Android XML. '
    'See assets/licenses/translation-notices.txt for attribution and licenses, '
    'and scripts/translations/provenance.json for per-string sources.'
)
SOURCES = {
    'webui': ('Suwayomi/Suwayomi-WebUI', 'd22e0dfe8a47717b56649f6c90fc2cbaca8399fe', 'src/i18n/locales/{locale}.po'),
    'mihon': ('mihonapp/mihon', 'f52d890e7f8a3c418ddab41f41d4b577bce0dc06', 'i18n/src/commonMain/moko-resources/{locale}/strings.xml'),
    'komikku': ('komikku-app/komikku', '936e25bf99af29e059f06c4ad613ab62df9ae53e', 'i18n/src/commonMain/moko-resources/{locale}/strings.xml'),
    'komikku_extra': ('komikku-app/komikku', '936e25bf99af29e059f06c4ad613ab62df9ae53e', 'i18n-kmk/src/commonMain/moko-resources/{locale}/strings.xml'),
}
LOCALES = {
    'ar': ('ar', 'ar'), 'de': ('de', 'de'), 'es': ('es', 'es'),
    'fil': ('fil', 'fil'), 'fr': ('fr', 'fr'), 'id': ('id', 'in'),
    'it': ('it', 'it'), 'ja': ('ja', 'ja'), 'ko': ('ko', 'ko'),
    'nb': ('nb-NO', 'nb-rNO'), 'nb_NO': ('nb-NO', 'nb-rNO'), 'nl': ('nl', 'nl'),
    'pt': ('pt', 'pt'), 'pt_BR': ('pt-BR', 'pt-rBR'),
    'ru': ('ru', 'ru'), 'ta': ('ta', 'ta'), 'th': ('th', 'th'),
    'tr': ('tr', 'tr'), 'uk': ('uk', 'uk'), 'vi': ('vi', 'vi'),
    'zh_Hans': ('zh-Hans', 'zh-rCN'), 'zh_Hant': ('zh-Hant', 'zh-rTW'),
}


def read_json(path):
    return json.loads(path.read_text())


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def android_text(value):
    if value.startswith('"') and value.endswith('"'):
        value = value[1:-1]
    if re.search(r'\\(?![ntr\'"\\@?]|u[0-9a-fA-F]{4})', value):
        return None
    escapes = {'n': '\n', 't': '\t', 'r': '\r', "'": "'", '"': '"', '\\': '\\', '@': '@', '?': '?'}
    return re.sub(r'\\(u[0-9a-fA-F]{4}|.)', lambda m: chr(int(m[1][1:], 16)) if m[1].startswith('u') else escapes[m[1]], value)


def parse_catalog(path, source):
    if source == 'webui':
        return {e.msgid: e.msgstr for e in polib.pofile(str(path))
                if not e.obsolete and 'fuzzy' not in e.flags and not e.msgid_plural}
    root = ET.parse(path).getroot()
    values = {e.attrib['name']: android_text(e.text or '')
              for e in root if e.tag == 'string' and not len(e)
              and e.attrib.get('translatable') != 'false'}
    for element in root.findall('plurals'):
        if all(not len(item) for item in element):
            values[element.attrib['name']] = {item.attrib['quantity']: android_text(item.text or '') for item in element}
    return values


def safe_static(text):
    return bool(text and text.strip()) and not re.search(r'[{}<>]|%(?:\d+\$)?[-#+ 0,(]*\d*(?:\.\d+)?[a-zA-Z]|\\|^[@?]', text)


def effective(catalogs, locale, key):
    return catalogs[locale].get(key) or catalogs.get(locale.split('_')[0], {}).get(key)


def coverage(catalogs, keys):
    return {locale: sum(bool(effective(catalogs, locale, key)) for key in keys)
            for locale in sorted(catalogs) if locale != 'en'}


def load_catalog(cache, source, locale, fetch, catalog="strings"):
    repo, revision, pattern = SOURCES[source]
    relative = pattern.format(locale=locale)
    if catalog == "plurals":
        relative = relative.replace("strings.xml", "plurals.xml")
    path = cache / source / revision / relative
    if not path.exists():
        if not fetch:
            raise FileNotFoundError(f'{path}: run with --fetch to download pinned catalogs')
        url = f'https://raw.githubusercontent.com/{repo}/{revision}/{relative}'
        data = urllib.request.urlopen(url, timeout=60).read()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    return parse_catalog(path, source)


def prepare_translation(raw, key, ref, locale, allowances):
    if raw is None:
        return None
    unchanged = raw == ref['english'] or (isinstance(raw, str) and isinstance(ref['english'], str)
                                         and raw.strip().casefold() == ref['english'].strip().casefold())
    if unchanged and key not in allowances['invariant'] and key not in allowances['locales'].get(locale, {}):
        return None
    try:
        text = convert(raw, ref, locale)
    except (ValueError, TypeError):
        return None
    if not ref.get('conversion') and not safe_static(text):
        return None
    return text


def run(cache, fetch, write):
    paths = {p.stem[4:]: p for p in (ROOT / 'lib/src/l10n').glob('app_*.arb')}
    catalogs = {locale: read_json(path) for locale, path in paths.items()}
    original = {locale: dict(values) for locale, values in catalogs.items()}
    english = catalogs['en']
    keys = [k for k in english if not k.startswith('@')]
    mapping = read_json(DATA / 'mapping.json')
    upstream = {}
    for source in SOURCES:
        upstream[source, 'en'] = load_catalog(cache, source, 'en' if source == 'webui' else 'base', fetch)
        for locale, pair in LOCALES.items():
            upstream[source, locale] = ({} if source == 'komikku_extra' and locale in ('nb', 'nb_NO')
                                        else load_catalog(cache, source, pair[source != 'webui'], fetch))
    for source in {ref['source'] for entry in mapping.values() for ref in entry['sources'] if ref.get('catalog') == 'plurals'}:
        for locale in ['en', *LOCALES]:
            source_locale = 'base' if locale == 'en' else LOCALES[locale][1]
            upstream[source, locale, 'plurals'] = ({} if source == 'mihon' and locale == 'ta'
                                                   else load_catalog(cache, source, source_locale, fetch, 'plurals'))
    allowances = read_json(DATA / 'unchanged.json')

    def source_value(ref, locale):
        catalog_key = (ref['source'], locale, 'plurals') if ref.get('catalog') == 'plurals' else (ref['source'], locale)
        return upstream[catalog_key].get(ref['key'])

    def imported_value(key, ref, locale):
        if locale in mapping[key].get('excluded_locales', {}):
            return None
        return prepare_translation(source_value(ref, locale), key, ref, locale, allowances)

    for key, entry in mapping.items():
        assert english[key] == entry['english'], f'English changed: {key}'
        for ref in entry['sources']:
            assert source_value(ref, 'en') == ref['english'], f'Source changed: {key}/{ref}'
            if 'conversion' in ref:
                validate_spec(english[key], english.get('@' + key, {}), ref)
            else:
                assert safe_static(english[key]), f'Unsupported format: {key}'
    provenance_path = DATA / 'provenance.json'
    provenance = read_json(provenance_path) if provenance_path.exists() else {}
    for locale, entries in provenance.items():
        for key, ref in entries.items():
            assert ref in mapping[key]['sources'], f'Unmapped provenance: {locale}/{key}'
            text = imported_value(key, ref, locale)
            assert text is not None and catalogs[locale].get(key) == text, f'Imported text differs: {locale}/{key}'
    added = 0
    for locale in sorted(LOCALES, key=lambda s: ('_' in s, s)):
        for key, entry in mapping.items():
            if effective(original, locale, key):
                continue
            for ref in entry['sources']:
                text = imported_value(key, ref, locale)
                if text is None:
                    continue
                catalogs[locale][key] = text
                provenance.setdefault(locale, {})[key] = ref
                added += 1
                break
    for locale in provenance:
        if not catalogs[locale].get(NOTICE_KEY):
            catalogs[locale][NOTICE_KEY] = TRANSLATION_NOTICE
        if not write:
            assert original[locale].get(NOTICE_KEY), f'Missing translation notice: {locale}'
    for locale, old in original.items():
        assert all(catalogs[locale][key] == value for key, value in old.items() if value), f'Existing value changed: {locale}'
    report_path = DATA / 'coverage.json'
    report = read_json(report_path) if report_path.exists() else {'baseline': 'fe452d18', 'total': len(keys), 'before': coverage(original, keys)}
    report.setdefault('pass_two', {'baseline': 'dc04b2c1', 'before': coverage(original, keys), 'imports_before': sum(report['imported'].values())})
    report['after'] = coverage(catalogs, keys)
    report['pass_two']['delta'] = {locale: report['after'][locale] - value for locale, value in report['pass_two']['before'].items()}
    report['pass_two']['new_imports'] = sum(len(entries) for entries in provenance.values()) - report['pass_two']['imports_before']
    report['imported'] = {locale: len(entries) for locale, entries in sorted(provenance.items())}
    report['sources'] = {source: {'repository': repo, 'revision': revision, 'path': pattern} for source, (repo, revision, pattern) in SOURCES.items()}
    if write:
        for locale, path in paths.items():
            if catalogs[locale] != original[locale]:
                write_json(path, catalogs[locale])
        write_json(provenance_path, provenance)
        write_json(report_path, report)
    else:
        assert added == 0, f'{added} missing imports; run with --write'
        assert report == read_json(report_path), 'Coverage report differs'
    print(f'{added} additions; {sum(len(v) for v in provenance.values())} recorded imports; preservation and source checks passed')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, default=ROOT / '.local-translation-import/catalogs')
    parser.add_argument('--fetch', action='store_true', help='Download missing catalogs at pinned revisions')
    parser.add_argument('--write', action='store_true', help='Apply missing imports; default checks committed imports')
    args = parser.parse_args()
    run(args.cache, args.fetch, args.write)
