-- fh_homestead fixed plots (spec L138-139). Coordinates are APPROXIMATE (from fh_core regions) and must be verified
-- in game: stand at the spot, read coords, adjust. One entry per plot; ids are stable (stored in fh_plots).
FhHomesteadConfig = {
    plots = {
        heartlands_01 = {
            id = 'heartlands_01',
            region = 'heartlands',
            center = vector3(-300.0, 790.0, 118.0),
            radius = 25.0,
            chest = { coords = vector3(-296.0, 790.0, 118.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
        },
    },
}
