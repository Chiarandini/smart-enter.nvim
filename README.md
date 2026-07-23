# smart-enter.nvim

A context dispatched newline. One insert mode key (default `<S-CR>`) does the
right thing for where the cursor is:

- continues a LaTeX environment (`\\` in a matrix, `\\` then `&= ` in `align`, `\item ` in a list)
- continues a Markdown list, checkbox, or blockquote (renumbering ordered lists, exiting on an empty item)
- otherwise inserts a plain newline that does not re-insert a comment leader

Rules are plain data. Detection is Treesitter based for LaTeX (no VimTeX
dependency) and Lua pattern based for line shapes. Extend any filetype through
`setup()` opts.

## Requirements

- Neovim 0.10 or newer (`vim.keycode`, and `vim.treesitter` for the latex preset)
- The `latex` Treesitter parser, for the latex preset
- A terminal that sends `<S-CR>` distinctly from `<CR>` (Kitty, WezTerm, iTerm2
  with the CSI u profile, most GUIs). Otherwise set a different `key`, or set
  `key = false` and drive `dispatch()` from your own mapping.

Run `:checkhealth smart_enter` to confirm the key, the parser, and the
configured filetypes.

## Setup

Call `require("smart_enter").setup{}` once:

```lua
require("smart_enter").setup({
  key      = "<S-CR>",     -- insert mode map; false to skip and drive dispatch() yourself
  fallback = "newline",    -- "newline" (no comment leader) | "cr" | false | function(ctx)
  filetypes = {
    markdown = { preset = "markdown" },
    tex      = { preset = "latex" },
    latex    = { preset = "latex" },
  },
})
```

With [lazy.nvim](https://github.com/folke/lazy.nvim), the `opts` table is
lazy's way of passing that config, and `config` calls `setup`:

```lua
{ "Chiarandini/smart-enter.nvim", event = "InsertEnter",
  opts = { filetypes = { markdown = { preset = "markdown" }, tex = { preset = "latex" } } },
  config = function(_, opts) require("smart_enter").setup(opts) end }
```

## Extending

`filetypes[ft]` is `{ preset = <name|list>, rules = {...} }`. Your `rules` are
tried before the preset's, so they win:

```lua
-- adds a rule without touching the latex preset
require("smart_enter").setup({ filetypes = { tex = { rules = {
  { env = "exercise", item = "\\Question " },
} } } })
```

A `["*"]` filetype applies its rules to every filetype, after that filetype's
own rules. Use it for behaviour you want everywhere, for example continuing a
comment leader read from `commentstring`.

### Rule shapes

Insert fixed text around the break with `append` and `prefix`. The new line is
indented to the current line, then `prefix`; `append` is glued to the current
line at the cursor (the row separator):

```lua
{ env = "align", append = "\\\\", prefix = "&= " }   -- match one environment
{ pattern = "^%s*> ", prefix = "> " }                -- match on the line text
```

Continue a list with `item`. The new entry lines up with the current entry,
not with the deeper indent of a soft wrapped continuation line, and pressing on
an empty entry clears the marker and exits the list. `item` is a string, or a
table with `exit_empty` and `counter`:

```lua
{ envs = { "itemize", "enumerate" }, item = "\\item " }
{ env = "exercise", item = "\\Question " }
{ env = "notes",    item = { text = "\\item ", exit_empty = false } }
{ env = "steps",    item = { text = "\\item[{})] ", counter = "alpha" } }  -- a), b), c)
```

`counter` is `"arabic"`, `"alpha"`/`"Alpha"`, or `"roman"`/`"Roman"`; the `{}`
in `text` becomes the previous entry's counter plus one.

Run your own logic with `handle` for anything the fields above do not cover.
It returns `false` to fall through to the next rule; anything else (including
`nil`) counts as handled:

```lua
{ pattern = "^(%s*)(%d+)%.%s(.*)", handle = function(ctx, caps)
    ctx.split("", caps[1] .. tostring(tonumber(caps[2]) + 1) .. ". ")
end }
```

The `ctx` object exposes `ctx.split(append, prefix)`, `ctx.replace_line(text)`,
and the fields `buf`, `win`, `row`, `col`, `line`, `ws`, `filetype`.

### Matchers and actions

The `env`, `pattern`, and `item` fields cover the common rules. For anything
else, two modules give building blocks for a rule's `match` and `handle`:

- `require("smart_enter.matchers")`: `pattern(lua_pat)`, `ts_env(names[, lang])`,
  and `env_chain(ctx[, lang])` (enclosing environment names, innermost first).
- `require("smart_enter.actions")`: `item(template)`, the handler behind the
  `item` field.

Both are `require`d, so call them where `setup` runs, for example inside a
`config` function, the same as any Lua module loaded at startup.

## Binding to plain `<CR>`

If you want the smart behaviour on `<CR>` and already map `<CR>` for autopairs
or completion, keep `key = false` and compose in your own map. `dispatch({ fallback = false })`
runs the rules, skips the built in fallback, and reports whether a rule matched:

```lua
vim.keymap.set("i", "<CR>", function()
  if require("smart_enter").dispatch({ fallback = false }) then
    return
  end
  -- no rule matched: run your existing <CR> behaviour here
end)
```

## Non-goals

smart-enter stays small on purpose. These belong to dedicated plugins:

- Renumbering or reformatting a whole list after later edits (see autolist.nvim).
- `<Tab>` and `<S-Tab>` indent and dedent of list items.
- Normal mode `o` and `O` continuation. You can bind `dispatch()` to any key.

## API

- `require("smart_enter").setup(opts)`
- `require("smart_enter").dispatch(opts?)`: run the smart action; returns `true`
  when a rule handled it. `opts.fallback = false` skips the built in fallback so
  you can compose with your own `<CR>` behaviour. Bind it from any key.
- `require("smart_enter").inspect([lang])`: report the filetype, the Treesitter
  environment chain, and which configured rules match at the cursor. Run it
  where the key behaves unexpectedly to see what the rules see.
