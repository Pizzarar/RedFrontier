#!/usr/bin/env python3
"""Self-test for check-contracts.py: python3 tools/test_check_contracts.py (fixture resource trees in a temp dir)."""
import importlib.util, os, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('cc', os.path.join(HERE, 'check-contracts.py'))
cc = importlib.util.module_from_spec(spec); spec.loader.exec_module(cc)

def write(root, rel, text):
    p = os.path.join(root, rel); os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w') as f: f.write(text)

MANIFEST = "fx_version 'cerulean'\n%s\n"

def tree(root, srv_a, cli_a='', mfa='server_scripts { "s.lua" }\nclient_scripts { "c.lua" }\nserver_exports { "ok" }',
         cfg_items='', events_b='', cfg='ensure rsg-core\nensure fh_a\nensure fh_b\n'):
    write(root, 'server.cfg', cfg)
    r = os.path.join(root, 'resources')
    write(r, '[fh]/fh_a/fxmanifest.lua', MANIFEST % mfa)
    write(r, '[fh]/fh_a/s.lua', "exports('ok', function() end)\nexports('srvOnly', function() end)\n" + events_b)
    write(r, '[fh]/fh_a/c.lua', "exports('cliFn', function() end)\n")
    write(r, '[fh]/fh_b/fxmanifest.lua', MANIFEST % 'server_scripts { "s.lua" }\nclient_scripts { "c.lua" }\nshared_scripts { "config.lua" }')
    write(r, '[fh]/fh_b/s.lua', srv_a)
    write(r, '[fh]/fh_b/c.lua', cli_a)
    write(r, '[fh]/fh_b/config.lua', cfg_items)
    write(r, '[rsg]/rsg-core/fxmanifest.lua', MANIFEST % '')
    write(r, '[rsg]/rsg-core/shared/items.lua', "RSGShared.Items = {\n  bread = { name = 'bread', label = 'Bread' },\n}\n")
    return os.path.join(r), os.path.join(root, 'server.cfg')

def findings(root_cfg, rule=None):
    return [f for f in cc.run(*root_cfg) if rule is None or f[0] == rule]

class T(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.TemporaryDirectory(); self.root = self.d.name
    def tearDown(self): self.d.cleanup()

    def test_clean(self):
        t = tree(self.root, "exports.fh_a:ok()\nexports['rsg-core']:X()\n", "exports.fh_a:ok()" if False else '',
                 events_b="RegisterNetEvent('fh:a:ping', function() end)\n")
        write(self.root, 'resources/[fh]/fh_b/s.lua',
              "exports.fh_a:ok()\nexports['rsg-core']:X()\nTriggerEvent('fh:a:ping')\n")
        write(self.root, 'resources/[fh]/fh_b/config.lua', "loot = { { name = 'bread', chance = 1 }, item = 'bread' }\n")
        self.assertEqual(findings(t), [])

    def test_missing_export_and_side(self):
        t = tree(self.root, "exports.fh_a:nope()\nexports.fh_a:cliFn()\n")
        keys = sorted(f[1] for f in findings(t, 'exports'))
        self.assertEqual(keys, ['fh_a:cliFn', 'fh_a:nope'])   # cliFn is client-only, called from a server script

    def test_unknown_and_unensured_resource(self):
        t = tree(self.root, "exports.ghost:f()\nexports['rsg-core']:X()\n", cfg='ensure fh_a\nensure fh_b\n')
        msgs = ' '.join(f[3] for f in findings(t, 'exports'))
        self.assertIn("'ghost' not found", msgs)
        self.assertIn("'rsg-core' is not ensured", msgs)

    def test_category_ensure_and_comments(self):
        t = tree(self.root, "-- exports.ghost:f()\n--[[ exports.ghost:g() ]]\nexports.fh_a:ok()\n", cfg='ensure [fh]\nensure [rsg]\n')
        self.assertEqual(findings(t, 'exports'), [])

    def test_event_without_listener_and_orphan_handler(self):
        t = tree(self.root, "TriggerClientEvent('fh:x:nobody', 1)\nRegisterNetEvent('fh:x:orphan', function() end)\n")
        keys = sorted(f[1] for f in findings(t, 'events'))
        self.assertEqual(keys, ['fh:x:nobody', 'fh:x:orphan'])

    def test_event_wrong_side_and_indirect_sender(self):
        t = tree(self.root, "RegisterNetEvent('fh:x:srv', function() end)\nTriggerClientEvent('fh:x:srv', 1)\n"
                 "RegisterNetEvent('fh:x:viaconst', function() end)\nlocal E = 'fh:x:viaconst'\n")
        keys = sorted(f[1] for f in findings(t, 'events'))
        self.assertEqual(keys, ['fh:x:srv'])   # listener is server-side, sender targets client; constant counts as sender

    def test_documented_event_needs_no_listener(self):
        t = tree(self.root, "TriggerEvent('fh:b:bus')\n")
        write(self.root, 'resources/[fh]/fh_b/README.md', 'Emits `fh:b:bus`.')
        self.assertEqual(findings(t, 'events'), [])

    def test_unknown_item(self):
        t = tree(self.root, "", cfg_items="loot = { { name = 'ghost_item', chance = 1 }, { item = 'bread' }, { item = 'phantom' } }\n")
        self.assertEqual(sorted(f[1] for f in findings(t, 'items')), ['ghost_item', 'phantom'])

    def test_fh_item_definition_counts(self):
        t = tree(self.root, "", cfg_items="items = { gun_parts = { label = 'Gun Parts', weight = 1 } }\nloot = { { name = 'gun_parts', chance = 1 } }\n")
        self.assertEqual(findings(t, 'items'), [])

    def test_table_item_with_label_defines_item(self):
        t = tree(self.root, "")
        write(self.root, 'resources/[fh]/fh_b/data/items.lua', "return {\n  pelt = { item = 'p1', label = 'P' },\n}\n")
        self.assertEqual(findings(t, 'items'), [])

    def test_multiline_table_label_before_item_defines_item(self):
        t = tree(self.root, "")
        write(self.root, 'resources/[fh]/fh_b/data/items.lua',
              "return {\n  trophy = {\n    label = 'Trophy',\n    comfort = 10,\n    item = 't1',\n  },\n}\n")
        self.assertEqual(findings(t, 'items'), [])

    def test_plain_item_reference_without_label_is_finding(self):
        t = tree(self.root, "")
        write(self.root, 'resources/[fh]/fh_b/data/loot.lua', "return { { item = 'nope', amount = 1 } }\n")
        self.assertEqual([f[1] for f in findings(t, 'items')], ['nope'])

    def test_nested_table_label_does_not_define_outer_item(self):
        t = tree(self.root, "")
        write(self.root, 'resources/[fh]/fh_b/data/nested.lua',
              "return {\n  row = {\n    item = 'outer_only',\n    meta = { label = 'Inner Label' },\n  },\n}\n")
        self.assertEqual([f[1] for f in findings(t, 'items')], ['outer_only'])

    def test_label_inside_string_or_long_bracket_is_not_a_label_field(self):
        t = tree(self.root, "")
        write(self.root, 'resources/[fh]/fh_b/data/str.lua',
              "return {\n  a = { item = 'only_str', note = 'label = x' },\n"
              "  b = { item = 'only_long', note = [[ label = y ]] },\n"
              "  c = { item = 'real_def', label = 'R' },\n}\n")
        self.assertEqual(sorted(f[1] for f in findings(t, 'items')), ['only_long', 'only_str'])

    def test_allowlist_and_stale_fails(self):
        t = tree(self.root, "exports.fh_a:nope()\n")
        al = os.path.join(self.root, 'allow.txt')
        write(self.root, 'allow.txt', 'exports|fh_a:nope  # idea-1\nexports|fh_a:gone  # stale\n')
        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = cc.main(['--root', t[0], '--cfg', t[1], '--allowlist', al])
        self.assertEqual(rc, 1)   # stale entry fails the gate
        self.assertIn('stale allowlist entry', buf.getvalue())
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(cc.main(['--root', t[0], '--cfg', t[1], '--allowlist', os.path.join(self.root, 'none')]), 1)

    def test_manifest_exports_is_client_side(self):
        t = tree(self.root, "exports.fh_a:viaManifest()\n", mfa='server_scripts { "s.lua" }\nclient_scripts { "c.lua" }\nexports { "viaManifest" }')
        self.assertEqual([f[1] for f in findings(t, 'exports')], ['fh_a:viaManifest'])  # server caller, client-only export

    def test_dynamic_event_name_skipped(self):
        t = tree(self.root, "TriggerEvent('fh:x_' .. v)\nTriggerEvent('fh:y:' .. v, 1)\n")
        self.assertEqual(findings(t, 'events'), [])

    def test_prefixed_export_loop_per_side(self):
        t = tree(self.root, "exports.fh_a:FhThing()\nexports.fh_a:FhCli()\n",
                 mfa='server_scripts { "s.lua" }\nclient_scripts { "c.lua" }')
        write(self.root, 'resources/[fh]/fh_a/s.lua', "local T = {}\nfunction T.Thing() end\nfor k, f in pairs(T) do exports('Fh' .. k, f) end\n")
        write(self.root, 'resources/[fh]/fh_a/c.lua', "function T.Cli() end\n")   # client file, no loop: not exported
        self.assertEqual([f[1] for f in findings(t, 'exports')], ['fh_a:FhCli'])

    # ---- G1c: module-constant event names resolve as listeners ----
    def test_module_constant_event_listener(self):
        t = tree(self.root, "TriggerEvent('fh:b:wipe')\n")
        write(self.root, 'resources/[fh]/fh_b/config.lua',
              "local M = {}\nM.SQUAD_EVENT = 'fh:b:wipe'\noffer = { on = M.SQUAD_EVENT }\n")
        self.assertEqual(findings(t, 'events'), [])

    # ---- G1b: event-target namespace must exist on disk ----
    def test_event_target_missing_namespace(self):
        t = tree(self.root, "TriggerEvent('rsg-weapons:client:UseWeapon')\n")
        self.assertEqual(sorted(f[1] for f in findings(t, 'event-target')), ['rsg-weapons:client:UseWeapon'])

    def test_event_target_self_contained_namespace(self):
        t = tree(self.root, "TriggerServerEvent('rsg-multicharacter:server:createCharacter')\n"
                 "RegisterNetEvent('rsg-multicharacter:server:createCharacter', function() end)\n")
        self.assertEqual(findings(t, 'event-target'), [])

    def test_event_target_provided_namespace(self):
        t = tree(self.root, "TriggerEvent('rsg-multijob:server:jobsLoaded')\n")
        write(self.root, 'resources/[rsg]/rsg-core/fxmanifest.lua', MANIFEST % "provide 'rsg-multijob'\n")
        self.assertEqual(findings(t, 'event-target'), [])

    def test_event_target_disabled_config_flag(self):
        t = tree(self.root, "", cli_a="    if Config.Opt then\n        TriggerServerEvent('rsg-opt:server:x')\n    end\n",
                 cfg_items="Config = {}\nConfig.Opt = false\n")
        self.assertEqual(findings(t, 'event-target'), [])
        write(self.root, 'resources/[fh]/fh_b/config.lua', "Config = {}\nConfig.Opt = true\n")
        self.assertEqual([f[1] for f in findings(t, 'event-target')], ['rsg-opt:server:x'])

    # ---- G1a: useable=true items need a use handler ----
    def test_useable_item_without_handler(self):
        t = tree(self.root, "", cfg_items="loot = { { name = 'bandage', chance = 1 } }\n")
        write(self.root, 'resources/[rsg]/rsg-core/shared/items.lua',
              "RSGShared.Items = { bread = { name = 'bread', label = 'Bread' }, "
              "bandage = { name = 'bandage', label = 'Bandage', useable = true } }\n")
        self.assertEqual(sorted(f[1] for f in findings(t, 'useable')), ['bandage'])

    def test_useable_item_with_handler(self):
        t = tree(self.root, "", cfg_items="loot = { { name = 'bread', chance = 1 } }\n")
        write(self.root, 'resources/[rsg]/rsg-core/shared/items.lua',
              "RSGShared.Items = { bread = { name = 'bread', label = 'Bread', useable = true } }\n")
        write(self.root, 'resources/[fh]/fh_a/s.lua',
              "exports('ok', function() end)\nexports['rsg-core']:CreateUseableItem('bread', function() end)\n")
        self.assertEqual(findings(t, 'useable'), [])

    def test_useable_handler_via_use_table_loop(self):
        t = tree(self.root, "", cfg_items="loot = { { name = 'stew', chance = 1 } }\n")
        write(self.root, 'resources/[rsg]/rsg-core/shared/items.lua',
              "RSGShared.Items = { stew = { name = 'stew', label = 'Stew', useable = true } }\n")
        write(self.root, 'resources/[fh]/fh_a/s.lua',
              "exports('ok', function() end)\nI.USE = { stew = { hunger = 5 } }\n"
              "for name, d in pairs(I.USE) do exports['rsg-core']:CreateUseableItem(name, function() end) end\n")
        self.assertEqual(findings(t, 'useable'), [])

    def test_additem_literal_undefined(self):
        t = tree(self.root, "AddItem(src, 'ghost_item', 1)\n")
        self.assertEqual(sorted(f[1] for f in findings(t, 'items')), ['ghost_item'])

    def test_dead_item_is_warning_not_finding(self):
        t = tree(self.root, "", cfg_items="loot = { { name = 'bread', chance = 1 } }\n")
        self.assertEqual(findings(t, 'useable'), [])
        self.assertIn('bread', [w[1] for w in cc.WARNINGS if w[0] == 'dead'])

    def test_fh_item_missing_icon_is_warning(self):
        t = tree(self.root, "")
        write(self.root, 'resources/[fh]/fh_inventory/fxmanifest.lua', MANIFEST % '')
        write(self.root, 'resources/[fh]/fh_inventory/html/images/has_icon.png', 'x')
        write(self.root, 'resources/[fh]/fh_a/items.lua',
              "I = { has_icon = { name = 'has_icon', label = 'A', weight = 1 }, no_icon = { name = 'no_icon', label = 'B', weight = 1 }, menu = { label = 'Menu' } }\n")
        self.assertEqual([f for f in findings(t) if f[0] == 'icon'], [])
        self.assertEqual([w[1] for w in cc.WARNINGS if w[0] == 'icon'], ['no_icon'])

    def test_manifest_literal_missing(self):
        t = tree(self.root, "", mfa='server_scripts { "s.lua", "gone.lua" }\nclient_scripts { "c.lua" }')
        self.assertEqual(sorted(f[1] for f in findings(t, 'manifest')), ['fh_a:gone.lua'])

    def _items(self, extra=''):
        write(self.root, 'resources/[rsg]/rsg-core/shared/items.lua',
              "RSGShared.Items = {\n" + extra + "}\n")

    def test_useable_via_helper_loop_with_bracket_keys(self):
        t = tree(self.root, "", cfg_items="loot = { { name = 'ammo_box_x', chance = 1 } }\n")
        self._items("ammo_box_x = { name = 'ammo_box_x', label = 'Box', useable = true },\n")
        write(self.root, 'resources/[fh]/fh_a/shared.lua', "Config = {}\nConfig.BoxAmmo = {\n  ['ammo_box_x'] = 'AMMO_X',\n}\n")
        write(self.root, 'resources/[fh]/fh_a/s.lua',
              "exports('ok', function() end)\nlocal function reg(itemName, a)\n"
              "  exports['rsg-core']:CreateUseableItem(itemName, function() end)\nend\n"
              "for itemName, a in pairs(Config.BoxAmmo) do\n  reg(itemName, a)\nend\n")
        self.assertEqual(findings(t, 'useable'), [])

    def test_unrelated_pairs_loop_does_not_suppress(self):
        t = tree(self.root, "", cfg_items="loot = { { name = 'bandage', chance = 1 } }\n")
        self._items("bandage = { name = 'bandage', label = 'B', useable = true },\n")
        write(self.root, 'resources/[fh]/fh_a/s.lua',
              "exports('ok', function() end)\nfor n in pairs({ tonic = true }) do exports['rsg-core']:CreateUseableItem(n, f) end\n"
              "for k in pairs({ bandage = true }) do print(k) end\n")
        self.assertEqual(sorted(f[1] for f in findings(t, 'useable')), ['bandage'])

    def test_field_named_name_does_not_resolve_loop_var(self):
        t = tree(self.root, "", cfg_items="loot = { { name = 'bandage', chance = 1 } }\n")
        self._items("bandage = { name = 'bandage', label = 'B', useable = true },\n")
        write(self.root, 'resources/[fh]/fh_a/s.lua',
              "exports('ok', function() end)\nlocal row = {\n  name = 'bandage',\n}\n"
              "exports['rsg-core']:CreateUseableItem(name, function() end)\n")
        self.assertEqual(sorted(f[1] for f in findings(t, 'useable')), ['bandage'])

    def test_weapon_type_dispatch_needs_listener(self):
        t = tree(self.root, "", cfg_items="loot = { { name = 'weapon_x', chance = 1 } }\n")
        self._items("weapon_x = { name = 'weapon_x', label = 'W', type = 'weapon', useable = true },\n")
        write(self.root, 'resources/[fh]/fh_a/s.lua',
              "exports('ok', function() end)\nlocal weaponEvents = { weapon = 'rsg-weapons:client:UseWeapon' }\n")
        self.assertEqual(sorted(f[1] for f in findings(t, 'useable')), ['weapon_x'])
        write(self.root, 'resources/[rsg]/rsg-weapons/fxmanifest.lua', MANIFEST % "client_scripts { 'c.lua' }")
        write(self.root, 'resources/[rsg]/rsg-weapons/c.lua', "RegisterNetEvent('rsg-weapons:client:UseWeapon', function() end)\n")
        self.assertEqual(findings(t, 'useable'), [])

    def test_crafting_inputs_are_not_grants(self):
        t = tree(self.root, "", cfg_items="")
        self._items("carrot = { name = 'carrot', label = 'C', useable = true },\n")
        write(self.root, 'resources/[fh]/fh_b/data/recipes.lua', "R = { { inputs = { { item = 'carrot', amount = 1 } } } }\n")
        self.assertEqual(findings(t, 'useable'), [])

    def test_item_and_label_table_defines_item(self):
        t = tree(self.root, "", cfg_items="")
        write(self.root, 'resources/[fh]/fh_b/data/pelts.lua', "P = { { item = 'legend_pelt', label = 'Legendary Pelt' } }\n"
              "G = { { item = 'ghost_item', amount = 1 } }\n")
        names = sorted(f[1] for f in findings(t, 'items'))
        self.assertEqual(names, ['ghost_item'])

    # ---- G3: manifest globs/literals must match ----
    def test_manifest_glob_no_match(self):
        t = tree(self.root, "", mfa='server_scripts { "s.lua" }\nclient_scripts { "c.lua" }\nfiles { "missing/*.png" }')
        self.assertEqual(sorted(f[1] for f in findings(t, 'manifest')), ['fh_a:missing/*.png'])

    # ---- G3: default clothes hashes must exist in clothing.lua ----
    def test_default_clothes_hash_valid(self):
        t = tree(self.root, "")
        write(self.root, 'resources/[rsg]/rsg-character/fxmanifest.lua', MANIFEST % '')
        write(self.root, 'resources/[rsg]/rsg-character/data/clothing.lua',
              "local clothing = { ['male'] = { ['shirts_full'] = { [1] = { [1] = { ['hash'] = 123 } } } } }\n")
        write(self.root, 'resources/[rsg]/rsg-character/shared/config.lua',
              "RSG.DefaultClothes = { male = { shirts_full = { hash = 123 } } }\n")
        self.assertEqual(findings(t, 'clothes'), [])

    def test_default_clothes_hash_invalid(self):
        t = tree(self.root, "")
        write(self.root, 'resources/[rsg]/rsg-character/fxmanifest.lua', MANIFEST % '')
        write(self.root, 'resources/[rsg]/rsg-character/data/clothing.lua',
              "local clothing = { ['male'] = { ['shirts_full'] = { [1] = { [1] = { ['hash'] = 123 } } } } }\n")
        write(self.root, 'resources/[rsg]/rsg-character/shared/config.lua',
              "RSG.DefaultClothes = { male = { shirts_full = { hash = 999 } } }\n")
        self.assertEqual(sorted(f[1] for f in findings(t, 'clothes')), ['male:shirts_full'])


if __name__ == '__main__':
    unittest.main()
