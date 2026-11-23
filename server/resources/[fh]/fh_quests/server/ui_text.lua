-- Pure: fh_quests error code -> player-facing notice text for the fh_ui jobs screen (specced in
-- spec/ui_quests_view_spec.lua). Unknown codes get a generic line, never the raw code.
local M = {}

M.TEXT = {
    fh_offer_gone = 'That job is no longer on the board.',
    fh_bounty_taken = 'Somebody is already after that one.',
    fh_busy = 'Try again in a moment.',
    fh_not_ready = 'The board is not ready yet.',
    fh_no_player = 'Your character is not loaded yet.',
    fh_bad_region = 'There is no board here.',
    fh_quest_active = 'You already have that job.',
    fh_quest_cooldown = 'You took that job recently. Try another.',
    fh_quest_done = 'You already finished that one.',
    fh_reward_pending = 'Collect your last reward first.',
    fh_accept_refused = 'The client turned you down.',
    fh_accept_failed = 'Could not take that job.',
    fh_bounty_spawn_failed = 'The target could not be found. Try again later.',
    fh_db = 'Could not save that. Try again.',
}
M.DEFAULT = 'Could not take that job.'
M.ACCEPTED = 'Job accepted.'

---accept result -> { notice, notice_kind }
function M.acceptNotice(ok, err)
    if ok == true then return { notice = M.ACCEPTED, notice_kind = 'ok' } end
    return { notice = M.TEXT[err] or M.DEFAULT, notice_kind = 'error' }
end

if GetCurrentResourceName then
    FhQuestsUiText = M
else
    return M
end
