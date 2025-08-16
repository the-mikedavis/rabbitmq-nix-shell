{
  description = "A feature-rich, multi-protocol messaging broker";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
      forEachSystem = lib.genAttrs lib.systems.flakeExposed;
    in
    {
      devShell = forEachSystem (system:
        let
          pkgs = import nixpkgs { inherit system; };
          perf-test-jar = pkgs.fetchurl {
            url = "https://github.com/rabbitmq/rabbitmq-perf-test/releases/download/v2.20.0/perf-test-2.20.0.jar";
            sha256 = "5PIjk0B8RCU+c5a/O+pV+vAyoYvabr5F3/fr/O60UF4=";
          };
          perf-test = pkgs.writeShellScriptBin "perf-test" ''
            ${pkgs.openjdk}/bin/java -jar ${perf-test-jar} "$@"
          '';
          stream-perf-test-jar = pkgs.fetchurl {
            url = "https://github.com/rabbitmq/rabbitmq-stream-perf-test/releases/download/v1.5.0/stream-perf-test-1.5.0.jar";
            sha256 = "QPlsNAPmKaziITuQ2CLYSAireIWlYw/CrsxmHx2gmj8=";
          };
          stream-perf-test = pkgs.writeShellScriptBin "stream-perf-test" ''
            ${pkgs.openjdk}/bin/java -jar ${stream-perf-test-jar} "$@"
          '';
          openWrapper = pkgs.writeShellScriptBin "open" ''
            exec "${pkgs.xdg-utils}/bin/xdg-open" "$@" 
          '';
          erlangPkgs = pkgs.beam.packages.erlang_27;
          /*
          # Build Erlang/OTP 28 before it becomes available in nixpkgs.
          erlang_28 = pkgs.beam.beamLib.callErlang ./28.nix {
            parallelBuild = true;
            wxSupport = false;
            systemdSupport = false;
          };
          # Use that for all other packages.
          erlangPkgs = pkgs.beam.packagesWith erlang_28;
          */
          # rebar's package runs its whole test suite, running for minutes :/
          rebar3 = erlangPkgs.rebar3.overrideAttrs (final: prev: { doCheck = false; });
        in
        pkgs.mkShell {
          packages = [
            erlangPkgs.erlang
            erlangPkgs.elixir
            rebar3
            erlangPkgs.erlfmt
            # Building OTP:
            pkgs.ncurses
            pkgs.libxml2
            pkgs.libxslt
            pkgs.pkg-config
            pkgs.openssl
            # Building running and documenting rabbit
            pkgs.gnumake
            pkgs.mandoc
            pkgs.python3
            perf-test
            stream-perf-test
            pkgs.p7zip
            # Kubernetes testing
            # pkgs.ytt
            # pkgs.kubectl
            # ... on AWS
            pkgs.awscli2
          ] ++ (pkgs.lib.optionals pkgs.stdenv.isLinux [openWrapper pkgs.linuxPackages-libre.perf]);
          shellHook = ''
            # This is used by perf-test. I can't tell what sets it in the first place :/
            unset SIZE
          '';
          MAKEFLAGS = "--jobs=16 --no-print-directory";
          # ./configure --with-ssl=$OTP_WITH_SSL_PATH --with-ssl-incl=$OTP_WITH_SSL_INCL_PATH
          OTP_WITH_SSL_PATH = lib.getOutput "out" pkgs.openssl;
          OTP_WITH_SSL_INCL_PATH = lib.getDev pkgs.openssl;
        });
    };
}
