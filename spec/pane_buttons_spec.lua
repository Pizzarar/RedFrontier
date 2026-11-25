-- core-10 I3: fh_inventory pane-button registry (client/panebuttons.lua, pure Lua).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
dofile(here .. '../server/resources/[fh]/fh_inventory/client/panebuttons.lua')
local B = FhPaneButtons

T.describe('FhPaneButtons', function()
  T.it('registers and lists a button, pane defaults to backpack', function()
    B.reset()
    T.eq(true, B.register({ id = 'a', label = 'A' }))
    T.eq('backpack', B.list()[1].pane)
    T.eq(true, B.register({ id = 'b', label = 'B', pane = 'saddlebag' }))
    T.eq(2, #B.list())
  end)
  T.it('rejects bad input', function()
    B.reset()
    local cases = {
      { nil, 'bad_args' }, { 5, 'bad_args' }, { { label = 'x' }, 'bad_id' }, { { id = 3, label = 'x' }, 'bad_id' },
      { { id = '', label = 'x' }, 'bad_id' }, { { id = 'a' }, 'bad_label' }, { { id = 'a', label = 7 }, 'bad_label' },
      { { id = 'a', label = 'x', pane = 'horse' }, 'bad_pane' }, { { id = 'a', label = 'x', pane = 1 }, 'bad_pane' },
    }
    for _, c in ipairs(cases) do
      local ok, why = B.register(c[1])
      T.eq(false, ok); T.eq(c[2], why)
    end
    T.eq(0, #B.list())
  end)
  T.it('re-registering an id replaces it in place', function()
    B.reset()
    B.register({ id = 'a', label = 'A' }); B.register({ id = 'b', label = 'B' })
    B.register({ id = 'a', label = 'A2', pane = 'saddlebag' })
    local l = B.list()
    T.eq(2, #l); T.eq('a', l[1].id); T.eq('A2', l[1].label); T.eq('saddlebag', l[1].pane)
  end)
  T.it('payload is { id, pane } for known ids only', function()
    B.reset()
    B.register({ id = 'a', label = 'A', pane = 'saddlebag' })
    local p = B.payload('a')
    T.eq('a', p.id); T.eq('saddlebag', p.pane); T.eq(nil, B.payload('zzz')); T.eq(nil, B.payload(nil))
  end)
end)
T.finish()
