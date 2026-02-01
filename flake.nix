{
  description = "R.nvim development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Neovim
            neovim

            # Lua with all testing packages bundled
            (lua5_1.withPackages (
              ps: with ps; [
                luarocks
                busted
                luafilesystem
                penlight
                luassert
                lua-cjson
                luasystem
                dkjson
                say
                mediator_lua
                nlua
              ]
            ))

            # Tree-sitter
            tree-sitter
            nodejs # for tree-sitter CLI via npm

            # Build tools
            gcc
            gnumake
            git
          ];

          shellHook = ''
                        echo "🚀 R.nvim development environment loaded"
                        echo "📦 Neovim: $(nvim --version | head -1)"
                        echo "🧪 Run 'busted --verbose tests/' to run tests"
                        echo ""

                        # Install lua-term via luarocks if not present (not in nixpkgs lua5_1 packages)
                        if ! lua -e "require('term')" 2>/dev/null; then
                          echo "📥 Installing lua-term via luarocks..."
                          luarocks install --local lua-term
                          # Add local luarocks to path
                          export LUA_PATH="$HOME/.luarocks/share/lua/5.1/?.lua;$HOME/.luarocks/share/lua/5.1/?/init.lua;$LUA_PATH"
                          export LUA_CPATH="$HOME/.luarocks/lib/lua/5.1/?.so;$LUA_CPATH"
                        fi

                        # Create .busted config for Nix environment (not tracked in git)
                        cat > .busted <<'EOF'
            return {
              _all = {
                coverage = false,
                lpath = "lua/?.lua;lua/?/init.lua;tests/?.lua;tests/?/init.lua",
                lua = "nlua",
                verbose = true,
                helper = "tests/test_helper.lua",
              },
            }
            EOF
          '';
        };

        # Optional: Add a package for R.nvim itself
        packages.default = pkgs.vimUtils.buildVimPlugin {
          pname = "R.nvim";
          version = "0.1.0";
          src = ./.;
        };
      }
    );
}
