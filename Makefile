.PHONY: test clean

test: deps/lazy.nvim
	./scripts/test

deps/lazy.nvim:
	mkdir -p deps
	git clone --depth 1 https://github.com/folke/lazy.nvim.git $@

clean:
	rm -rf deps/
