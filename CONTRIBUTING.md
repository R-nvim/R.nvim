# Contributing to R.nvim

Thank you for your interest in contributing to R.nvim! This Document provides
instructions on how to setup your environment and contribute effectively to the project.

## Setting a Pre-commit Hook

After cloning the repository, run the following commands from a terminal:

```bash
# create a local git hooks directory
mkdir -p .git/hooks

# Create a symlink for pre-commit hook
cd .git/hooks
ln -sf ../../scripts/pre-commit
```

## Formatting

Make sure the formatting tool for the corresponding files in your commit is installed.

| language | formatting tool | installation instructions                        |
| -------- | --------------- | ------------------------------------------------ |
| C        | clang-format    | [clang.llvm.org/docs/ClangFormat.html](https://clang.llvm.org/docs/ClangFormat.html) |
| Lua      | stylua          | [github.com/JohnnyMorganz/stylua](https://github.com/JohnnyMorganz/stylua)           |

If you stage files of a filetype and then commit them, the formatting tool will
be run automatically. That is by virtue of the pre-commit hook.

If you haven't installed the formatting tool, the hook will ask you to install the formatting tool first.

To manually run the formatting tool on files, run the following command from a terminal:

| Language | command                          |
| -------- | -------------------------------- |
| C        | `clang-format -i -style=<STYLE>` |
| Lua      | `stylua`                         |

See the pre-commit hook for specific styles used by the project.
