local M = {}

local actions = require("suru.actions")
local ui = require("suru.ui")

function M.setup()
  print("Hello there from suru todo application")
end

function M.add_todo()
  actions.add_todo()
end

function M.show_window()
  ui.open()
end

return M
