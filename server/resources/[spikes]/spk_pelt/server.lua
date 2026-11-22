lib.addCommand('spk_pelt', {
    help = 'Spike S4: spawn 2 deer ~20m ahead and log damage bone / quality on death and skinning',
}, function(source)
    TriggerClientEvent('spk_pelt:run', source)
end)
