-- /journal opens the fh_ui journal screen (plan ui-wiring W3). The server answers with fh:ui:open (server/ui.lua);
-- the fh_ui client adapter fills it from the last fh:quests:sync. No keybind: no client keybind pattern exists here yet.
RegisterCommand('journal', function() TriggerServerEvent('fh:quests:ui_journal_open') end, false)
