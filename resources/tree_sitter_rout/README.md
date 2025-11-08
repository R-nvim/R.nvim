# How to compile the tree-sitter `rout` parser

1. Install the command line application `tree-sitter`.

2. Go `R.nvim` directory and run the commands:

```sh
mkdir -p parser
cd resources/tree_sitter_rout
tree-sitter generate grammar.js
make
cp libtree-sitter-rout.so ../../parser/rout.so
```

