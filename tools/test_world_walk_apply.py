#!/usr/bin/env python3
"""Self-test for world-walk-apply.py: python3 tools/test_world_walk_apply.py (fixture copies in a temp dir, never real data)."""
import contextlib, re, importlib.util, io, json, os, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('wwa', os.path.join(HERE, 'world-walk-apply.py'))
wwa = importlib.util.module_from_spec(spec); spec.loader.exec_module(wwa)

REGIONS = """regions.regions = {
    heartlands = {
        towns = {
            { id = 'valentine',     label = 'Valentine',     x = -169.47, y = 629.38,  z = 113.03 },
            { id = 'emerald_ranch', label = 'Emerald Ranch', x = 1411.0,  y = 355.0,   z = 96.0 },
        },
        ambush = {
            { id = 'heartlands_amb_1', x = 640, y = 560, z = 100, label = 'East stage road bend', verified = false },
        },
    },
}
regions.territories = {
    heartlands_t1_camp = {
        id = 'heartlands_t1_camp',
        label = 'Heartland Bluffs Camp',
        center = { x = -145.0, y = 845.0, z = 117.0 }, -- approximate
        radius = 60.0,
    },
}
"""
HOME = """plots = {
    heartlands_01 = {
        id = 'heartlands_01',
        name = 'Dakota Bend claim',
        verified = false,
        center = V(-500.0, 750.0, 105.0),
        chest = { coords = V(-496.0, 750.0, 105.0), heading = 90.0 },
    },
    heartlands_02 = {
        id = 'heartlands_02',
        name = 'Creekside Pines claim',
        center = V(-620.0, 430.0, 90.0),
    },
}
"""


def rw(path, text=None):
    if text is not None:
        with open(path, 'w') as f: f.write(text)
        return None
    with open(path) as f: return f.read()


def sq(t):  # collapse column-alignment runs of spaces
    return re.sub(r'(?<=\S) {2,}(?=\S)', ' ', t)


def run(marks, regions=REGIONS, home=HOME):
    with tempfile.TemporaryDirectory() as d:
        r, h, w = (os.path.join(d, n) for n in ('regions.lua', 'home.lua', 'walk.json'))
        rw(r, regions); rw(h, home)
        if marks is not None:
            rw(w, marks if isinstance(marks, str) else json.dumps(marks))
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = wwa.main(['--apply', '--no-specs', '--walk', w, '--file', r, '--file', h])
        return code, sq(rw(r)), sq(rw(h)), out.getvalue()


def m(id, verdict, **kw):
    return dict(id=id, verdict=verdict, **kw)


class WalkApply(unittest.TestCase):
    def test_ok_sets_verified_everywhere(self):
        _, r, h, _ = run([m('valentine', 'ok'), m('heartlands_amb_1', 'ok'), m('heartlands_t1_camp', 'ok'),
                          m('heartlands_02', 'ok')])
        self.assertIn("z = 113.03, verified = true }", r)          # one-liner, no field -> appended
        self.assertIn("z = 100, label = 'East stage road bend', verified = true }", r)  # flag flipped
        self.assertIn("id = 'heartlands_t1_camp',\n        verified = true,\n", r)  # block, inserted
        self.assertIn("id = 'heartlands_02',\n        verified = true,\n", h)

    def test_bad_with_coords_moves_and_verifies(self):
        _, r, h, out = run([m('emerald_ranch', 'bad', x=1400.5, y=360, z=97.25), m('heartlands_01', 'bad', x=-510, y=760.5, z=106),
                            m('heartlands_t1_camp', 'bad', x=-150, y=850)])
        self.assertIn("x = 1400.5, y = 360.0, z = 97.25, verified = true }", r)
        self.assertIn("center = V(-510.0, 760.5, 106.0),", h)
        self.assertIn("verified = true,", h)
        self.assertNotIn("verified = false", h)
        self.assertIn("center = { x = -150.0, y = 850.0, z = 117.0 }, -- approximate", r)  # no z -> keep hint
        self.assertIn("coords = V(-496.0, 750.0, 105.0)", h)        # chest untouched
        self.assertIn("label = 'Emerald Ranch'", r)                  # names untouched

    def test_bad_without_coords_is_todo_and_untouched(self):
        code, r, h, out = run([m('valentine', 'bad', note='in a building'), m('heartlands_01', 'bad', x='?', y=None)])
        self.assertEqual((r, h), (sq(REGIONS), sq(HOME)))
        self.assertIn('TODO    valentine: bad, no usable coords — note: in a building', out)
        self.assertIn('TODO    heartlands_01', out)

    def test_unknown_id_reported(self):
        _, r, h, out = run([m('nowhere', 'ok')])
        self.assertEqual((r, h), (sq(REGIONS), sq(HOME)))
        self.assertIn('UNKNOWN nowhere', out)

    def test_last_verdict_wins(self):
        _, r, _, out = run([m('valentine', 'ok'), m('valentine', 'bad', x=-100, y=600, z=110), m('emerald_ranch', 'bad', note='x'),
                            m('emerald_ranch', 'ok')])
        self.assertIn("x = -100.0, y = 600.0, z = 110.0, verified = true }", r)
        self.assertIn("z = 96.0, verified = true }", r)              # emerald: later ok beat earlier bad, coords unchanged
        self.assertIn('valentine: 2 verdicts, last wins (bad)', out)
        self.assertNotIn('TODO    emerald_ranch', out)

    def test_empty_or_missing_file_is_noop(self):
        for marks in ('', '[]', '   \n', None):
            code, r, h, out = run(marks)
            self.assertEqual(code, 0)
            self.assertEqual((r, h), (sq(REGIONS), sq(HOME)))

    def test_idempotent(self):
        marks = [m('emerald_ranch', 'bad', x=1400.5, y=360, z=97.25), m('heartlands_01', 'ok')]
        _, r, h, _ = run(marks)
        _, r2, h2, _ = run(marks, r, h)  # sq() is idempotent, so squashed text is a valid second input
        self.assertEqual((r, h), (r2, h2))

    def test_bad_json_errors(self):
        with tempfile.TemporaryDirectory() as d:
            w = os.path.join(d, 'w.json'); rw(w, '{nope')
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(wwa.main(['--walk', w, '--file', os.path.join(d, 'none.lua')]), 2)


class Review(unittest.TestCase):
    def test_dry_run_writes_nothing(self):
        with tempfile.TemporaryDirectory() as d:
            r, w = os.path.join(d, 'r.lua'), os.path.join(d, 'w.json')
            rw(r, REGIONS); rw(w, json.dumps([m('valentine', 'ok')]))
            with contextlib.redirect_stdout(io.StringIO()) as out:
                self.assertEqual(wwa.main(['--walk', w, '--file', r]), 0)
            self.assertEqual(rw(r), REGIONS)
            self.assertIn('dry run', out.getvalue())
            self.assertIn('+++', out.getvalue())

    def test_zone_camp_bad_with_coords_is_todo(self):
        zones = "camps = {\n    heartlands_t1_01 = {\n        id = 'heartlands_t1_01',\n        territory = 'heartlands_t1_camp',\n        verified = false,\n    },\n}\n"
        _, r, h, out = run([m('heartlands_t1_01', 'bad', x=1, y=2, z=3)], home=zones)
        self.assertEqual(h, sq(zones))
        self.assertIn('TODO    heartlands_t1_01', out)

    def test_duplicate_anchor_is_todo_and_untouched(self):
        dup = REGIONS + "regions.posts = {\n    valentine = { id = 'valentine', x = 1, y = 2, z = 3 },\n}\n"
        _, r, h, out = run([m('valentine', 'ok')], regions=dup)
        self.assertEqual(r, sq(dup))
        self.assertRegex(out, r'TODO    valentine: ambiguous id \(regions.lua:\d+, regions.lua:\d+\)')

    def test_oneliner_with_trailing_comment(self):
        reg = "towns = {\n    { id = 'a', x = 1.0, y = 2.0, z = 3.0 }, -- approx\n    { id = 'b', x = 1.0, y = 2.0, z = 3.0, verified = false }, -- tbd\n}\n"
        _, r, _, _ = run([m('a', 'ok'), m('b', 'bad', x=5, y=6)], regions=reg)
        self.assertIn("{ id = 'a', x = 1.0, y = 2.0, z = 3.0, verified = true }, -- approx", r)
        self.assertIn("{ id = 'b', x = 5.0, y = 6.0, z = 3.0, verified = true }, -- tbd", r)


if __name__ == '__main__':
    unittest.main()
