if vim.g.loaded_autoread_diff then return end; vim.g.loaded_autoread_diff = true

local augroup = vim.api.nvim_create_augroup("AutoreadDiff", { clear = true })

vim.api.nvim_create_autocmd({ "BufReadPost" }, {
  group = augroup,
  callback = function(ev)
    require('autoread_diff').on_reload(ev.buf)

    -- scheduled later so we don't clear if the cursor moves during the reload
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(ev.buf) then
        vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
          group = augroup, buffer = ev.buf, once = true,
          callback = function() require('autoread_diff').clear_highlight(ev.buf) end,
        })
      end
    end)
  end,
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
