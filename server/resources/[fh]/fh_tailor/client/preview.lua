-- fh_tailor client: preview guard (ui-tailor-catalog T4b). Pure factory, specced in spec/tailor_preview_spec.lua.
-- A mirror preview (previewLook) must NEVER stick on the ped. This guard remembers which fh_ui screen asked for the
-- preview and calls revert on every way that screen can go away:
--   onClosed  fh_ui closed the screen (close button, Esc, server close, character unload, replaced by another screen,
--             NUI page reload: fh_ui emits the local event fh:ui:closed for all of them)
--   onEnd     the screen's own "Stop preview" button
--   tick      watchdog (every ~500 ms while previewing): fh_ui stopped or crashed, the screen is no longer open, or the
--             player died (the screen is closed first so focus is released, then reverted)
--   stop      fh_tailor or fh_ui resource stop (synchronous revert)
-- Nothing here talks to the server and nothing is saved.
local M = {}

---@param d table { preview(look)->bool, revert(sync), isOpen(screen)->bool, isDead()->bool, closeScreen(screen), notice(screen, text, kind) }
function M.new(d)
    local P = { screen = nil }

    local function revert(sync)
        if not P.screen then return false end
        P.screen = nil -- cleared first: a failing revert must not be retried forever
        local ok = pcall(d.revert, sync)
        return ok
    end

    function P.active() return P.screen ~= nil end

    function P.onPreview(screen, look)
        if type(screen) ~= 'string' or type(look) ~= 'table' then return false end
        if P.screen and P.screen ~= screen then revert(false) end
        if not d.preview(look) then
            d.notice(screen, 'That look cannot be previewed.', 'err')
            return false
        end
        P.screen = screen
        return true
    end

    function P.onEnd(screen)
        if P.screen and P.screen == screen then return revert(false) end
        return false
    end

    function P.onClosed(screen)
        if P.screen and (screen == P.screen or screen == '*') then return revert(false) end
        return false
    end

    function P.tick()
        local screen = P.screen
        if not screen then return false end
        local okOpen, open = pcall(d.isOpen, screen)
        if not okOpen or not open then return revert(false) end
        if d.isDead() then
            pcall(d.closeScreen, screen)
            return revert(false)
        end
        return false
    end

    function P.stop() return revert(true) end

    return P
end

if _G.GetCurrentResourceName then
    FhTailorPreview = M
else
    return M
end
