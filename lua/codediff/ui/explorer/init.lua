-- Git status explorer
-- Public API for explorer module
local M = {}

-- Import submodules
local render = require("codediff.ui.explorer.render")
local refresh = require("codediff.ui.explorer.refresh")
local actions = require("codediff.ui.explorer.actions")

-- Delegate to render module
M.create = render.create
M.rerender_current = render.rerender_current
M.show_welcome_page = render.show_welcome_page

-- Delegate to refresh module
M.setup_auto_refresh = refresh.setup_auto_refresh
M.refresh = refresh.refresh

-- Delegate to actions module
M.navigate_next = actions.navigate_next
M.navigate_prev = actions.navigate_prev
M.navigate_next_in_group = actions.navigate_next_in_group
M.navigate_prev_in_group = actions.navigate_prev_in_group
M.toggle_visibility = actions.toggle_visibility
M.toggle_view_mode = actions.toggle_view_mode
M.toggle_stage_entry = actions.toggle_stage_entry
M.toggle_stage_file = actions.toggle_stage_file
M.stage_all = actions.stage_all
M.unstage_all = actions.unstage_all
M.restore_entry = actions.restore_entry

return M
