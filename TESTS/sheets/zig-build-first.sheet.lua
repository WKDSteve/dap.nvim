-- The Zig configuration "Launch (build first)": when a session starts, dap.nvim runs `zig build` in the project, then
-- asks for the executable (prefilled with zig-out/bin/). nvim-dap is a stand-in (TESTS/sheets/_nvim_dap.lua) that
-- resolves `program` in a coroutine as nvim-dap does. `zig` runs for real when it is installed; without it the build
-- cannot start, dap.nvim says so and asks all the same.
return {
  id = "dap.zig-build-first",
  title = "The Zig configuration 'Launch (build first)' runs zig build, then asks for the executable",
  task = "dap.nvim/performance-pruefung-luecken-schliessen-katalog-feature-shee",
  feature = "dap.zig-build-first",
  steps = {
    {
      lua = [[
        dofile("TESTS/sheets/_nvim_dap.lua")({ mason = { "codelldb" } })
        local dir = vim.fn.tempname()
        vim.fn.mkdir(dir, "p")
        vim.fn.writefile({ "pub fn main() void {}" }, dir .. "/main.zig")
        vim.cmd.cd(dir)
        vim.cmd.edit("main.zig")
        -- Notifications go to a list, as with a notification plugin: the warning of a failed build is longer than
        -- the command line and would hold the editor at a hit-enter prompt.
        _G.notes = {}
        vim.notify = function(msg)
          table.insert(_G.notes, msg)
        end
      ]],
      note = "a Zig file is open, codelldb is installed by Mason",
    },
    { lua = 'require("wkddap").setup({ languages = { "zig" } })', note = "the user's config" },
    {
      lua = [[
        local cfg
        for _, c in ipairs(package.loaded.dap.configurations.zig) do
          if c.name == "Launch (build first)" then cfg = c end
        end
        _G.co = coroutine.create(function() _G.program = cfg.program() end)
        assert(coroutine.resume(_G.co))
      ]],
      note = "the user starts 'Launch (build first)'",
    },
    {
      wait = "vim.api.nvim_win_get_config(0).relative ~= ''",
      timeout = 30000,
      note = "after the build the prompt for the executable opens",
    },
    {
      expect = "vim.api.nvim_get_current_line():find('zig-out', 1, true) ~= nil",
      note = "it is prefilled with zig-out/bin/",
    },
    { input = "app<CR>", note = "the user names the executable" },
    { wait = "_G.program ~= nil", note = "the configuration resolves" },
    {
      expect = "_G.program:find('zig%-out/bin/app$') ~= nil",
      note = "the program is the named executable below zig-out/bin",
    },
    {
      expect = [[
        vim.fn.executable("zig") == 1
          or table.concat(_G.notes, "\n"):find("zig build could not start", 1, true) ~= nil
      ]],
      note = "without zig the user is told that the build could not start",
    },
  },
  judge = { "the prompt opens only once the build is done (or failed), not before" },
  manual = {
    "with zig installed and a build.zig: a failing build shows 'zig build exited ...' and still asks",
  },
}
