<p align="center">
  <img width="400" src="https://raw.githubusercontent.com/lfrati/onesearch/main/assets/pony.jpeg">
   <p align="center"> The one-trick pony of searching.
</p>


# onesearch.nvim
What is onesearch? Not his [highness of motion](https://github.com/easymotion/vim-easymotion) nor a mind bending [approach](https://github.com/ggandor/leap.nvim).

This pony does one thing and one thing only: interactively searches for a pattern.

## Installation
Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
 use { 'lfrati/onesearch.nvim', config = function()
        vim.keymap.set("n", "/", ":lua require('onesearch').search()<CR>")
 end }
```

## How it works

Onesearch has only one main function `search()`, which dims the text on screen and starts an interactive string search. As you type the matches in the currently visible area are highlighted in green, if there is only a single match the color will change to light blue. 

Multiple matches           |  Single match             | Hints
:-------------------------:|:-------------------------:|:-------------------------:
![](https://raw.githubusercontent.com/lfrati/onesearch.nvim/main/assets/multi.png)   |  ![](https://raw.githubusercontent.com/lfrati/onesearch.nvim/main/assets/single.png) | ![](https://raw.githubusercontent.com/lfrati/onesearch.nvim/main/assets/hints.png) 

Pressing `<Tab>` will loop through groups of matches. Upon pressing `<CR>` the search ends and the jumping begins. The highlight changes to red, showing single char hints that can be used to jump to the matches. If there is only a single match visible it will jump immediately.

```mermaid
graph LR
    A(START) -->|overlay| B(read char)
    B -->|ESC| C(END)
    subgraph pattern
        B --> |char| E(grow) --> B
        B --> |DEL| F(shrink) --> B 
        B -->|TAB| G(move view) --> B
        B -->|ENTER| D{Accept}
    end
    subgraph marks
        D --> |single|J
        D --> |multiple|H(read char)
        H --> |char|J(JUMP)
    end
    H --> |ESC|C
```
## Configuration
The default settings are already perfect, why would you change them?

But if you really want to just override the following defaults:
```lua
require("onesearch").setup{
    flash_t = 150,                    -- how long it flashes for, set to 0 for no flash
    hl = {
        overlay = "NonText",          -- highlight for the background during search
        multi = "OnesearchMulti",     -- highlight for multiple matches
        single = "OnesearchSingle",   -- highlight for single match
        select = "WarningMsg",        -- highlight for hints during target selection
        flash = "Search",             -- highlight for landing flash
    },
    hints = { "a", "s", "d", "f", "h", "j", "k", "l", "w", "e", "r", "u", "i", "o", "x", "c", "n", "m" }
}
```
