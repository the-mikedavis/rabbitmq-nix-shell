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
        erlang = pkgs.erlangR25;
        java = pkgs.openjdk;
        java-version = builtins.elemAt (builtins.match "([[:digit:]]+).*" java.version) 0;
        user-bazelrc-text = pkgs.writeText "user.bazelrc" ''
          build:local --@rules_erlang//:erlang_home=${erlang}/lib/erlang
          build:local --@rules_erlang//:erlang_version=${erlang.version}
          build:local --//:elixir_home=${pkgs.elixir_1_13}/lib/elixir

          build --tool_java_language_version=${java-version}
          build --tool_java_runtime_version=local_jdk

          # rabbitmqctl wait shells out to 'ps', which is broken in the bazel macOS
          # sandbox (https://github.com/bazelbuild/bazel/issues/7448)
          # adding "--spawn_strategy=local" to the invocation is a workaround
          build --spawn_strategy=local

          # --experimental_strict_action_env breaks memory size detection on macOS,
          # so turn it off for local runs
          build --noexperimental_strict_action_env
          build:buildbuddy --experimental_strict_action_env

          # don't re-run flakes automatically on the local machine
          build --flaky_test_attempts=1

          # Always run locally. Remote builds seem to be broken because of /bin/bash replacements.
          build --config=local

          # build:buildbuddy --remote_header=x-buildbuddy-api-key=YOUR_API_KEY_HERE

          # cross compile for linux (if on macOS) with rbe
          # build:rbe --host_cpu=k8
          # build:rbe --cpu=k8
        '';
        linkbazelrc = pkgs.writeShellScriptBin "linkbazelrc" ''
          read -p "Create $(pwd)/user.bazelrc?" -n 1 -r
          echo
          if [[ $REPLY =~ ^[^Nn]$ ]]; then
            ln -s ${user-bazelrc-text} user.bazelrc
          fi
        '';
        openWrapper = pkgs.writeShellScriptBin "open" ''
          exec "${pkgs.xdg-utils}/bin/xdg-open" "$@" 
        '';
      in {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.gnumake
            pkgs.bazel_5
            pkgs.mandoc
            pkgs.openssl
            pkgs.python3
            pkgs.perf-test
            java
            linkbazelrc
            openWrapper
          ];
          shellHook = ''
            export CC=${pkgs.clang}/bin/clang

            # This is used by perf-test. I can't tell what sets it in the first place :/
            unset SIZE
          '';
        };
      });
}
