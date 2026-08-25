local Popup = require("nui.popup")
local Layout = require("nui.layout")
local event = require("nui.utils.autocmd").event
local actions = require("suru.actions")

local M = {}

local ns = vim.api.nvim_create_namespace("suru_todos")

local tabs = { "Important", "Unimportant", "Completed" }

local state = {
  curr_tab = 1,
  all_todos = nil,
  entries = {},
  selected = {},
  layout = nil,
  tab_popup = nil,
  list_popup = nil,
  loading = false,
}

local function setup_highlights()
  local hl = vim.api.nvim_set_hl
  hl(0, "SuruBorder", { link = "TelescopeBorder", default = true })
  hl(0, "SuruTitle", { fg = "#c0caf5", bold = true, default = true })
  hl(0, "SuruTabActive", { fg = "#1a1b26", bg = "#7aa2f7", bold = true, default = true })
  hl(0, "SuruTabInactive", { fg = "#565f89", default = true })
  hl(0, "SuruTabSep", { fg = "#3b4261", default = true })
  hl(0, "SuruTodoSelected", { bg = "#292e42", bold = true, default = true })
  hl(0, "SuruTodoIcon", { fg = "#9ece6a", default = true })
  hl(0, "SuruEmpty", { fg = "#565f89", italic = true, default = true })
  -- multi-select row background (distinct from cursorline)
  hl(0, "SuruMultiSelected", { bg = "#3d2b3d", default = true })
  hl(0, "SuruSelectedMarker", { fg = "#f7768e", bold = true, default = true })
  hl(0, "SuruMarker", { fg = "#565f89", default = true })
end

local function matches_tab(todo, tab_name)
  if tab_name == "Completed" then
    return todo.status == "done"
  end

  local wanted_type = tab_name:lower()
  return todo.type == wanted_type and todo.status ~= "done"
end

local function filter_for_current_tab()
  local tab_name = tabs[state.curr_tab]
  local entries = {}
  for i, todo in ipairs(state.all_todos or {}) do
    if matches_tab(todo, tab_name) then
      table.insert(entries, { todo = todo, orig_index = i })
    end
  end
  state.entries = entries
end

local function render_tabs()
  local bufnr = state.tab_popup.bufnr
  vim.bo[bufnr].modifiable = true

  local parts = {}
  local segments = {}
  local col = 1
  table.insert(parts, " ")

  for i, tab in ipairs(tabs) do
    local label = " " .. tab .. " "
    table.insert(parts, label)
    table.insert(segments, {
      start_col = col,
      end_col = col + #label,
      hl = (i == state.curr_tab) and "SuruTabActive" or "SuruTabInactive",
    })
    col = col + #label

    if i < #tabs then
      table.insert(parts, "  ")
      col = col + 2
    end
  end

  local line = table.concat(parts, "")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { line })
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for _, seg in ipairs(segments) do
    vim.api.nvim_buf_set_extmark(bufnr, ns, 0, seg.start_col, {
      end_col = seg.end_col,
      hl_group = seg.hl,
    })
  end

  vim.bo[bufnr].modifiable = false
end

local function set_list_lines(lines, highlight_empty)
  local bufnr = state.list_popup.bufnr
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  if highlight_empty then
    vim.api.nvim_buf_add_highlight(bufnr, ns, "SuruEmpty", 1, 0, -1)
  end
  vim.bo[bufnr].modifiable = false
end

local function render_list_placeholder()
  set_list_lines({ "", "  Loading todos..." }, true)
end

-- Each row is rendered as: " [x]  title"  or  " [ ]  title"
-- columns:  1        selection marker
--           5-6      type icon (overlaid)
--           8+       title text
local ROW_MARKER_COL = 1
local ROW_ICON_COL = 5
local ROW_TITLE_COL = 8

local function render_list()
  filter_for_current_tab()

  local bufnr = state.list_popup.bufnr

  if #state.entries == 0 then
    set_list_lines({ "", "  No todos in this list." }, true)
    return
  end

  local lines = {}
  for _, entry in ipairs(state.entries) do
    local marker = state.selected[entry.orig_index] and "[x]" or "[ ]"
    local prefix = string.rep(" ", ROW_MARKER_COL) .. marker
        .. string.rep(" ", ROW_ICON_COL - ROW_MARKER_COL - #marker)
        .. " " -- icon overlay slot
        .. string.rep(" ", ROW_TITLE_COL - ROW_ICON_COL - 2)
    table.insert(lines, prefix .. tostring(entry.todo.title))
  end

  set_list_lines(lines, false)

  for i, entry in ipairs(state.entries) do
    local row = i - 1
    local is_selected = state.selected[entry.orig_index] or false

    -- type icon
    vim.api.nvim_buf_set_extmark(bufnr, ns, row, ROW_ICON_COL, {
      end_col = ROW_ICON_COL + 1,
      hl_group = "SuruTodoIcon",
      virt_text = { { "", "SuruTodoIcon" } },
      virt_text_pos = "overlay",
    })

    -- selection marker highlight
    vim.api.nvim_buf_set_extmark(bufnr, ns, row, ROW_MARKER_COL, {
      end_col = ROW_MARKER_COL + 3,
      hl_group = is_selected and "SuruSelectedMarker" or "SuruMarker",
    })

    -- full-row background for selected (multi-select) rows
    if is_selected then
      vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
        end_row = row + 1,
        hl_group = "SuruMultiSelected",
        hl_eol = true,
        priority = 90, -- below cursorline's default priority so cursorline still shows
      })
    end
  end

  local target = 1
  pcall(vim.api.nvim_win_set_cursor, state.list_popup.winid, { target, 0 })
end

local function ensure_todos_loaded(on_ready)
  if state.all_todos ~= nil then
    on_ready()
    return
  end

  state.loading = true
  render_tabs()
  render_list_placeholder()

  local ok, todos = pcall(actions.get_todos)

  state.all_todos = (ok and type(todos) == "table") and todos or {}
  state.loading = false
  on_ready()
end

local function render()
  render_tabs()
  ensure_todos_loaded(render_list)
end

local function switch_tab(delta)
  state.curr_tab = ((state.curr_tab - 1 + delta) % #tabs) + 1
  state.selected = {} -- selection doesn't carry across tabs
  render_tabs()
  render_list()
end

local function current_row()
  local win = state.list_popup.winid
  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
  if not ok then return nil end
  return cursor[1]
end

local function move_selection(delta)
  if #state.entries == 0 then return end
  local win = state.list_popup.winid
  local cursor = vim.api.nvim_win_get_cursor(win)
  local new_row = math.min(math.max(cursor[1] + delta, 1), #state.entries)
  vim.api.nvim_win_set_cursor(win, { new_row, 0 })
end

-- Toggle multi-select on the todo under the cursor, then re-render
-- (to update the [x]/[ ] marker and row highlight) and step down
-- one row, mirroring the usual "mark and move on" multi-select feel.
local function toggle_select_current()
  if #state.entries == 0 then return end
  local row = current_row()
  if not row then return end

  local entry = state.entries[row]
  if not entry then return end

  if state.selected[entry.orig_index] then
    state.selected[entry.orig_index] = nil
  else
    state.selected[entry.orig_index] = true
  end

  render_list()

  local win = state.list_popup.winid
  local new_row = math.min(row + 1, #state.entries)
  pcall(vim.api.nvim_win_set_cursor, win, { new_row, 0 })
end

-- Flip type (important <-> unimportant) for every selected todo,
-- or -- if nothing is selected -- for whichever todo is under the
-- cursor right now. Refreshes the view afterward; items that no
-- longer belong to the current tab (their type just changed) will
-- naturally drop out of the filtered list on re-render.
local function toggle_type_selected()
  if #state.entries == 0 then return end

  local indices = {}
  if next(state.selected) ~= nil then
    for orig_index in pairs(state.selected) do
      table.insert(indices, orig_index)
    end
  else
    local row = current_row()
    local entry = row and state.entries[row]
    if entry then
      table.insert(indices, entry.orig_index)
    end
  end

  if #indices == 0 then return end

  local any_failed = false
  for _, orig_index in ipairs(indices) do
    local ok = actions.toggle_todo_type(orig_index)
    if not ok then
      any_failed = true
    end
  end

  if any_failed then
    vim.notify(
      "suru: some todos could not be toggled (unexpected type)",
      vim.log.levels.WARN
    )
  end

  state.selected = {}
  render_list()
end

-- dd: on any tab except Completed, marks the selected (or, if
-- nothing is selected, the current-row) todo(s) as done. On the
-- Completed tab, dd instead permanently deletes them. Either way,
-- selection is cleared and the list re-renders -- items that just
-- got marked done will naturally drop out of non-Completed tabs.
local function handle_dd()
  if #state.entries == 0 then return end

  local indices = {}
  if next(state.selected) ~= nil then
    for orig_index in pairs(state.selected) do
      table.insert(indices, orig_index)
    end
  else
    local row = current_row()
    local entry = row and state.entries[row]
    if entry then
      table.insert(indices, entry.orig_index)
    end
  end

  if #indices == 0 then return end

  local tab_name = tabs[state.curr_tab]
  local ok, err
  if tab_name == "Completed" then
    ok, err = actions.delete_todos(indices)
  else
    ok, err = actions.mark_todos_done(indices)
  end

  if not ok then
    vim.notify("suru: " .. tostring(err), vim.log.levels.WARN)
  end

  state.selected = {}
  render_list()
end

local function close()
  if state.layout then
    state.layout:unmount()
    state.layout = nil
    state.all_todos = nil
    state.selected = {}
  end
end

local function setup_keymaps()
  local bufnr = state.list_popup.bufnr
  local opts = { noremap = true, nowait = true, silent = true, buffer = bufnr }

  vim.keymap.set("n", "j", function() move_selection(1) end, opts)
  vim.keymap.set("n", "k", function() move_selection(-1) end, opts)
  vim.keymap.set("n", "<Down>", function() move_selection(1) end, opts)
  vim.keymap.set("n", "<Up>", function() move_selection(-1) end, opts)

  vim.keymap.set("n", "l", function() switch_tab(1) end, opts)
  vim.keymap.set("n", "h", function() switch_tab(-1) end, opts)
  vim.keymap.set("n", "<Tab>", function() switch_tab(1) end, opts)
  vim.keymap.set("n", "<S-Tab>", function() switch_tab(-1) end, opts)

  vim.keymap.set("n", "<Space>", toggle_select_current, opts)
  vim.keymap.set("n", "x", toggle_type_selected, opts)
  vim.keymap.set("n", "dd", handle_dd, opts)

  vim.keymap.set("n", "q", close, opts)
  vim.keymap.set("n", "<Esc>", close, opts)

  -- Neutralize anything that mutates the buffer or enters insert mode.
  -- Notes:
  --  - "x" is the "toggle type" action above, not delete-char.
  --  - "d" is intentionally NOT in this list: it needs to remain the
  --    unmapped prefix key so "dd" (mapped above) can fire. Vim's
  --    mapping engine will wait up to 'timeoutlen' after a lone "d"
  --    to see if "dd" completes; "D" (delete-to-EOL) is still blocked
  --    below since it's a different key and not part of that sequence.
  local disabled_keys = {
    "i", "a", "o", "O", "I", "A", "s", "S", "c", "C", "R",
    "X", "D", "p", "P", "u", "U", "r", "J", "~",
    ">", "<", "v", "V", "<C-v>",
  }
  for _, key in ipairs(disabled_keys) do
    vim.keymap.set("n", key, "<Nop>", opts)
  end
  vim.keymap.set("n", "cc", "<Nop>", opts)
  vim.keymap.set("v", "d", "<Nop>", opts)
  vim.keymap.set("v", "p", "<Nop>", opts)
end

function M.open()
  setup_highlights()
  state.curr_tab = 1
  state.all_todos = nil
  state.selected = {}

  state.tab_popup = Popup({
    enter = false,
    focusable = false,
    border = {
      style = "rounded",
      text = { top = " MY TODOS ", top_align = "center" },
      highlight = "SuruBorder",
    },
    win_options = {
      winhighlight = "Normal:NormalFloat,FloatBorder:SuruBorder",
    },
  })

  state.list_popup = Popup({
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      highlight = "SuruBorder",
    },
    win_options = {
      cursorline = true,
      winhighlight = "Normal:NormalFloat,FloatBorder:SuruBorder,CursorLine:SuruTodoSelected",
    },
    buf_options = {
      modifiable = false,
      readonly = true,
      buftype = "nofile",
      swapfile = false,
    },
  })

  state.layout = Layout(
    {
      position = "50%",
      size = { width = 80, height = 23 },
    },
    Layout.Box({
      Layout.Box(state.tab_popup, { size = 3 }),
      Layout.Box(state.list_popup, { size = "100%" }),
    }, { dir = "col" })
  )

  state.layout:mount()

  setup_keymaps()
  render()

  state.list_popup:on(event.BufLeave, close)

  return state.layout
end

return M
