{
  description = "A feature-rich, multi-protocol messaging broker";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
    rabbitmq-perf-test = {
      url = "github:the-mikedavis/rabbitmq-perf-test/flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "utils";
    };
  };

  outputs = { nixpkgs, utils, rabbitmq-perf-test, ... }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (_final: _prev: { inherit (rabbitmq-perf-test.packages.${system}) perf-test; })
          ];
        };
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            gnumake
            bazel_5
            mandoc
            openjdk
            openssl
            python3
            perf-test
            (writeShellScriptBin "open" '' exec "${pkgs.xdg-utils}/bin/xdg-open" "$@" '')
            erlangR25
            elixir_1_13
          ];
          shellHook = ''
            export CC=${pkgs.clang}/bin/clang

            # This is used by perf-test. I can't tell what sets it in the first place :/
            unset SIZE
          '';
        };
      });
}
