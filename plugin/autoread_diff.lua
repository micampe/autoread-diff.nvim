if vim.g.loaded_autoread_diff then return end; vim.g.loaded_autoread_diff = true

local augroup = vim.api.nvim_create_augroup("AutoreadDiff", { clear = true })

vim.api.nvim_create_autocmd("BufReadPost", {
  group = augroup,
  callback = function(ev) require('autoread_diff').on_reload(ev.buf) end,
})

vim.api.nvim_create_autocmd("VimEnter", {
  group = augroup,
  callback = function() require('autoread_diff').init_baseline() end,
})

vim.api.nvim_create_autocmd("BufWritePost", {
  group = augroup,
  callback = function(ev) require('autoread_diff').update_baseline(ev.buf) end,
})

vim.api.nvim_create_autocmd("BufWipeout", {
  group = augroup,
  callback = function(ev) require('autoread_diff').clear_baseline(ev.buf) end,
})

vim.api.nvim_create_autocmd("ModeChanged", {
  group = augroup,
  pattern = "*:i*",
  callback = function(ev) require('autoread_diff').clear_highlight(ev.buf) end,
})

vim.api.nvim_create_autocmd("BufModifiedSet", {
  group = augroup,
  callback = function(ev)
    if vim.bo[ev.buf].modified then
      require('autoread_diff').clear_highlight(ev.buf)
    end
  end,
})

vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
  group = augroup,
  callback = function(ev)
    if vim.g.autoread_diff_highlight_ms == nil or vim.g.autoread_diff_highlight_ms > 0 then
      require('autoread_diff').clear_highlight(ev.buf)
    end
  end,
})

vim.api.nvim_create_user_command(
  "AutoreadDiffClear",
  function()
    require('autoread_diff').clear_highlight(vim.api.nvim_get_current_buf())
  end,
  { desc = "clear autoread diff" }
)
