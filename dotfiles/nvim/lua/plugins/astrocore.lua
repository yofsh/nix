-- AstroCore provides a central place to modify mappings, vim options, autocommands, and more!
-- Configuration documentation can be found with `:h astrocore`
-- NOTE: We highly recommend setting up the Lua Language Server (`:LspInstall lua_ls`)
--       as this provides autocomplete and documentation while editing

-- Helper functions for terminal toggles
local function toggle_float_term()
  local Terminal = require("toggleterm.terminal").Terminal
  if not _G.float_term then
    _G.float_term = Terminal:new {
      hidden = true,
      direction = "float",
      float_opts = {
        border = "none",
      },
    }
  end
  _G.float_term:toggle()
end

local function toggle_claude_term()
  local Terminal = require("toggleterm.terminal").Terminal
  if not _G.claude_term then
    _G.claude_term = Terminal:new {
      cmd = "cd ~/.config/nvim && claude --dangerously-skip-permissions --add-dir ~/dev/vim",
      hidden = true,
      direction = "float",
      float_opts = {
        border = "none",
      },
    }
  end
  _G.claude_term:toggle()
end

---@type LazySpec
return {
  "AstroNvim/astrocore",
  ---@type AstroCoreOpts
  opts = {
    -- Configure core features of AstroNvim
    features = {
      large_buf = { size = 1024 * 256, lines = 10000 }, -- set global limits for large files for disabling features like treesitter
      autopairs = true, -- enable autopairs at start
      cmp = true, -- enable completion at start
      diagnostics = { virtual_text = true, virtual_lines = false }, -- diagnostic settings on startup
      highlighturl = true, -- highlight URLs at start
      notifications = true, -- enable notifications at start
    },
    -- Diagnostics configuration (for vim.diagnostics.config({...})) when diagnostics are on
    diagnostics = {
      virtual_text = true,
      underline = true,
    },
    -- passed to `vim.filetype.add`
    filetypes = {
      -- see `:h vim.filetype.add` for usage
      extension = {
        foo = "fooscript",
      },
      filename = {
        [".foorc"] = "fooscript",
      },
      pattern = {
        [".*/etc/foo/.*"] = "fooscript",
      },
    },
    -- vim options can be configured here
    options = {
      opt = { -- vim.opt.<key>
        relativenumber = false, -- sets vim.opt.relativenumber
        number = false, -- sets vim.opt.number
        spell = false, -- sets vim.opt.spell
        signcolumn = "yes", -- sets vim.opt.signcolumn to yes
        wrap = false, -- sets vim.opt.wrap
      },
      g = { -- vim.g.<key>
        -- configure global vim variables (vim.g)
        -- NOTE: `mapleader` and `maplocalleader` must be set in the AstroNvim opts or before `lazy.setup`
        -- This can be found in the `lua/lazy_setup.lua` file
      },
    },
    -- Mappings can be configured through AstroCore as well.
    -- NOTE: keycodes follow the casing in the vimdocs. For example, `<Leader>` must be capitalized
    mappings = {
      -- first key is the mode
      n = {
        -- second key is the lefthand side of the map

        -- find files with <Space><Space>
        ["<Leader><Leader>"] = { function() Snacks.picker.files() end, desc = "Find files" },

        -- find files in dotfiles and nix directories
        ["<Leader>fd"] = {
          function()
            Snacks.picker.files {
              dirs = { vim.fn.expand "~/nix" },
            }
          end,
          desc = "Find config",
        },

        -- execute row under cursor in ZSH
        ["<Leader>E"] = { "yyp:.!zsh<CR>", desc = "Misc execute row under curson in ZSH" },

        -- Floating terminal
        ["<M-`>"] = { toggle_float_term, desc = "Toggle floating terminal" },

        -- navigate buffer tabs
        ["]b"] = { function() require("astrocore.buffer").nav(vim.v.count1) end, desc = "Next buffer" },
        ["[b"] = { function() require("astrocore.buffer").nav(-vim.v.count1) end, desc = "Previous buffer" },

        -- mappings seen under group name "Buffer"
        ["<Leader>bd"] = {
          function()
            require("astroui.status.heirline").buffer_picker(
              function(bufnr) require("astrocore.buffer").close(bufnr) end
            )
          end,
          desc = "Close buffer from tabline",
        },

        -- tables with just a `desc` key will be registered with which-key if it's installed
        -- this is useful for naming menus
        -- ["<Leader>b"] = { desc = "Buffers" },

        -- setting a mapping to false will disable it
        -- ["<C-S>"] = false,

        -- Reload Neovim configuration
        ["<C-M-,>"] = { "<cmd>AstroReload<CR>", desc = "Reload configuration" },

        -- Fullscreen lazygit
        ["<Leader>gg"] = {
          function()
            local Terminal = require("toggleterm.terminal").Terminal
            if not _G.lazygit_term then
              _G.lazygit_term = Terminal:new {
                cmd = "lazygit",
                hidden = true,
                direction = "float",
                float_opts = {
                  border = "none",
                  width = function() return vim.o.columns end,
                  height = function() return vim.o.lines end,
                },
              }
            end
            _G.lazygit_term:toggle()
          end,
          desc = "ToggleTerm lazygit (fullscreen)",
        },

        -- Open toggleterm with claude command
        ["<C-,>"] = { toggle_claude_term, desc = "Toggle Nvim Claude helper terminal" },
      },
      i = {
        ["<M-`>"] = { toggle_float_term, desc = "Toggle floating terminal" },
        ["<C-,>"] = { toggle_claude_term, desc = "Toggle Nvim Claude helper terminal" },
      },
      t = {
        ["<M-`>"] = { toggle_float_term, desc = "Toggle floating terminal" },
        ["<C-,>"] = { toggle_claude_term, desc = "Toggle Nvim Claude helper terminal" },
      },
    },
  },
}
