#!/usr/bin/env python3
"""Self-test for the G5 load-all-manifests gate (tools/load_manifests.py).

Proves the gate catches the JT bug (5e90abb): the pre-fix fh_quests bounty jobtype does
`local JT = ... or FhQuestsJobTypes`; FXServer passes a NUMBER as `...`, so indexing JT fails at load.
Also proves strict exports (unregistered export is reported) and the clean case.
"""
import importlib.util, os, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('lm', os.path.join(HERE, 'load_manifests.py'))
lm = importlib.util.module_from_spec(spec); spec.loader.exec_module(lm)
ROOT = lm.ROOT
QUESTS = os.path.join(lm.RESOURCES_ROOT, '[fh]', 'fh_quests')
FIX = os.path.join(ROOT, 'spec', 'fixtures', 'gate')
LUA = lm._get_lua_mod()


def ent(path, display):
    return {'path': path, 'display': display}


def plan(files, name='fh_quests', exports=()):
    return {'resources': [{'name': name, 'system': False, 'dir': QUESTS, 'server': files, 'client': [],
                           'server_exports': list(exports), 'client_exports': [], 'provides': []}]}


class GateTest(unittest.TestCase):
    def test_catches_pre_5e90abb_jt_bug(self):
        r = lm.run_plan(LUA, plan([
            ent(os.path.join(QUESTS, 'shared', 'jobtypes.lua'), 'fh_quests/shared/jobtypes.lua'),
            ent(os.path.join(FIX, 'jt_pre_5e90abb_bounty.lua'), 'fh_quests/shared/jobtypes/bounty.lua'),
        ]))
        hits = [f for f in r['findings'] if f['kind'] == 'top_error' and f['file'].endswith('jobtypes/bounty.lua')]
        self.assertEqual(len(hits), 1, r['findings'])
        self.assertIn('attempt to index a number value', hits[0]['msg'])
        self.assertEqual(hits[0]['line'], 5)  # the JT.registerBuilder call

    def test_fixed_bounty_loads_clean(self):
        r = lm.run_plan(LUA, plan([
            ent(os.path.join(QUESTS, 'shared', 'jobtypes.lua'), 'fh_quests/shared/jobtypes.lua'),
            ent(os.path.join(QUESTS, 'shared', 'jobtypes', 'bounty.lua'), 'fh_quests/shared/jobtypes/bounty.lua'),
        ]))
        self.assertEqual(r['findings'], [])

    def test_strict_exports(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, 'a.lua')
            with open(p, 'w') as f:
                f.write("exports['nope']:fn()\nexports('mine', function() end)\nexports['fh_quests']:mine()\n")
            r = lm.run_plan(LUA, plan([ent(p, 'fh_quests/a.lua')]))
        kinds = [(f['kind'], f['line']) for f in r['findings']]
        self.assertEqual(kinds, [('unresolved_export', 1)], r['findings'])

    # ---- review fixes (rn-c5401c5a016e) ----
    def _res(self, name, server=(), client=(), sexp=(), cexp=()):
        return {'name': name, 'system': False, 'dir': QUESTS, 'server': list(server), 'client': list(client),
                'server_exports': list(sexp), 'client_exports': list(cexp), 'provides': []}

    def _write(self, d, name, text):
        p = os.path.join(d, name)
        with open(p, 'w') as f:
            f.write(text)
        return ent(p, 'x/' + name)

    def test_exports_are_per_side(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            srv = self._write(d, 's.lua', "exports('onlyServer', function() end)\n")
            cli = self._write(d, 'c.lua', "exports['a']:onlyServer()\n")
            r = lm.run_plan(LUA, {'resources': [self._res('a', server=[srv], client=[cli], sexp=['onlyServer'])]})
        self.assertEqual([(f['kind'], f['line']) for f in r['findings']], [('unresolved_export', 1)], r['findings'])
        self.assertIn('client export', r['findings'][0]['msg'])

    def test_missing_ensure_target_is_a_finding(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            cfg = os.path.join(d, 'server.cfg')
            with open(cfg, 'w') as f:
                f.write('ensure fh_quests\nensure not_vendored\n')
            old = lm.CFG_PATH
            lm.CFG_PATH = cfg
            try:
                plan_ = lm.build_plan(LUA)
            finally:
                lm.CFG_PATH = old
        self.assertEqual(plan_['missing'], ['not_vendored'])
        self.assertEqual([r['name'] for r in plan_['resources']], ['fh_quests'])
        r = lm.run_plan(LUA, {'resources': [], 'missing': ['not_vendored']})
        self.assertEqual([(f['kind'], f['res']) for f in r['findings']], [('missing_resource', 'not_vendored')])

    def test_resource_state_follows_load_order(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            probe = self._write(d, 'p.lua', "STATES = { GetResourceState('a'), GetResourceState('b'), GetResourceState('zz') }\n"
                                            "assert(GetResourceState('a') == 'started' and GetResourceState('b') == 'stopped'"
                                            " and GetResourceState('zz') == 'missing', table.concat(STATES, ','))\n")
            r = lm.run_plan(LUA, {'resources': [self._res('a', server=[probe]), self._res('b')]})
        self.assertEqual(r['findings'], [])

    def test_unset_fh_module_global_is_nil(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            f1 = self._write(d, 'u.lua', "assert(FhNotSetYet == nil, 'Fh* global must be nil before it is set')\n"
                                         "local x = FhNotSetYet.field\n")
            r = lm.run_plan(LUA, {'resources': [self._res('a', server=[f1])]})
        self.assertEqual([(f['kind'], f['line']) for f in r['findings']], [('top_error', 2)], r['findings'])


if __name__ == '__main__':
    unittest.main()
