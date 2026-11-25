#!/usr/bin/env python3
"""Self-test for world-walk-sheet.py: ~/.venvs/rf/bin/python tools/test_world_walk_sheet.py"""
import importlib.util, os, re, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('wws', os.path.join(HERE, 'world-walk-sheet.py'))
wws = importlib.util.module_from_spec(spec); spec.loader.exec_module(wws)

ENABLED = ['bayou_nwa', 'great_plains', 'heartlands', 'scarlett_meadows']


class WalkSheet(unittest.TestCase):
    def test_lists_every_unverified_place_in_enabled_regions(self):
        data = wws.region_data()
        self.assertEqual(sorted(r[0] for r in data), ENABLED)
        for rid, _, _, rows in data:
            self.assertGreater(len(rows), 0, rid)
            self.assertEqual(len({r[0] for r in rows}), len(rows), 'duplicate place in ' + rid)
        # Every unverified (non-origin-town) place the index has for the region appears in the block.
        block = wws.render(data)
        for rid, _, origin, rows in data:
            for pid, *_ in rows:
                self.assertIn('`%s`' % pid, block)
            self.assertNotIn('`%s` -' % origin, block)

    def test_rerun_is_a_no_op_and_rest_of_file_untouched(self):
        block = wws.render(wws.region_data())
        base = 'head\n\nmiddle text\n'
        once = wws.apply(base, block)
        self.assertEqual(wws.apply(once, block), once)
        self.assertTrue(once.startswith(base))
        edited = once + '\ntrailing owner notes\n'
        self.assertEqual(wws.apply(edited, block), edited)
        stale = once.replace('RESULT:', 'X', 1)
        self.assertEqual(wws.apply(stale, block), once)

    def test_committed_file_is_current(self):
        with open(wws.DOC, encoding='utf-8', newline='') as f:
            old = f.read()
        self.assertEqual(wws.apply(old, wws.render(wws.region_data())), old)


if __name__ == '__main__':
    unittest.main()
