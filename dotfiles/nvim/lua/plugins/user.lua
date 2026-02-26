-- if true then return {} end -- WARN: REMOVE THIS LINE TO ACTIVATE THIS FILE

-- You can also add or configure plugins by creating files in this `plugins/` folder
-- PLEASE REMOVE THE EXAMPLES YOU HAVE NO INTEREST IN BEFORE ENABLING THIS FILE
-- Here are some examples:

---@type LazySpec
return {

  -- Configure toggleterm for lazygit integration
  {
    "akinsho/toggleterm.nvim",
    optional = true,
    opts = function(_, opts)
      local astro = require "astrocore"
      -- Override on_create to set EDITOR for nested nvim usage
      local prev_on_create = opts.on_create
      opts.on_create = function(t)
        if prev_on_create then prev_on_create(t) end
        -- If this is running inside nvim (NVIM env var exists), set up nested editing
        if vim.env.NVIM then
          -- Use the current nvim's listen address for nested editing
          vim.fn.jobsend(t.job_id, "export EDITOR='nvim --server " .. vim.v.servername .. " --remote-wait'\n")
          vim.fn.jobsend(t.job_id, "export GIT_EDITOR='nvim --server " .. vim.v.servername .. " --remote-wait'\n")
        end
      end
      -- Remove borders from floating terminals
      opts.float_opts = { border = "none" }
      return opts
    end,
  },

  -- == Examples of Adding Plugins ==

  "andweeb/presence.nvim",
  {
    "ray-x/lsp_signature.nvim",
    event = "BufRead",
    config = function() require("lsp_signature").setup() end,
  },

  -- Make completion popup borderless
  {
    "saghen/blink.cmp",
    opts = {
      completion = {
        menu = { border = "none" },
        documentation = { window = { border = "none" } },
      },
      signature = { window = { border = "none" } },
    },
  },

  -- == Examples of Overriding Plugins ==

  -- customize dashboard options
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        layout = {
          cycle = true,
          preset = function() return vim.o.columns >= 120 and "default" or "vertical" end,
        },
        layouts = {
          default = {
            layout = {
              box = "horizontal",
              width = 0.999,
              min_width = 120,
              height = 0.999,
              {
                box = "vertical",
                border = "none",
                title = "{title} {live} {flags}",
                { win = "input", height = 1, border = "none" },
                { win = "list", border = "none" },
              },
              { win = "preview", title = "{preview}", border = "none", width = 0.5 },
            },
          },
          vertical = {
            layout = {
              backdrop = false,
              width = 0.999,
              min_width = 80,
              height = 0.999,
              min_height = 30,
              box = "vertical",
              border = "none",
              title = "{title} {live} {flags}",
              title_pos = "center",
              { win = "input", height = 1, border = "none" },
              { win = "list", border = "none" },
              { win = "preview", title = "{preview}", height = 0.5, border = "none" },
            },
          },
        },
        win = {
          input = {
            keys = {
              ["<Esc>"] = { "close", mode = { "n", "i" } },
              ["<c-e><c-h>"] = { "toggle_hidden", mode = { "i", "n" } },
              ["<c-r>#"] = { "insert_alt", mode = "i" },
              ["<c-r>%"] = { "insert_filename", mode = "i" },
              ["<c-w>H"] = "layout_left",
              ["<c-w>J"] = "layout_bottom",
              ["<c-w>K"] = "layout_top",
              ["<c-w>L"] = "layout_right",
              ["?"] = "toggle_help_input",
            },
          },
        },
      },

      dashboard = {
        preset = {
          header = false,
          -- header = table.concat({
          --   " █████  ███████ ████████ ██████   ██████ ",
          --   "██   ██ ██         ██    ██   ██ ██    ██",
          --   "███████ ███████    ██    ██████  ██    ██",
          --   "██   ██      ██    ██    ██   ██ ██    ██",
          --   "██   ██ ███████    ██    ██   ██  ██████ ",
          --   "",
          --   "███    ██ ██    ██ ██ ███    ███",
          --   "████   ██ ██    ██ ██ ████  ████",
          --   "██ ██  ██ ██    ██ ██ ██ ████ ██",
          --   "██  ██ ██  ██  ██  ██ ██  ██  ██",
          --   "██   ████   ████   ██ ██      ██",
          -- }, "\n"),
        },
      },
    },
  },

  -- You can disable default plugins as follows:
  { "max397574/better-escape.nvim", enabled = false },

  -- You can also easily customize additional setup of plugins that is outside of the plugin's setup call
  {
    "L3MON4D3/LuaSnip",
    config = function(plugin, opts)
      require "astronvim.plugins.configs.luasnip"(plugin, opts) -- include the default astronvim config that calls the setup call
      -- add more custom luasnip configuration such as filetype extend or custom snippets
      local luasnip = require "luasnip"
      luasnip.filetype_extend("javascript", { "javascriptreact" })
    end,
  },

  {
    "windwp/nvim-autopairs",
    config = function(plugin, opts)
      require "astronvim.plugins.configs.nvim-autopairs"(plugin, opts) -- include the default astronvim config that calls the setup call
      -- add more custom autopairs configuration such as custom rules
      local npairs = require "nvim-autopairs"
      local Rule = require "nvim-autopairs.rule"
      local cond = require "nvim-autopairs.conds"
      npairs.add_rules(
        {
          Rule("$", "$", { "tex", "latex" })
            -- don't add a pair if the next character is %
            :with_pair(cond.not_after_regex "%%")
            -- don't add a pair if  the previous character is xxx
            :with_pair(
              cond.not_before_regex("xxx", 3)
            )
            -- don't move right when repeat character
            :with_move(cond.none())
            -- don't delete if the next character is xx
            :with_del(cond.not_after_regex "xx")
            -- disable adding a newline when you press <cr>
            :with_cr(cond.none()),
        },
        -- disable for .vim files, but it work for another filetypes
        Rule("a", "a", "-vim")
      )
    end,
  },
}
