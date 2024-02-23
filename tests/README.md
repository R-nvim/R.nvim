# Test Suite for R.nvim

Follow the instructions below to run the tests.

```bash
make test
```

- This command executes the custom test runner script `tests/run`, which is
  a wrapper around Neovim in headless mode, tailored for running the test suite.
- The `tests/run` script handles the setup and teardown of the test environment,
  including configuring `XDG` paths for Neovim, installing testing dependencies,
  and linking R.nvim as a Neovim plugin within the test environment.
- The script automatically executes tests found in the test directory using
  Busted, a Lua testing framework, within the Neovim environment, allowing for
  testing of plugin functionality in a way that closely simulates actual usage.
