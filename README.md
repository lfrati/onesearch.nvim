<p align="center">
  <img width="400" src="https://raw.githubusercontent.com/lfrati/onesearch/main/assets/pony.jpeg">
   <p align="center"> The one-trick pony of searching.
</p>


# onesearch
Opinionated and simple.

Not his [highness of motion](https://github.com/easymotion/vim-easymotion) nor a mind bending [approach](https://github.com/ggandor/leap.nvim).
This pony does one thing and one thing only.
Interactively searches for a pattern, TABs to cycle through matches and easymotion-ly jumps to one of them with a single char. 

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
        D --> |multiple|H(read nchar)
        H --> |char|J(JUMP)
    end
    H --> |ESC|C
```
