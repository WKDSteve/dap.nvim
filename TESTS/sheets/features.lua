-- TESTS/sheets/features.lua -- the functionalities of dap.nvim (testing.nvim docs/SHEETS.md, "Feature sheets and the
-- catalog"). Read as data. Every functionality that starts a process is here; `perf` says why one is not measured by a
-- sheet of its own (testing.nvim docs/PERF.md).
return {
  {
    id = "dap.rust-pretty-printers",
    title = "A Rust launch configuration feeds LLDB the pretty-printers of the project's toolchain (rustc --print sysroot)",
    surface = { "config:languages", "lua:wkddap.setup" },
    docs = "docs/FEATURES/LANGUAGES.md",
  },
  {
    id = "dap.zig-build-first",
    title = "The Zig configuration 'Launch (build first)' runs zig build, then asks for the executable",
    surface = { "config:languages", "lua:wkddap.setup" },
    docs = "docs/FEATURES/LANGUAGES.md",
  },
  {
    id = "dap.attach-process-picker",
    title = "The JS/TS 'Attach' configuration lists the running processes in a picker and attaches to the chosen pid",
    surface = { "config:languages", "lua:wkddap.utils.validation.pick_process" },
    docs = "docs/FEATURES/LANGUAGES.md",
  },
  {
    id = "dap.memory-companion",
    title = "The memory view in a companion window: a second Neovim shows the bytes of the debuggee",
    surface = { "command:Dap memory-window", "lua:wkddap.memory.open" },
    docs = "docs/FEATURES/MEMORY.md",
  },
  {
    id = "dap.debug-session",
    title = "A debug session starts the language's debug adapter (codelldb, debugpy, delve, js-debug, gdb, ...)",
    surface = { "keymap:<leader>dc", "command:Dap continue" },
    docs = "docs/FEATURES/CONTROLS.md",
    perf = "manual:nvim-dap starts the adapter, not dap.nvim; needs nvim-dap, a real adapter and a program to debug, none of them on CI",
  },
  {
    id = "dap.run-in-terminal",
    title = "A debuggee the adapter asks to run in a terminal (runInTerminal) runs in a terminal.nvim window",
    surface = { "config:terminal.enable" },
    docs = "docs/integrations.md",
    perf = "manual:the start belongs to terminal.nvim and needs a real adapter that sends runInTerminal",
  },
  {
    id = "dap.lua-osv-server",
    title = "Debugging Neovim Lua: launch_server() starts one-small-step-for-vimkind's server in the debuggee",
    surface = { "lua:wkddap.languages.lua.launch_server" },
    docs = "docs/FEATURES/LANGUAGES.md",
    perf = "manual:osv starts its own headless Neovim; osv and nvim-dap are not dependencies of the suite",
  },
}
