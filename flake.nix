{
  description = "A feature-rich, multi-protocol messaging broker";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
    flamegraph-src = {
      url = "github:brendangregg/FlameGraph";
      flake = false;
    };
  };

  outputs = { nixpkgs, utils, flamegraph-src, ... }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        java = pkgs.openjdk;
        # TODO figure out the graalvm building process...
        perf-test-jar = pkgs.fetchurl {
          url = "https://github.com/rabbitmq/rabbitmq-perf-test/releases/download/v2.19.0/perf-test-2.19.0.jar";
          sha256 = "sha256-kgU/JpS5iPHMR2B+6+fzZT2l/Y1X16+RWCYhSnykrNU=";
        };
        perf-test = pkgs.writeShellScriptBin "perf-test" ''
          ${java}/bin/java -jar ${perf-test-jar} "$@"
        '';
        inherit (pkgs.linuxPackages-libre) perf;
        openWrapper = pkgs.writeShellScriptBin "open" ''
          exec "${pkgs.xdg-utils}/bin/xdg-open" "$@" 
        '';
        mkflamegraph = pkgs.writeShellScriptBin "mkflamegraph" ''
          PERF_DATA_FILE="''${1:-perf.data}"
          FLAMEGRAPH_FILE="''${2:-flamegraph.svg}"
          WORK_DIR=`mktemp -d`
          if [[ ! "$WORK_DIR" || ! -d "$WORK_DIR" ]]; then
            echo "Could not create temp dir"
            exit 1
          fi
          function cleanup {
            rm -rf "$WORK_DIR"
          }
          trap cleanup EXIT

          ${perf}/bin/perf script --input="$PERF_DATA_FILE" > "$WORK_DIR"/out.perf
          # Collapse multiline stacks into single lines
          ${pkgs.perl}/bin/perl ${flamegraph-src + /stackcollapse-perf.pl} "$WORK_DIR"/out.perf > "$WORK_DIR"/out.folded
          # Merge scheduler profile data
          ${pkgs.gnused}/bin/sed -e 's/^[0-9]\+_//' "$WORK_DIR"/out.folded > "$WORK_DIR"/out.folded_sched
          # Create the SVG file
          ${pkgs.perl}/bin/perl ${flamegraph-src + /flamegraph.pl} --title="CPU Flame Graph" "$WORK_DIR"/out.folded_sched > "$FLAMEGRAPH_FILE"
        '';
      in {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.gnumake
            pkgs.mandoc
            pkgs.openssl
            pkgs.python3
            java
            openWrapper
            # For building OTP by hand:
            pkgs.ncurses
            pkgs.libxml2
            pkgs.libxslt
            # Kubernetes testing
            pkgs.ytt
            pkgs.kubectl
            (pkgs.google-cloud-sdk.withExtraComponents [pkgs.google-cloud-sdk.components.gke-gcloud-auth-plugin])
          ] ++ (pkgs.lib.optionals pkgs.stdenv.isLinux [perf mkflamegraph perf-test pkgs.hotspot]);
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
