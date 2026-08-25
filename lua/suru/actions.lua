local M = {}

local curr_todos = {}
local is_setup = false
local loaded_root = nil

local VALID_TYPES = {
  important = true,
  unimportant = true,
}

local ROOT_MARKERS = { ".git", ".hg", ".svn" }

local CACHE_DIR = vim.fn.stdpath("cache") .. "/suru"

local function get_project_root()
  local bufnr = vim.api.nvim_get_current_buf()

  local root = vim.fs.root(bufnr, ROOT_MARKERS)

  if root then
    return vim.fs.normalize(root)
  end

  return vim.fs.normalize(vim.fn.getcwd())
end

local function get_project_key(root)
  return vim.fn.sha256(root)
end

local function get_file_path(root)
  local project_key = get_project_key(root)

  vim.fn.mkdir(CACHE_DIR, "p")

  return CACHE_DIR .. "/" .. project_key .. ".json"
end

local function save_todos()
  local root = get_project_root()
  local project_key = get_project_key(root)
  local file_path = get_file_path(root)

  local file = io.open(file_path, "w")

  if not file then
    print("Unable to write todos to: " .. file_path)
    return false
  end

  local data = {
    project_key = project_key,
    project_root = root,
    todos = curr_todos,
  }

  file:write(vim.json.encode(data))
  file:flush()
  file:close()

  return true
end

function M.setup()
  local root = get_project_root()

  -- Already loaded this project.
  if is_setup and loaded_root == root then
    return
  end

  local project_key = get_project_key(root)
  local file_path = get_file_path(root)

  -- Reset state for the new project.
  curr_todos = {}
  loaded_root = root
  is_setup = true

  local file = io.open(file_path, "r")

  -- No todos saved for this project yet.
  if not file then
    return
  end

  local contents = file:read("*a")
  file:close()

  if contents == "" then
    return
  end

  local ok, data = pcall(vim.json.decode, contents)

  if not ok or type(data) ~= "table" then
    print("Unable to read todos from: " .. file_path)
    return
  end

  -- Make sure this cache file actually belongs
  -- to the project we're currently in.
  if data.project_key ~= project_key then
    print("Todo cache belongs to a different project")
    return
  end

  if type(data.todos) == "table" then
    curr_todos = data.todos
  end
end

function M.add_todo()
  M.setup()

  vim.ui.input({ prompt = "Add todo: " }, function(input)
    if input == nil or input == "" then
      return
    end

    table.insert(curr_todos, {
      title = input,
      type = "important",
      status = "todo",
    })

    if not save_todos() then
      table.remove(curr_todos)

      print("Unable to save todo")
    end
  end)
end

function M.get_todos()
  M.setup()

  return curr_todos
end

function M.change_todo_type(index, new_type)
  M.setup()

  if not VALID_TYPES[new_type] then
    return false, "invalid type: " .. tostring(new_type)
  end

  local todo = curr_todos[index]

  if not todo then
    return false, "no todo at index " .. tostring(index)
  end

  local old_type = todo.type

  todo.type = new_type

  if not save_todos() then
    todo.type = old_type
    return false, "failed to write todos"
  end

  return true
end

function M.toggle_todo_type(index)
  M.setup()

  local todo = curr_todos[index]

  if not todo then
    return false, "no todo at index " .. tostring(index)
  end

  local next_type

  if todo.type == "important" then
    next_type = "unimportant"
  elseif todo.type == "unimportant" then
    next_type = "important"
  else
    return false,
        "todo type '" .. tostring(todo.type) .. "' is not toggleable"
  end

  return M.change_todo_type(index, next_type)
end

function M.mark_todos_done(indices)
  M.setup()

  local changed = false

  for _, index in ipairs(indices) do
    local todo = curr_todos[index]

    if todo then
      todo.status = "done"
      changed = true
    end
  end

  if changed and not save_todos() then
    return false, "failed to write todos"
  end

  return true
end

function M.delete_todos(indices)
  M.setup()

  local sorted = {}

  for _, index in ipairs(indices) do
    table.insert(sorted, index)
  end

  table.sort(sorted, function(a, b)
    return a > b
  end)

  local changed = false

  for _, index in ipairs(sorted) do
    if curr_todos[index] then
      table.remove(curr_todos, index)
      changed = true
    end
  end

  if changed and not save_todos() then
    return false, "failed to write todos"
  end

  return true
end

return M
