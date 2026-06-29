# autoread-diff

Show changes when a file is reloaded after being modified externally.

![Screenshot](https://codeberg.org/micampe/autoread-diff.nvim/raw/branch/media/screenshot.png)

The changes will be visible for a few seconds or until the cursor is moved.

You can change the timeout:

```lua
vim.g.autoread_diff_highlight_ms = 5000
```

Setting the timeout to `0` disables the timer and the cursor movement clear,
so you can move through the file to see all the changes. The diff will be
cleared when entering insert mode or when the buffer is modified.

## Install

To install and load the plugin just add this:

```lua
vim.pack.add({"https://codeberg.org/micampe/autoread-diff.nvim"})
```

You don't need to call a setup function or anything else, the plugin will set
itself up to be loaded on demand.
