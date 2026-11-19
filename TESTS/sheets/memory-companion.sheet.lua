-- The memory view in a companion window: a second Neovim (lib.nvim.companion) shows the page dap.nvim reads from the
-- debug session. nvim-dap and the session are stand-ins (TESTS/sheets/_nvim_dap.lua: 512 readable bytes at &buffer).
-- The companion editor runs for real, headless (`terminal = false`, the form for scripts): a terminal window around
-- it is a GUI, kept for the manual line.
return {
  id = "dap.memory-companion",
  title = "The memory view in a companion window: a second Neovim shows the bytes of the debuggee",
  feature = "dap.memory-companion",
  steps = {
    {
      lua = 'dofile("TESTS/sheets/_nvim_dap.lua")({ session = "memory" })',
      note = "a debug session is stopped",
    },
    { lua = 'require("wkddap").setup({ languages = { "c" } })', note = "the user's config" },
    {
      lua = 'require("wkddap.memory").open("&buffer", { companion = true, terminal = false })',
      note = "the user opens the memory of &buffer in the companion",
    },
    {
      wait = [[
        require("wkddap.memory").state() ~= nil
          and require("wkddap.memory.companion").is_valid(require("wkddap.memory").state().view)
      ]],
      timeout = 20000,
      note = "the companion editor runs",
    },
    {
      expect = [[
        vim.tbl_contains(package.loaded.dap.session().requests, "readMemory")
          and table.concat(require("wkddap.memory").state().view.render.lines, "\n"):find("ABCDEFGH", 1, true) ~= nil
      ]],
      note = "the bytes at &buffer (A, B, C, ...) are what the companion shows",
    },
    { lua = 'require("wkddap.memory").close()', note = "the user closes the view" },
    {
      wait = "require('wkddap.memory').state() == nil",
      note = "the view is gone with its companion",
    },
  },
  judge = { "the companion shows the same page as the float, with the key legend under it" },
  manual = {
    ":Dap memory-window &buffer in a real session opens a terminal window with the page; n/p page, q closes it",
  },
}
