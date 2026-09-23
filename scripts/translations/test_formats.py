import unittest

from formats import android_format, convert, plural_parts, validate_spec
from import_upstream import prepare_translation


class FormatTests(unittest.TestCase):
    def setUp(self):
        self.args = {'1': {'name': 'name', 'type': 'String', 'format': 's'},
                     '2': {'name': 'count', 'type': 'int', 'format': 'd'}}
        self.ref = {'english': '%1$s has %2$d', 'conversion': {'kind': 'android', 'arguments': self.args}}
        self.plural = {'kind': 'android_plural', 'argument': {'name': 'count', 'type': 'int'}, 'format': 'd', 'exact': [1]}

    def test_reordered_arguments_and_unicode(self):
        self.assertEqual(android_format('%2$d : %1$s 日本語', self.args), '{count} : {name} 日本語')
        self.assertEqual(android_format('%s : %d', self.args), '{name} : {count}')

    def test_rejects_missing_repeated_mistyped_and_malformed_formats(self):
        for text in ('%1$s', '%1$s %1$s %2$d', '%2$s %1$s', '%3$s %2$d',
                     '%1$02d %2$s', '%.2f %s', '%s %2$d', '1%s 2%d', '%1$s $2%d', '<b>%1$s</b> %2$d'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                android_format(text, self.args)

    def test_unchanged_check_happens_before_format_conversion(self):
        empty = {'invariant': {}, 'locales': {}}
        self.assertIsNone(prepare_translation('%1$s has %2$d', 'example', self.ref, 'de', empty))
        allowed = {'invariant': {}, 'locales': {'de': {'example': 'Reviewed term'}}}
        self.assertEqual(prepare_translation('%1$s has %2$d', 'example', self.ref, 'de', allowed), '{name} has {count}')
        self.assertIsNone(prepare_translation('%1$s has %2$d', 'example', self.ref, 'fr', allowed))

    def test_target_names_and_types_checked(self):
        validate_spec('{name} has {count}', {'placeholders': {'name': {'type': 'String'}, 'count': {'type': 'int'}}}, self.ref)
        with self.assertRaises(ValueError):
            validate_spec('{name} has {other}', {}, self.ref)
        with self.assertRaises(ValueError):
            validate_spec('{name} has {count}', {'placeholders': {'name': {'type': 'String'}, 'count': {'type': 'String'}}}, self.ref)

    def test_rejects_select_nested_and_missing_other(self):
        for text in ('{count, select, one{a} other{b}}', '{count, plural, one{a}}',
                     '{count, plural, one{a} other{{x, plural, one{b} other{c}}}}'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                plural_parts(text)

    def test_keeps_arabic_zero_two_few_many_and_exact_one(self):
        raw = {'zero': 'لا مستودعات', 'one': 'مستودع', 'two': 'مستودعان',
               'few': '%d مستودعات', 'many': '%d مستودعات', 'other': '%d مستودعات'}
        text = convert(raw, {'conversion': self.plural}, 'ar')
        _, branches = plural_parts(text)
        self.assertEqual(set(branches), {'=1', 'zero', 'two', 'few', 'many', 'other'})
        self.assertEqual(branches['=1'], 'مستودع')
        self.assertEqual(branches['few'], '{count} مستودعات')

    def test_rejects_hardcoded_russian_one_and_missing_categories(self):
        raw = {'one': '1 день', 'few': '%d дня', 'many': '%d дней', 'other': '%d дня'}
        with self.assertRaisesRegex(ValueError, 'Hardcoded'):
            convert(raw, {'conversion': self.plural}, 'ru')
        raw['one'] = 'Вчера'
        with self.assertRaisesRegex(ValueError, 'Count omitted'):
            convert(raw, {'conversion': self.plural}, 'ru')
        with self.assertRaisesRegex(ValueError, 'Missing locale'):
            convert({'one': '%d день', 'other': '%d дни'}, {'conversion': self.plural}, 'ru')

    def test_hash_becomes_explicit_argument(self):
        spec = {'kind': 'icu_plural', 'source_argument': '0', 'argument': {'name': 'count', 'type': 'int'}, 'exact': [1]}
        text = convert('{0, plural, one {# Tag} other {# Tage}}', {'conversion': spec}, 'de')
        self.assertEqual(text, '{count, plural, =1{{count} Tag} other{{count} Tage}}')

    def test_rejects_blank_singleton_branch(self):
        with self.assertRaisesRegex(ValueError, 'Empty plural'):
            convert({'one': ' ', 'other': '%d Tage'}, {'conversion': self.plural}, 'de')

    def test_zero_selector_cannot_be_dropped(self):
        ref = {'english': {'one': '%d day', 'other': '%d days'}, 'conversion': self.plural}
        with self.assertRaisesRegex(ValueError, 'exact selectors'):
            validate_spec('{count, plural, =0{None} =1{1 day} other{{count} days}}', {'placeholders': {'count': {'type': 'int'}}}, ref)

    def test_plain_numeric_target_can_gain_cardinal_forms(self):
        spec = {**self.plural, 'target': 'interpolation', 'exact': []}
        ref = {'english': {'one': 'Next chapter', 'other': 'Next %d chapters'}, 'conversion': spec}
        validate_spec('Next {count} chapters', {'placeholders': {'count': {'type': 'int'}}}, ref)
        text = convert({'one': 'Nächstes Kapitel', 'other': 'Nächste %d Kapitel'}, ref, 'de')
        self.assertEqual(text, '{count, plural, one{Nächstes Kapitel} other{Nächste {count} Kapitel}}')


if __name__ == '__main__':
    unittest.main()
