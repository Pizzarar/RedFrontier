lib.addCommand('spk_wear', {
    help = 'Spike S5: "get" prints weapon wear values, "set <0..1>" sets degradation',
    params = {
        { name = 'action', type = 'string' },
        { name = 'value', type = 'number', optional = true },
    },
}, function(source, args)
    TriggerClientEvent('spk_wear:run', source, args.action, args.value)
end)
