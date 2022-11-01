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
    flamegraph-src = {
      url = "github:brendangregg/FlameGraph";
      flake = false;
    };
  };

  outputs = { nixpkgs, utils, rabbitmq-perf-test, flamegraph-src, ... }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (_final: _prev: { inherit (rabbitmq-perf-test.packages.${system}) perf-test; })
          ];
        };
        bazel_5 = pkgs.callPackage ./bazel_5 {
          inherit (pkgs.darwin) cctools;
          inherit (pkgs.darwin.apple_sdk.frameworks) CoreFoundation CoreServices Foundation;
          buildJdk = pkgs.jdk11_headless;
          runJdk = pkgs.jdk11_headless;
          stdenv = if pkgs.stdenv.cc.isClang then pkgs.llvmPackages.stdenv else pkgs.stdenv;
          bazel_self = pkgs.bazel_5;
        };
        erlang-src = pkgs.fetchFromGitHub {
          owner = "erlang";
          repo = "otp";
          rev = "OTP-25.0.4";
          sha256 = "sha256-bC93rEMjdqH/OQsEcDeKfFlAXIIWVanN1ewDdCECdC4=";
        };
        erlang = pkgs.erlangR25.override { src = erlang-src; version = "25.0.4"; };
        elixir = pkgs.elixir_1_13;
        rebar3 = (pkgs.rebar3.overrideAttrs (prev: { buildInputs = [ erlang ]; doCheck = false; }));
        java = pkgs.openjdk;
        inherit (pkgs.linuxPackages-libre) perf;
        java-version = builtins.elemAt (builtins.match "([[:digit:]]+).*" java.version) 0;
        user-bazelrc-text = pkgs.writeText "user.bazelrc" ''
          build:local --@rules_erlang//:erlang_home=${erlang}/lib/erlang
          build:local --@rules_erlang//:erlang_version=${erlang.version}
          build:local --//:elixir_home=${elixir}/lib/elixir

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
        mkflamegraph = pkgs.writeShellScriptBin "mkflamegraph" ''
          WORK_DIR=`mktemp -d`
          if [[ ! "$WORK_DIR" || ! -d "$WORK_DIR" ]]; then
            echo "Could not create temp dir"
            exit 1
          fi
          function cleanup {
            rm -rf "$WORK_DIR"
          }
          trap cleanup EXIT

          ${perf}/bin/perf script > "$WORK_DIR"/out.perf
          # Collapse multiline stacks into single lines
          ${pkgs.perl}/bin/perl ${flamegraph-src + /stackcollapse-perf.pl} "$WORK_DIR"/out.perf > "$WORK_DIR"/out.folded
          # Merge scheduler profile data
          ${pkgs.gnused}/bin/sed -e 's/^[0-9]\+_//' "$WORK_DIR"/out.folded > "$WORK_DIR"/out.folded_sched
          # Create the SVG file
          ${pkgs.perl}/bin/perl ${flamegraph-src + /flamegraph.pl} --title="CPU Flame Graph" "$WORK_DIR"/out.folded_sched > flamegraph.svg
        '';
      in {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.gnumake
            bazel_5
            pkgs.mandoc
            pkgs.openssl
            pkgs.python3
            erlang
            rebar3
            elixir
            java
            linkbazelrc
            openWrapper
            # For building OTP by hand:
            pkgs.ncurses
            pkgs.libxml2
            pkgs.libxslt
          ] ++ (pkgs.lib.optionals pkgs.stdenv.isLinux [perf mkflamegraph pkgs.perf-test pkgs.hotspot]);
          shellHook = ''
            export CC=${pkgs.clang}/bin/clang

            # enable profiling support with the JIT on Linux
            export RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS="+JPperf true"

            # This is used by perf-test. I can't tell what sets it in the first place :/
            unset SIZE
          '';
        };
      });
}
