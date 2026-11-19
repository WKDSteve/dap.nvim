-- The Rust configuration of a user who has codelldb from Mason: dap.nvim's setup looks up the toolchain's sysroot in
-- the background (`rustc --print sysroot`), and a session started after `:cd` into another project, where that lookup
-- has not run yet, asks rustc on the spot. nvim-dap is a stand-in (TESTS/sheets/_nvim_dap.lua); rustc runs for real
-- when it is installed and is skipped by dap.nvim when it is not (then the session starts without pretty-printers).
return {
  id = "dap.rust-pretty-printers",
  title = "A Rust launch configuration feeds LLDB the pretty-printers of the project's toolchain (rustc --print sysroot)",
  task = "dap.nvim/performance-pruefung-luecken-schliessen-katalog-feature-shee",
  feature = "dap.rust-pretty-printers",
  steps = {
    {
      lua = [[
        dofile("TESTS/sheets/_nvim_dap.lua")({ mason = { "codelldb" } })
        _G.project_a = vim.fn.tempname()
        vim.fn.mkdir(_G.project_a .. "/src", "p")
        vim.fn.writefile({ "[package]", 'name = "a"', 'version = "0.1.0"' }, _G.project_a .. "/Cargo.toml")
        vim.fn.writefile({ "fn main() {}" }, _G.project_a .. "/src/main.rs")
        vim.cmd.cd(_G.project_a)
        vim.cmd.edit("src/main.rs")
      ]],
      note = "a Rust project is open, codelldb is installed by Mason",
    },
    { lua = 'require("wkddap").setup({ languages = { "rust" } })', note = "the user's config" },
    {
      expect = "package.loaded.dap.adapters.codelldb.executable.command:find('codelldb', 1, true) ~= nil",
      note = "codelldb is the adapter",
    },
    {
      expect = "package.loaded.dap.configurations.rust[1].name == 'Launch'",
      note = "the Rust configuration is there",
    },
    {
      lua = [[
        local b = vim.fn.tempname()
        vim.fn.mkdir(b .. "/src", "p")
        vim.fn.writefile({ "[package]", 'name = "b"', 'version = "0.1.0"' }, b .. "/Cargo.toml")
        vim.fn.writefile({ "fn main() {}" }, b .. "/src/main.rs")
        vim.cmd.cd(b)
        vim.cmd.edit("src/main.rs")
      ]],
      note = "the user moves on to another Rust project",
    },
    {
      lua = "_G.init_commands = package.loaded.dap.configurations.rust[1].initCommands()",
      note = "a session starts there: nvim-dap asks the configuration for LLDB's initCommands",
    },
    {
      expect = [[
        type(_G.init_commands) == "table"
          and (vim.fn.executable("rustc") == 0 or #_G.init_commands == 0
            or _G.init_commands[1]:find("lldb_lookup.py", 1, true) ~= nil)
      ]],
      note = "with rustc: the pretty-printer script of the toolchain is imported; without: no commands",
    },
  },
  judge = {
    "the session in the second project shows Rust values (Vec, String) with their pretty-printers",
  },
  manual = {
    "with nvim-dap and codelldb: a Vec<String> in the variables pane reads as its elements",
  },
}
