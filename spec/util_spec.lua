local util = require('util')

describe('fh_core shared/util', function()
  describe('clamp', function()
    it('returns the value inside range', function() assert.are.equal(5, util.clamp(5, 0, 10)) end)
    it('clamps below and above', function()
      assert.are.equal(0, util.clamp(-3, 0, 10))
      assert.are.equal(10, util.clamp(99, 0, 10))
    end)
    it('tolerates swapped bounds', function() assert.are.equal(4, util.clamp(4, 10, 0)) end)
  end)

  describe('deepCopy', function()
    it('copies nested tables without aliasing', function()
      local a = { x = { y = 1 }, list = { 1, 2 } }
      local b = util.deepCopy(a)
      assert.are.same(a, b)
      assert.are_not.equal(a.x, b.x)
      b.x.y = 2
      assert.are.equal(1, a.x.y)
    end)
    it('handles cycles', function()
      local a = {}; a.self = a
      local b = util.deepCopy(a)
      assert.are.equal(b, b.self)
    end)
  end)
end)
