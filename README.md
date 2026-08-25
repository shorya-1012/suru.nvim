# Suru

A simple, project-aware todo manager for Neovim.

Suru lets you manage todos directly from Neovim without relying on a separate application. Todos are automatically associated with the project you're currently working in, so each project gets its own independent todo list.

## Features

* Add todos directly from Neovim
* Project-aware todo lists
* Todos are persisted automatically
* Todos divided as `important` or `unimportant`
* Mark todos as completed
* Delete todos
* Lightweight and built for Neovim
* UI built with `nui.nvim`

## How project-based todos work

Suru detects the current project's root using common version-control directories:

* `.git`
* `.hg`
* `.svn`

For example:

```text
~/dev/projects/my-project/
├── .git/
├── src/
└── ...
```

Suru identifies:

```text
~/dev/projects/my-project
```

as the project root.

A deterministic hash of the project root is then used as the project's unique identifier. This means different projects get completely separate todo lists.

## Requirements

* Neovim
* [`nui.nvim`](https://github.com/MunifTanjim/nui.nvim)

Suru is currently developed and tested on Linux.

## Installation

### lazy.nvim

Add Suru to your lazy.nvim plugin configuration:
If Suru is hosted on GitHub, you can instead use its repository directly:

```lua
return {
  {
    "shorya-1012/suru.nvim",

    dependencies = {
      "MunifTanjim/nui.nvim",
    },

    config = function()
      local suru = require("suru")

      vim.keymap.set("n", "<leader>tt", function()
        suru.add_todo()
      end, { desc = "Suru: Add Todo" })

      vim.keymap.set("n", "<leader>hh", function()
        suru.show_window()
      end, { desc = "Suru: Show Todos" })
    end,
  },
}
```

## Usage

### Add a todo

Press:

```text
<leader>tt
```

The new todo is created as `important` by default.

### Show todos

Press:

```text
<leader>hh
```

This opens the Suru todo interface.
From the UI you can manage your todos, including changing their importance, completing them, and deleting them.
