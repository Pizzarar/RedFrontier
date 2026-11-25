-- fh_tailor/client/preview.lua: the mirror-preview revert guard (ui-tailor-catalog T4b). A preview must never stick.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case, eq = T.it, T.eq
local G = dofile(here .. '../server/resources/[fh]/fh_tailor/client/preview.lua')

local function rig(opts)
    opts = opts or {}
    local r = { applied = {}, reverts = {}, closed = {}, notes = {}, open = { tailor = true, wardrobe = true }, dead = false,
        previewOk = true, uiError = false }
    r.g = G.new({
        preview = function(look) r.applied[#r.applied + 1] = look return r.previewOk end,
        revert = function(sync) r.reverts[#r.reverts + 1] = sync == true and 'sync' or 'async' if opts.revertErrors then error('boom') end end,
        isOpen = function(screen) if r.uiError then error('fh_ui stopped') end return r.open[screen] == true end,
        isDead = function() return r.dead end,
        closeScreen = function(screen) r.closed[#r.closed + 1] = screen r.open[screen] = nil end,
        notice = function(screen, text, kind) r.notes[#r.notes + 1] = { screen, text, kind } end,
    })
    return r
end
local look = { outfit = 'o1', items = {} }

case('preview applies and marks active; refusal shows a notice and stays inactive', function()
    local r = rig(); eq(true, r.g.onPreview('tailor', look)); eq(true, r.g.active())
    r = rig(); r.previewOk = false
    eq(false, r.g.onPreview('tailor', look)); eq(false, r.g.active()); eq('err', r.notes[1][3]); eq(0, #r.reverts)
    r = rig(); eq(false, r.g.onPreview(nil, look)); eq(false, r.g.onPreview('tailor', 'x')); eq(0, #r.applied)
end)
case('close button / Esc / server close / unload / NUI reload: fh_ui closed -> revert once', function()
    local r = rig(); r.g.onPreview('tailor', look)
    eq(true, r.g.onClosed('tailor')); eq(1, #r.reverts); eq(false, r.g.active())
    eq(false, r.g.onClosed('tailor')); eq(1, #r.reverts) -- idempotent
end)
case('closing an unrelated screen keeps the preview; wildcard (character unload) reverts', function()
    local r = rig(); r.g.onPreview('tailor', look)
    eq(false, r.g.onClosed('heat')); eq(false, r.g.onClosed('wardrobe')); eq(0, #r.reverts); eq(true, r.g.active())
    eq(true, r.g.onClosed('*')); eq(1, #r.reverts)
end)
case('stop preview button reverts only for its own screen', function()
    local r = rig(); r.g.onPreview('wardrobe', look)
    eq(false, r.g.onEnd('tailor')); eq(0, #r.reverts)
    eq(true, r.g.onEnd('wardrobe')); eq(1, #r.reverts)
end)
case('screen replaced: previewing from the other screen reverts the first before applying', function()
    local r = rig(); r.g.onPreview('tailor', look); r.g.onPreview('wardrobe', look)
    eq(1, #r.reverts); eq(2, #r.applied); eq(true, r.g.active()); eq(true, r.g.onClosed('wardrobe'))
    eq(2, #r.reverts)
end)
case('watchdog: screen no longer open, or fh_ui crashed/stopped -> revert', function()
    local r = rig(); r.g.onPreview('tailor', look); eq(false, r.g.tick()); eq(0, #r.reverts)
    r.open.tailor = nil; eq(true, r.g.tick()); eq(1, #r.reverts)
    r = rig(); r.g.onPreview('tailor', look); r.uiError = true
    eq(true, r.g.tick()); eq(1, #r.reverts); eq(false, r.g.active())
    eq(false, rig().g.tick()) -- nothing previewed: nothing to do
end)
case('watchdog: player died -> close the screen (frees focus) and revert', function()
    local r = rig(); r.g.onPreview('wardrobe', look); r.dead = true
    eq(true, r.g.tick()); eq('wardrobe', r.closed[1]); eq(1, #r.reverts)
end)
case('resource stop (fh_tailor or fh_ui): synchronous revert, only if previewing', function()
    local r = rig(); eq(false, r.g.stop()); eq(0, #r.reverts)
    r.g.onPreview('tailor', look); eq(true, r.g.stop()); eq('sync', r.reverts[1]); eq(false, r.g.active())
end)
case('a revert that errors still clears the preview (no retry loop)', function()
    local r = rig({ revertErrors = true }); r.g.onPreview('tailor', look)
    eq(false, r.g.onClosed('tailor')); eq(false, r.g.active()); eq(1, #r.reverts)
end)

T.finish()
