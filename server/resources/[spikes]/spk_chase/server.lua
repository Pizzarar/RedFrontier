-- spk_chase server: only the command. Spawn is CLIENT-SIDE for this probe (the caller's client creates
-- riders + horses as networked entities and runs the AI tasks), because server-side CreatePed is
-- likely not available on RedM (see spk_camp README) and the chase AI tasks are client natives anyway.
lib.addCommand('spk_chase', {
    help = 'spk_chase [clear]: spawn 3 mounted riders behind your wagon and log pursuit for 60s',
    params = { { name = 'action', type = 'string', optional = true } },
}, function(src, args)
    if src == 0 then return print('[spk_chase] run this in-game, while driving a wagon') end
    if args.action == 'clear' then
        return TriggerClientEvent('spk_chase:clear', src)
    end
    TriggerClientEvent('spk_chase:run', src)
end)
