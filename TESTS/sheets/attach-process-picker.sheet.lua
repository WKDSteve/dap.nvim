-- The JS/TS "Attach" configuration: its processId is dap.nvim's process picker, which lists the running processes
-- (`ps -eo pid,comm`, on Windows `tasklist`) in a picker and gives nvim-dap the pid of the chosen line. nvim-dap is a
-- stand-in (TESTS/sheets/_nvim_dap.lua) that resolves processId in a coroutine as nvim-dap does: a function returning
-- a thread is resumed and its answer awaited. The listing runs for real.
return {
  id = "dap.attach-process-picker",
  title = "The JS/TS 'Attach' configuration lists the running processes in a picker and attaches to the chosen pid",
  task = "dap.nvim/performance-pruefung-luecken-schliessen-katalog-feature-shee",
  feature = "dap.attach-process-picker",
  steps = {
    {
      lua = 'dofile("TESTS/sheets/_nvim_dap.lua")({ mason = { "js-debug-adapter" } })',
      note = "js-debug-adapter is installed by Mason",
    },
    {
      lua = 'require("wkddap").setup({ languages = { "javascript" } })',
      note = "the user's config",
    },
    {
      lua = [[
        local cfg
        for _, c in ipairs(package.loaded.dap.configurations.javascript) do
          if c.name == "Attach" then cfg = c end
        end
        _G.co = coroutine.create(function()
          local v = cfg.processId()
          if type(v) == "thread" then
            assert(coroutine.resume(v))
            v = coroutine.yield()
          end
          _G.pid, _G.done = v, true
        end)
        assert(coroutine.resume(_G.co))
      ]],
      note = "the user starts 'Attach'",
    },
    {
      wait = "vim.api.nvim_win_get_config(0).relative ~= ''",
      timeout = 15000,
      note = "the picker of the running processes opens",
    },
    {
      expect = "vim.api.nvim_get_current_line():match('^%s*%d+') ~= nil",
      note = "each line starts with a pid",
    },
    { keys = "<CR>", note = "the user takes the first process" },
    { wait = "_G.done == true", note = "the configuration resolves" },
    -- The first line may be pid 0 (Windows' "System Idle Process"): a number is what counts.
    { expect = "type(_G.pid) == 'number'", note = "nvim-dap gets the pid of the line" },
  },
  judge = { "the picker reads well: pid and program name per line" },
  manual = {
    "with nvim-dap and js-debug: attaching to a `node --inspect` process stops at a breakpoint",
  },
}
