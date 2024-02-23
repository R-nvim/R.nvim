# TODO: Use one Makefile for all languages.
#
default: all

# Targets are ones that do not represent files.
.PHONY: all test help coverage

all: help

test:
	@eval $$(luarocks path --lua-version 5.1 --bin) && (busted --run r_tests; exit_code=$$?; \
	if [ $$exit_code -ne 0 ]; then \
		echo "\nTests failed. Please review the errors above to diagnose issues.\n"; \
	else \
		echo "\nAll tests passed successfully.\n"; \
	fi)

help:
	@echo "Available targets:"
	@echo "  all       - The default target, does nothing by itself."
	@echo "  test      - Runs the Lua tests using Busted."
	@echo "  help      - Displays this help information."
	@echo "  coverage  - Generates test coverage (not implemented)."

coverage:
	@echo "Code coverage functionality is not yet implemented."
