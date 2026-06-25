# autoread-diff.nvim

This plugin shows what changed when a file is reloaded after being modified
externally.

The changes will be visible for a few seconds or until the cursor is moved.

## Install

To install and load the plugin just add this:

```lua
vim.pack.add({"https://codeberg.org/micampe/autoread-diff.nvim"})
```

You can change the timeout:

```lua
vim.g.autoread_diff_highlight_ms = 5000
```

![Screenshot](https://codeberg.org/micampe/autoread-diff.nvim/raw/branch/media/screenshot.png)
