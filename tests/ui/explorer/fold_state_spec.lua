-- Test: Explorer fold state survives a refresh
--
-- Regression coverage for two defects in ui/explorer/refresh.lua:
--   1. Collapsed state was keyed by `node.data.path or node.data.name`. Directory
--      nodes carry `dir_path`, never `path`, so the key fell back to the bare
--      basename and every same-named directory in the tree shared one fold flag --
--      collapsing `a/api` also slammed `b/api` shut on the next refresh.
--   2. The collapsed-state snapshot was taken before the async `git status`, so a
--      fold toggled while the call was in flight got reverted when it returned.

local h = dofile("tests/helpers.lua")

-- Ensure plugin is loaded (needed for PlenaryBustedFile subprocess)
h.ensure_plugin_loaded()

-- Setup CodeDiff command for tests
local function setup_command()
  local commands = require("codediff.commands")
  vim.api.nvim_create_user_command("CodeDiff", function(opts)
    commands.vscode_diff(opts)
  end, {
    nargs = "*",
    bang = true,
    complete = function()
      return { "file", "install" }
    end,
  })
end

--- Spin the event loop so an async git status + vim.schedule callback lands.
local function wait_for_async(timeout_ms)
  vim.wait(timeout_ms or 3000, function()
    return false
  end, 50)
end

--- Open :CodeDiff in the given repo and wait until the explorer is ready.
--- @param repo table  Repo helper from h.create_temp_git_repo()
--- @return table explorer
local function open_codediff_and_wait(repo)
  vim.fn.chdir(repo.dir)
  vim.cmd("edit " .. repo.path("a/api/one.txt"))
  vim.cmd("CodeDiff")

  local lifecycle = require("codediff.ui.lifecycle")
  local explorer

  local ready = vim.wait(10000, function()
    for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
      local s = lifecycle.get_session(tp)
      if s and s.explorer and s.explorer.tree and #(s.explorer.tree:get_nodes() or {}) > 0 then
        explorer = s.explorer
        return true
      end
    end
    return false
  end, 100)

  assert.is_true(ready, "CodeDiff explorer should be ready")
  return explorer
end

--- Find a directory node by its dir_path, walking the whole tree.
--- Must be re-run after every refresh: the tree is rebuilt from scratch, so
--- previously held node handles go stale.
--- @param explorer table
--- @param dir_path string
--- @return table|nil
local function find_dir(explorer, dir_path)
  local tree = explorer.tree
  local found

  local function walk(node)
    if node.data and node.data.type == "directory" and node.data.dir_path == dir_path then
      found = node
    end
    if node:has_children() then
      for _, child_id in ipairs(node:get_child_ids()) do
        local child = tree:get_node(child_id)
        if child then
          walk(child)
        end
      end
    end
  end

  for _, node in ipairs(tree:get_nodes() or {}) do
    walk(node)
  end

  return found
end

--- Assert on the expanded state of a directory, re-resolving it from the tree.
local function assert_expanded(explorer, dir_path, expected, msg)
  local node = find_dir(explorer, dir_path)
  assert.is_not_nil(node, "directory " .. dir_path .. " should exist in the tree")
  assert.equals(expected, node:is_expanded(), msg)
end

-- ============================================================================
describe("Explorer Fold State", function()
  local repo
  local original_cwd
  local config

  before_each(function()
    require("codediff").setup({ diff = { layout = "side-by-side" } })
    setup_command()

    config = require("codediff.config")
    config.options.explorer.view_mode = "tree"
    -- Flattening would merge these single-child chains into one node each and
    -- hide the basename collision this spec is about.
    config.options.explorer.flatten_dirs = false

    original_cwd = vim.fn.getcwd()
    repo = h.create_temp_git_repo()

    -- Two directories that share the basename `api` under different parents.
    repo.write_file("a/api/one.txt", { "one" })
    repo.write_file("b/api/two.txt", { "two" })
    repo.git("add -A")
    repo.git("commit -m initial")

    -- Modify both so each shows up as an unstaged change in the explorer.
    repo.write_file("a/api/one.txt", { "one", "changed" })
    repo.write_file("b/api/two.txt", { "two", "changed" })
  end)

  after_each(function()
    h.close_extra_tabs()
    config.options.explorer.view_mode = "list"
    config.options.explorer.flatten_dirs = true
    vim.fn.chdir(original_cwd)
    if repo then
      repo.cleanup()
    end
  end)

  it("does not collapse a same-named directory elsewhere in the tree", function()
    local explorer = open_codediff_and_wait(repo)
    local refresh = require("codediff.ui.explorer.refresh")

    -- Both start expanded; fold only the one under `a`.
    assert_expanded(explorer, "a/api", true, "a/api should start expanded")
    assert_expanded(explorer, "b/api", true, "b/api should start expanded")
    find_dir(explorer, "a/api"):collapse()
    explorer.tree:render()

    refresh.refresh(explorer)
    wait_for_async()

    assert_expanded(explorer, "a/api", false, "a/api should stay collapsed after refresh")
    assert_expanded(explorer, "b/api", true, "b/api should stay expanded -- it only shares a basename with a/api")
  end)

  it("keeps a fold toggled while the git status call is in flight", function()
    local explorer = open_codediff_and_wait(repo)
    local refresh = require("codediff.ui.explorer.refresh")

    assert_expanded(explorer, "a/api", true, "a/api should start expanded")

    -- refresh() kicks off an async git status and returns immediately; folding
    -- here lands before the result is applied.
    refresh.refresh(explorer)
    find_dir(explorer, "a/api"):collapse()
    explorer.tree:render()
    wait_for_async()

    assert_expanded(explorer, "a/api", false, "a fold made during the async window should survive the refresh")
  end)
end)
