# nvim-startuptime

`nvim-startuptime` is a plugin for viewing `nvim` startup event timing
information.

## Installation

A package manager can be used to install `nvim-startuptime`.

```lua
vim.pack.add({ "https://github.com/seblyng/nvim-startuptime" })
```

## Usage

- Launch `nvim-startuptime` with `:StartupTime`.
- Press `<C-s>` to toggle sort between descending time and original order.
- Times are in milliseconds.

## Features

- In process language server is attached with hover and definition support.
  - Use `vim.lsp.buf.hover()` to view more information about a startup event.
  - Use `vim.lsp.buf.definition()` to jump to the source of a startup event.

## License

The source code has an [MIT License](https://en.wikipedia.org/wiki/MIT_License).
