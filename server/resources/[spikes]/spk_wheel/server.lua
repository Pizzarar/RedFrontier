-- /spk_wheel [fix|alt|<wheelIndex>] -> handled on the client of the caller
lib.addCommand('spk_wheel', {
    help = 'Spike S3: break a wagon wheel ("fix" repairs, "alt" uses the non-draft break native, a number picks the wheel index)',
    params = { { name = 'arg', type = 'string', optional = true } },
}, function(source, args)
    TriggerClientEvent('spk_wheel:run', source, args.arg)
end)
