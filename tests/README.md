# Test Suite for Project

This directory contains tests for the project. Follow the instructions below to run the tests.

```bash
nvim --headless -u tests/init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/init.lua', sequential = true}"
```

- `--headless` runs Neovim without a user interface, suitable for automated processes like testing.
- `-u tests/init.lua` specifies the Neovim configuration file to use for this
  session. This option allows you to define a custom initialization script
  (`init.lua` located in the `tests/` directory) which sets up the environment
  for the tests, including loading necessary plugins and configurations.
- `-c <COMMAND>` is a command to execute inside Neovim once it starts. This specific command uses:
  - `PlenaryBustedDirectory`: A command provided by the `plenary.nvim` plugin
    that runs tests within a specified directory. This command integrates with
    the Busted test framework, allowing for Lua tests to be executed within Neovim's environment.
  - `tests/`: The directory where the test files are located. This tells
    `PlenaryBustedDirectory` where to find the tests to run.
  - `{minimal_init = 'tests/init.lua', sequential = true}`: An options table
    passed to `PlenaryBustedDirectory`.
    - `minimal_init = 'tests/init.lua'` specifies a minimal initialization file
      for Neovim during the test runs. This is used to configure Neovim in a
      lightweight way, focusing only on what's necessary for the tests.
    - `sequential = true` indicates that the tests should be run sequentially.
      This can be important for ensuring tests do not interfere with each other,
      especially when they involve modifying Neovim's state or filesystem.
