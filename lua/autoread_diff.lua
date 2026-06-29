-- Briefly highlights what changed when a buffer is reloaded from disk.

local ns = vim.api.nvim_create_namespace("autoread_diff")
-- we always store the last known content of the file because there is no
-- reliable autocmd to get it when a reload happens
-- - BufUnload works when reloading manually
-- - FileChangedShell does not fire if autoread = true
local baseline = {} -- {bufnr = last-known lines}
local DEFAULT_HIGHLIGHT_MS = 5000
local DEFAULT_MAX_BYTES = 1 * 1024 * 1024

-- Decompose a line into codepoints:
-- Return: a list of { b = 0-based byte offset, s = codepoint string }
local function to_codepoints(line)
  local cp_pos = vim.str_utf_pos(line)
  local cps = {}
  for i, b in ipairs(cp_pos) do
    cps[i] = { b = b - 1, s = line:sub(b, (cp_pos[i + 1] or #line + 1) - 1) }
  end
  return cps
end

-- Returns false for out of range values
local function is_keyword(cps, i)
  return cps[i] ~= nil and vim.fn.charclass(cps[i].s) == 2
end

-- Extract character level diff from two lines
--
-- Returns two values:
--   - changes: list of { first, last, replaced }
--   - deletes: list of { del_mark, col, text }
--              del_mark is the index of the codepoint to highlight
--              when show_deleted_text is false
local function intra_line_diff(old_cps, new_cps)
  local function joined(cps)
    local t = {}
    for i, cp in ipairs(cps) do t[i] = cp.s end
    return table.concat(t, "\n") .. "\n"
  end

  local changes, deletes = {}, {}
  local hunks = vim.text.diff(
    joined(old_cps),
    joined(new_cps),
    { result_type = "indices", algorithm = "histogram" }
  )

  ---@cast hunks integer[][]
  for _, h in ipairs(hunks) do
    local old_start, old_count, new_start, new_count = h[1], h[2], h[3], h[4]

    if new_count > 0 then
      local lo, hi = new_start, new_start + new_count - 1
      -- expand the range to highlight a full keyword instead of individual characters
      while lo > 1 and is_keyword(new_cps, lo) and is_keyword(new_cps, lo - 1) do
        lo = lo - 1
      end
      while hi < #new_cps and is_keyword(new_cps, hi) and is_keyword(new_cps, hi + 1) do
        hi = hi + 1
      end
      changes[#changes + 1] = { first = lo, last = hi, replaced = old_count > 0 }
    else
      local removed = {}

      for j = old_start, old_start + old_count - 1 do
        if old_cps[j] then
          removed[#removed + 1] = old_cps[j].s
        end
      end

      local del_mark
      if new_start < #new_cps then
        del_mark = new_start + 1
      elseif new_start >= 1 then
        del_mark = new_start
      end

      deletes[#deletes + 1] = {
        del_mark = del_mark,
        at = new_start,
        col = new_start >= 1 and (new_cps[new_start].b + #new_cps[new_start].s) or 0,
        text = table.concat(removed),
      }
    end
  end

  -- merge close changes to make a cleaner diff
  local merged = {}
  local merge_gap = 1
  table.sort(changes, function(a, b) return a.first < b.first end)
  for _, change in ipairs(changes) do
    local prev = merged[#merged]
    local prev_last = prev and prev.last
    if prev and change.first - prev_last <= merge_gap + 1 then
      prev.last = math.max(prev_last, change.last)
      prev.replaced = prev.replaced or change.replaced
    else
      merged[#merged + 1] = { first = change.first, last = change.last, replaced = change.replaced }
    end
  end

  -- merge deletions with nearby changes
  local kept_deletes = {}
  for _, deletion in ipairs(deletes) do
    local absorbed = false
    for _, change in ipairs(merged) do
      if deletion.at >= change.first - 1 - merge_gap
        and deletion.at <= change.last + merge_gap
      then
        change.replaced = true
        absorbed = true
        break
      end
    end
    if not absorbed then
      kept_deletes[#kept_deletes + 1] = deletion
    end
  end

  return merged, kept_deletes
end

local function highlight_changed_line(buf, lnum, old_line, new_line)
  local function highlight_range(cp_lo, cp_hi, hl)
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, cp_lo.b, { end_col = cp_hi.b + #cp_hi.s, hl_group = hl })
  end

  local new_cps = to_codepoints(new_line)
  if #new_cps == 0 then  -- line is empty, highlight the whole screen line
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = "DiffDelete" })
    return
  end

  local old_cps = to_codepoints(old_line)
  local changes, deletes = intra_line_diff(old_cps, new_cps)

  for _, change in ipairs(changes) do
    highlight_range(new_cps[change.first], new_cps[change.last], change.replaced and "DiffText" or "DiffAdd")
  end

  local show_deleted = vim.g.autoread_diff_show_deleted_text == nil or vim.g.autoread_diff_show_deleted_text
  for _, deletion in ipairs(deletes) do
    if show_deleted then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, deletion.col, {
        virt_text = { { deletion.text, "DiffDelete" } },
        virt_text_pos = "inline",
      })
    elseif deletion.del_mark then
      highlight_range(new_cps[deletion.del_mark], new_cps[deletion.del_mark], "DiffDelete")
    end
  end
end

local function within_size_limit(buf)
  local max_bytes = vim.g.autoread_diff_max_bytes
  if max_bytes == nil then max_bytes = DEFAULT_MAX_BYTES end
  if max_bytes == false then return true end
  return vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf)) <= max_bytes
end

local function update_baseline(buf)
  if not within_size_limit(buf) then
    baseline[buf] = nil
    return
  end
  baseline[buf] = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function clear_baseline(buf)
  baseline[buf] = nil
end

local function init_baseline()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" then
      update_baseline(buf)
    end
  end
end

local function clear_highlight(buf)
  if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].autoread_diff_active then
    vim.b[buf].autoread_diff_active = nil
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
end

local function on_reload(buf)
  if not within_size_limit(buf) then
    baseline[buf] = nil
    return
  end

  local new = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local old = baseline[buf]
  baseline[buf] = new
  if not old then return end

  local hunks = vim.text.diff(
    table.concat(old, "\n") .. "\n",
    table.concat(new, "\n") .. "\n",
    { result_type = "indices", algorithm = "histogram", linematch = 60 }
  )

  if #hunks == 0 then return end

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  vim.b[buf].autoread_diff_active = true

  ---@cast hunks integer[][]
  for _, h in ipairs(hunks) do
    local old_start, old_count, new_start, new_count = h[1], h[2], h[3], h[4]

    if new_count == 0 then
      vim.api.nvim_buf_set_extmark(buf, ns, math.max(0, new_start - 1), 0, {
        line_hl_group = "DiffDelete",
      })
    else
      for i = 0, new_count - 1 do
        local line = new_start + i - 1
        if i >= old_count then
          vim.api.nvim_buf_set_extmark(buf, ns, line, 0, { line_hl_group = "DiffAdd" })
        else
          highlight_changed_line(buf, line, old[old_start + i], new[new_start + i])
        end
      end
    end
  end

  local highlight_ms = vim.g.autoread_diff_highlight_ms or DEFAULT_HIGHLIGHT_MS
  if highlight_ms > 0 then
    vim.defer_fn(function() clear_highlight(buf) end, highlight_ms)
  end
end

-- Optional: overrides existing config
local function setup(opts)
  opts = opts or {}
  if opts.highlight_ms ~= nil then
    vim.g.autoread_diff_highlight_ms = opts.highlight_ms
  end
  if opts.max_bytes ~= nil then
    vim.g.autoread_diff_max_bytes = opts.max_bytes
  end
  if opts.show_deleted_text ~= nil then
    vim.g.autoread_diff_show_deleted_text = opts.show_deleted_text
  end
end

return {
  setup = setup,
  on_reload = on_reload,
  init_baseline = init_baseline,
  update_baseline = update_baseline,
  clear_baseline = clear_baseline,
  clear_highlight = clear_highlight,
}
