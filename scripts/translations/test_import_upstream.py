import tempfile
from pathlib import Path
import unittest

from import_upstream import android_text, effective, parse_catalog, safe_static


class ImportTests(unittest.TestCase):
    def test_android_escapes_preserve_unicode(self):
        self.assertEqual(android_text(r"L\'été\n日本語 \u00e9"), "L'été\n日本語 é")
        self.assertEqual(android_text('" text "'), ' text ')
        self.assertIsNone(android_text(r'bad\q'))
        self.assertFalse(safe_static(android_text(r'literal\\n')))

    def test_unsupported_formats_are_rejected(self):
        for text in ('', ' ', '{count}', '{count, plural, other {items}}', '%1$s', '<b>text</b>', '%d', '%1$02d', '%.2f', '@string/name', '?attr/name'):
            self.assertFalse(safe_static(text), text)
        self.assertTrue(safe_static('日本語 100%'))

    def test_android_reads_plural_and_ignores_markup_and_nontranslatable(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'strings.xml'
            path.write_text('''<resources>
                <string name="good">A &amp; B</string>
                <string name="markup"><b>Bold</b></string>
                <string name="brand" translatable="false">Name</string>
                <plurals name="count"><item quantity="other">Items</item></plurals>
            </resources>''')
            self.assertEqual(parse_catalog(path, 'mihon'), {'good': 'A & B', 'count': {'other': 'Items'}})

    def test_po_ignores_fuzzy_obsolete_and_plural(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'strings.po'
            path.write_text('''msgid "Good"
msgstr "Bien"

#, fuzzy
msgid "Uncertain"
msgstr "Incertain"

#~ msgid "Old"
#~ msgstr "Ancien"

msgid "One"
msgid_plural "Many"
msgstr[0] "Un"
msgstr[1] "Plusieurs"
''')
            self.assertEqual(parse_catalog(path, 'webui'), {'Good': 'Bien'})

    def test_regional_inheritance_preserves_existing_effective_values(self):
        catalogs = {'pt': {'base': 'base text', 'empty': ''}, 'pt_BR': {'own': 'own text'}}
        self.assertEqual(effective(catalogs, 'pt_BR', 'base'), 'base text')
        self.assertEqual(effective(catalogs, 'pt_BR', 'own'), 'own text')
        self.assertIsNone(effective(catalogs, 'pt_BR', 'missing'))


if __name__ == '__main__':
    unittest.main()
