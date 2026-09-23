"""Strict conversions for the explicitly mapped message formats."""
from collections import Counter
import re

from babel import Locale

PRINTF = re.compile(r'%(?:(\d+)\$)?([sd])')
ARGUMENT = re.compile(r'\{([A-Za-z]\w*)\}')
CATEGORIES = ('zero', 'one', 'two', 'few', 'many', 'other')
BRANCH = re.compile(r'\s*(zero|one|two|few|many|other|=\d+)\s*\{((?:[^{}]|\{[A-Za-z]\w*\})*)\}')


def android_format(text, arguments, optional=False):
    if not isinstance(text, str) or re.search(r'[{}<>\\]|^[@?]|\d%[sd]', text):
        raise ValueError('Unsupported Android text')
    seen = []
    modes = set()
    position = 0

    def replace(match):
        nonlocal position
        position += 1
        modes.add(bool(match[1]))
        index = match[1] or str(position)
        if index not in arguments or arguments[index]['format'] != match[2]:
            raise ValueError('Unexpected argument position or type')
        seen.append(index)
        return '{' + arguments[index]['name'] + '}'

    result = PRINTF.sub(replace, text)
    if '%' in result or '$' in result or len(modes) > 1:
        raise ValueError('Unsupported or mixed printf arguments')
    if not optional and Counter(seen) != Counter(arguments.keys()):
        raise ValueError('Missing or repeated argument')
    if optional and any(count > 1 for count in Counter(seen).values()):
        raise ValueError('Repeated plural argument')
    return result


def plural_parts(text):
    match = re.fullmatch(r'\{(\w+),\s*plural,\s*(.*)\}', text, re.DOTALL)
    if not match:
        raise ValueError('Expected one whole-message cardinal plural')
    branches = {}
    position = 0
    for branch in BRANCH.finditer(match[2]):
        if branch.start() != position or branch[1] in branches:
            raise ValueError('Unsupported or duplicate plural branch')
        branches[branch[1]] = branch[2]
        position = branch.end()
    if match[2][position:].strip() or 'other' not in branches:
        raise ValueError('Unsupported plural body or missing other')
    return match[1], branches


def convert_plural(raw, spec, locale):
    name = spec['argument']['name']
    if spec['kind'] == 'icu_plural':
        source_name, branches = plural_parts(raw)
        if source_name != spec['source_argument'] or any('{' in body or "'" in body for body in branches.values()):
            raise ValueError('Unsupported ICU argument, nesting or apostrophe quoting')
        branches = {category: body.replace('#', '{' + name + '}') for category, body in branches.items()}
    else:
        if not isinstance(raw, dict) or 'other' not in raw:
            raise ValueError('Missing Android plural')
        arguments = {'1': {**spec['argument'], 'format': spec['format']}}
        branches = {category: android_format(body, arguments, optional=True) for category, body in raw.items()}
    if any(not body.strip() for body in branches.values()):
        raise ValueError('Empty plural branch')
    rule = Locale.parse(locale).plural_form
    allowed = rule.tags | {'other'}
    if not set(branches) <= set(CATEGORIES):
        raise ValueError('Unsupported source plural selectors')
    # Some catalogs retain unused CLDR forms. They never select at runtime.
    branches = {category: body for category, body in branches.items() if category in allowed}
    if not allowed <= branches.keys():
        raise ValueError('Missing locale plural categories')
    samples = list(range(202)) + [1000, 1000000]
    if spec['argument']['type'] == 'num':
        samples += [0.1, 0.5, 1.1, 1.5, 2.1, 10.5, 21.1]
    for category, body in branches.items():
        selected = [n for n in samples if str(rule(n)) == category]
        literals = re.findall(r'\d+', ARGUMENT.sub('', body))
        if literals and any(any(int(literal) != n for n in selected) for literal in literals):
            raise ValueError('Hardcoded number contradicts plural category')
        if '{' + name + '}' not in body and len(selected) > 1:
            raise ValueError('Count omitted from non-singleton plural category')
        if re.search(r'[<>\\]|%(?:\d+\$)?[-#+ 0,(]*\d*(?:\.\d+)?[a-zA-Z]', body):
            raise ValueError('Unsupported plural markup or formatting')
    result = {}
    for number in spec['exact']:
        result[f'={number}'] = branches.get(str(rule(number)), branches['other'])
    if 1 in spec['exact'] and str(rule(1)) == 'one':
        branches.pop('one', None)
    result.update(branches)
    return '{' + name + ', plural, ' + ' '.join(category + '{' + body + '}' for category, body in result.items()) + '}'


def convert(raw, ref, locale):
    spec = ref.get('conversion')
    if spec is None:
        return raw
    if spec['kind'] == 'android':
        return android_format(raw, spec['arguments'])
    if spec['kind'] in ('android_plural', 'icu_plural'):
        return convert_plural(raw, spec, locale)
    raise ValueError('Unknown conversion')


def validate_spec(target, metadata, ref):
    spec = ref['conversion']
    if spec['kind'] == 'android':
        arguments = list(spec['arguments'].values())
        expected = Counter(ARGUMENT.findall(target))
        if expected != Counter(arg['name'] for arg in arguments):
            raise ValueError('Target argument names or counts differ')
        android_format(ref['english'], spec['arguments'])
    else:
        arguments = [spec['argument']]
        if spec.get('target') == 'interpolation':
            if ARGUMENT.findall(target) != [arguments[0]['name']] or spec['exact']:
                raise ValueError('Target count or exact selectors differ')
        else:
            name, branches = plural_parts(target)
            if name != arguments[0]['name'] or {key for key in branches if key.startswith('=')} != {f'={n}' for n in spec['exact']}:
                raise ValueError('Target exact selectors differ')
        if arguments[0]['type'] not in ('int', 'num'):
            raise ValueError('Plural selector must be numeric')
        convert(ref['english'], ref, 'en')
    for argument in arguments:
        actual = metadata.get('placeholders', {}).get(argument['name'], {}).get('type')
        inferred = 'num' if spec['kind'].endswith('_plural') else 'Object'
        if (actual or inferred) != argument['type']:
            raise ValueError('Target argument type differs')
        if argument.get('format') == 'd' and argument['type'] not in ('int', 'num'):
            raise ValueError('Integer format requires numeric target')
