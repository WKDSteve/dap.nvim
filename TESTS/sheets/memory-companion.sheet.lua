-- The memory view in a companion window: a second Neovim (lib.nvim.companion) shows the page dap.nvim reads from the
-- debug session. nvim-dap and the session are stand-ins (TESTS/sheets/_nvim_dap.lua: 512 readable bytes at &buffer).
-- The companion editor runs for real, headless (`terminal = false`, the form for scripts): a terminal window around
-- it is a GUI, kept for the manual line.
return {
  id = "dap.memory-companion",
  title = "The memory view in a companion window: a second Neovim shows the bytes of the debuggee",
  task = "dap.nvim/performance-pruefung-luecken-schliessen-katalog-feature-shee",
  feature = "dap.memory-companion",
  steps = {
    {
      lua = [[
        dofile("TESTS/sheets/_nvim_dap.lua")({ session = "memory", mason = { "codelldb" } })
        -- The companion reports back over the editor's RPC server. A user's editor has one; the embedded child may
        -- not, where the sandbox's $TMPDIR makes the socket path too long for a Unix socket (macOS: 104 bytes).
        if vim.v.servername == "" and vim.fn.has("unix") == 1 then
          vim.fn.serverstart("/tmp/dap-sheet-" .. vim.fn.getpid() .. ".sock")
        end
        -- Notifications go to a list, as with a notification plugin (a long one would hold a hit-enter prompt).
        _G.notes = {}
        vim.notify = function(msg)
          table.insert(_G.notes, msg)
        end
      ]],
      note = "a debug session is stopped",
    },
    { lua = 'require("wkddap").setup({ languages = { "c" } })', note = "the user's config" },
    {
      lua = 'require("wkddap.memory").open("&buffer", { companion = true, terminal = false })',
      note = "the user opens the memory of &buffer in the companion",
    },
    {
      lua = 'assert(#_G.notes == 0, "dap.nvim said: " .. table.concat(_G.notes, " | "))',
      note = "nothing went wrong on the way (else the message is the failure)",
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
