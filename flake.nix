{
  description = "CodeRLM - tree-sitter code indexing for Claude Code";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    claude-code-nix.url = "github:sadjow/claude-code-nix";
  };

  outputs = { self, nixpkgs, flake-utils, claude-code-nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        claude-code = claude-code-nix.packages.${system}.default;

        # --- Rust server ---
        coderlm-server = pkgs.rustPlatform.buildRustPackage {
          pname = "coderlm-server";
          version = "0.1.1";
          src = ./server;
          cargoLock.lockFile = ./server/Cargo.lock;
        };

        # --- Helper to wrap a shell script per ertt.ca/nix/shell-scripts ---
        wrapScript = { name, src, runtimeInputs }:
          let
            script = (pkgs.writeScriptBin name
              (builtins.readFile src)).overrideAttrs (old: {
              buildCommand = "${old.buildCommand}\n patchShebangs $out";
            });
          in pkgs.symlinkJoin {
            inherit name;
            paths = [ script ] ++ runtimeInputs;
            buildInputs = [ pkgs.makeWrapper ];
            postBuild = "wrapProgram $out/bin/${name} --prefix PATH : $out/bin";
          };

        # --- Wrapped scripts ---
        session-init = wrapScript {
          name = "session-init.sh";
          src = ./plugin/scripts/session-init.sh;
          runtimeInputs = with pkgs; [ curl python3 coreutils ];
        };

        session-stop = wrapScript {
          name = "session-stop.sh";
          src = ./plugin/scripts/session-stop.sh;
          runtimeInputs = with pkgs; [ curl python3 coreutils ];
        };

        coderlm-daemon = wrapScript {
          name = "coderlm-daemon.sh";
          src = ./server/coderlm-daemon.sh;
          runtimeInputs = with pkgs; [ curl coreutils ];
        };

        # --- Plugin installer ---
        install-plugin = pkgs.writeShellScriptBin "install-plugin" ''
          set -euo pipefail

          CLAUDE="$(command -v claude 2>/dev/null || echo ${claude-code}/bin/claude)"

          echo "[coderlm] Installing plugin via marketplace..."
          "$CLAUDE" plugin marketplace add johnrichardrinehart/coderlm
          "$CLAUDE" plugin install coderlm@coderlm

          echo "[coderlm] Patching cached scripts with Nix-wrapped versions..."
          CACHE_DIR=$(echo ~/.claude/plugins/cache/coderlm/coderlm/*/scripts)
          if [ ! -d "$CACHE_DIR" ]; then
            echo "[coderlm] Error: plugin cache directory not found at $CACHE_DIR" >&2
            exit 1
          fi

          cp ${session-init}/bin/session-init.sh "$CACHE_DIR/"
          cp ${session-stop}/bin/session-stop.sh "$CACHE_DIR/"

          echo "[coderlm] Done. Restart Claude Code to activate."
        '';

      in {
        packages = {
          default = coderlm-server;
          server = coderlm-server;
          inherit session-init session-stop coderlm-daemon install-plugin;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            cargo rustc rust-analyzer
            curl python3
          ];
        };
      }
    );
}
