---@mod kitty-scrollback.launch

local ksb_win
local ksb_hl
local ksb_keymaps
local ksb_kitty_cmds
local ksb_util
local ksb_autocmds

local M = {}

---@class KsbPrivate
---@field orig_columns number
---@field bufid number?
---@field paste_bufid number?
---@field kitty_loading_winid number?
---@field kitty_colors table
---@field paste_winid number?
---@field legend_winid number?
---@field legend_bufid number?
local p = {}

local opts = {}

---@class KsbOpts
---@field callbacks KsbCallbacks
local default_opts = {
  keymaps_enabled = true,
  restore_options = false,
  status_window = {
    enabled = true,
    style_simple = false,
    autoclose = false,
    show_timer = false,
  },
  ---@class KsbKittyGetText see `kitty @ get-text --help`
  ---@field ansi boolean If true, the text will include the ANSI formatting escape codes for colors, bold, italic, etc.
  ---@field clear_selection boolean If true, clear the selection in the matched window, if any.
  ---@field extent string | 'screen' | 'selection' | 'first_cmd_output_on_screen' | 'last_cmd_output' | 'last_visited_cmd_output' | 'last_non_empty_output'     What text to get. The default of screen means all text currently on the screen. all means all the screen+scrollback and selection means the currently selected text. first_cmd_output_on_screen means the output of the first command that was run in the window on screen. last_cmd_output means the output of the last command that was run in the window. last_visited_cmd_output means the first command output below the last scrolled position via scroll_to_prompt. last_non_empty_output is the output from the last command run in the window that had some non empty output. The last four require shell_integration to be enabled. Choices: screen, all, first_cmd_output_on_screen, last_cmd_output, last_non_empty_output, last_visited_cmd_output, selection
  kitty_get_text = {
    ansi = true,
    extent = 'all',
    clear_selection = true,
  },
  highlight_overrides = {
    -- KittyScrollbackNvimNormal = '#968c81',
    -- KittyScrollbackNvimHeart = '#ff6961',
    -- KittyScrollbackNvimSpinner = '#d3869b',
    -- KittyScrollbackNvimReady = '#8faa80',
    -- KittyScrollbackNvimKitty = '#754b33',
    -- KittyScrollbackNvimVim = '#188b25',
    -- TODO: add paste window highlight overrides
  },
  ---@class KsbCallbacks
  ---@field after_setup function
  ---@field after_launch function
  ---@field after_ready function
  callbacks = {
    -- after_setup = function(kitty_data, opts) end,
    -- after_launch = function(kitty_data, opts) end,
    -- after_ready = function(kitty_data, opts) end,
  },
}


---@class KsbModules
---@field util table
local m = {}


local function restore_orig_options()
  for option, value in pairs(p.orig_options) do
    vim.o[option] = value
  end
end


local function set_options()
  p.orig_options = {
    virtualedit = vim.o.virtualedit,
    termguicolors = vim.o.termguicolors,
    laststatus = vim.o.laststatus,
    scrolloff = vim.o.scrolloff,
    cmdheight = vim.o.cmdheight,
    ruler = vim.o.ruler,
    number = vim.o.number,
    relativenumber = vim.o.relativenumber,
    scrollback = vim.o.scrollback,
    list = vim.o.list,
    showtabline = vim.o.showtabline,
    showmode = vim.o.showmode,
    ignorecase = vim.o.ignorecase,
    smartcase = vim.o.smartcase,
    cursorline = vim.o.cursorline,
    cursorcolumn = vim.o.cursorcolumn,
    fillchars = vim.o.fillchars,
    lazyredraw = vim.o.lazyredraw,
    hidden = vim.o.hidden,
    modifiable = vim.o.modifiable,
    wrap = vim.o.wrap,
  }

  -- required opts
  vim.o.virtualedit = 'all' -- all or onemore for correct position
  vim.o.termguicolors = true

  -- preferred optional opts
  vim.o.laststatus = 0
  vim.o.scrolloff = 0
  vim.o.cmdheight = 0
  vim.o.ruler = false
  vim.o.number = false
  vim.o.relativenumber = false
  vim.o.scrollback = 100000
  vim.o.list = false
  vim.o.showtabline = 0
  vim.o.showmode = false
  vim.o.ignorecase = true
  vim.o.smartcase = true
  vim.o.cursorline = false
  vim.o.cursorcolumn = false
  vim.opt.fillchars = {
    eob = ' ',
  }
  vim.o.lazyredraw = false -- conflicts with noice
  vim.o.hidden = true
  vim.o.modifiable = true
  vim.o.wrap = false
end


local set_cursor_position = vim.schedule_wrap(
  function(d)
    local x = d.cursor_x - 1
    local y = d.cursor_y - 1
    local scrolled_by = d.scrolled_by
    local lines = d.lines
    local last_line = vim.fn.line('$')

    local orig_virtualedit = vim.o.virtualedit
    local orig_scrollof = vim.o.scrolloff
    local orig_showtabline = vim.o.showtabline
    local orig_laststatus = vim.o.laststatus
    vim.o.scrolloff = 0
    vim.o.showtabline = 0
    vim.o.laststatus = 0
    vim.o.virtualedit = 'all'

    vim.fn.cursor(last_line, 1) -- cursor last line
    -- using normal commands instead of cursor pos due to virtualedit
    vim.cmd.normal({ lines .. 'k', bang = true }) -- cursor up
    vim.cmd.normal({ y .. 'j', bang = true }) -- cursor down
    vim.cmd.normal({ x .. 'l', bang = true }) -- cursor right
    if scrolled_by > 0 then
      -- scroll up
      vim.cmd.normal({
        vim.api.nvim_replace_termcodes(scrolled_by .. '<C-y>', true, false, true), -- TODO: invesigate if CSI control sequence to scroll is better
        bang = true
      })
    end

    vim.o.scrolloff = orig_scrollof
    vim.o.showtabline = orig_showtabline
    vim.o.laststatus = orig_laststatus
    vim.o.virtualedit = orig_virtualedit
  end
)


local function load_requires()
  -- add to runtime to allow loading modules via require
  vim.opt.runtimepath:append(p.kitty_data.ksb_dir)
  ksb_win = require('kitty-scrollback.windows')
  ksb_hl = require('kitty-scrollback.highlights')
  ksb_keymaps = require('kitty-scrollback.keymaps')
  ksb_kitty_cmds = require('kitty-scrollback.kitty_commands')
  ksb_util = require('kitty-scrollback.util')
  ksb_autocmds = require('kitty-scrollback.autocommands')
end


M.setup = function(kitty_data_str)
  p.kitty_data = vim.fn.json_decode(kitty_data_str)
  load_requires() -- must be after p.kitty_data initialized

  local user_opts = {}
  if p.kitty_data.config_file then
    user_opts = dofile(p.kitty_data.config_file).config(p.kitty_data)
  end
  opts = vim.tbl_deep_extend('force', default_opts, user_opts)

  ksb_util.setup(p, opts)
  ksb_autocmds.setup(p, opts)
  ksb_kitty_cmds.setup(p, opts)
  ksb_win.setup(p, opts)
  ksb_keymaps.setup(p, opts)
  ksb_hl.setup(p, opts)
  ksb_hl.set_highlights()
  ksb_kitty_cmds.open_kitty_loading_window() -- must be after opts and set highlights
  set_options()

  if opts.callbacks.after_setup and type(opts.callbacks.after_setup) == 'function' then
    opts.callbacks.after_setup(p.kitty_data, opts)
  end

  vim.schedule(ksb_hl.unpinkify_default_colorscheme)
end


M.launch = function()
  local kitty_data = p.kitty_data
  vim.schedule(function()
    p.bufid = vim.api.nvim_get_current_buf()

    ksb_autocmds.load_autocmds()

    local ansi = '--ansi'
    if not opts.kitty_get_text.ansi then
      ansi = ''
    end

    local clear_selection = '--clear-selection'
    if not opts.kitty_get_text.clear_selection then
      clear_selection = ''
    end

    local extent = '--extent=all'
    local extent_opt = opts.kitty_get_text.extent
    if extent_opt then
      extent = '--extent=' .. extent_opt
    end

    local add_cursor = '--add-cursor' -- always add cursor

    local get_text_opts = ansi .. ' ' .. clear_selection .. ' ' .. add_cursor .. ' ' .. extent

    -- increase the number of columns temporary so that the width is used during the
    -- terminal command kitty @ get-text. this avoids hard wrapping lines to the
    -- current window size. Note: a larger min_cols appears to impact performance
    -- do not worry about setting vim.o.columns back to original value that is taken
    -- care of when we trigger kitty to send a SIGWINCH to the nvim process
    local min_cols = 300
    if vim.o.columns < min_cols then
      vim.o.columns = min_cols
    end
    vim.schedule(function()
      vim.fn.termopen(
        [[kitty @ get-text --match="id:]] .. kitty_data.window_id .. [[" ]] .. get_text_opts .. [[ | ]] ..
        [[sed -e "s/$/\x1b[0m/g" ]] .. -- append all lines with reset to avoid unintended colors
        [[-e "s/\x1b\[\?25.\x1b\[.*;.*H\x1b\[.*//g"]], -- remove control sequence added by --add-cursor flag
        {
          stdout_buffered = true,
          on_exit = function()
            ksb_kitty_cmds.signal_winchanged_to_kitty_child_process()
            vim.fn.timer_start(
              20,
              function(t) ---@diagnostic disable-line: redundant-parameter
                local timer_info = vim.fn.timer_info(t)[1] or {}
                local ready = ksb_util.remove_process_exited()
                if ready or timer_info['repeat'] == 0 then
                  vim.fn.timer_stop(t)
                  if opts.kitty_get_text.extent == 'screen' or opts.kitty_get_text.extent == 'all' then
                    set_cursor_position(kitty_data)
                  end
                  ksb_win.show_status_window()

                  -- improve buffer name to avoid displaying complex command to user
                  local term_buf_name = vim.api.nvim_buf_get_name(p.bufid)
                  term_buf_name = term_buf_name:gsub(':kitty.*$', ':kitty-scrollback.nvim')
                  vim.api.nvim_buf_set_name(p.bufid, term_buf_name)

                  ksb_kitty_cmds.close_kitty_loading_window()
                  if opts.restore_options then
                    restore_orig_options()
                  end
                  if opts.callbacks.after_ready and type(opts.callbacks.after_ready) == 'function' then
                    vim.schedule(function()
                      opts.callbacks.after_ready(kitty_data, opts)
                    end)
                  end
                end
              end,
              {
                ['repeat'] = 200
              })
          end,
        })
    end)
    if opts.callbacks.after_launch and type(opts.callbacks.after_launch) == 'function' then
      vim.schedule(function()
        opts.callbacks.after_launch(kitty_data, opts)
      end)
    end
  end)
end


M.setup_and_launch = function(...)
  M.setup(...)
  M.launch()
end

return M