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
          openWrapper = pkgs.writeShellScriptBin "open" ''
            exec "${pkgs.xdg-utils}/bin/xdg-open" "$@" 
          '';
          erlangPkgs = pkgs.beam.packages.erlang_26;
          # rebar's package runs its whole test suite, running for minutes :/
          rebar3 = erlangPkgs.rebar3.overrideAttrs (final: prev: { doCheck = false; });
        in
        pkgs.mkShell {
          packages = [
            erlangPkgs.erlang
            erlangPkgs.elixir
            rebar3
            # Building OTP:
            pkgs.ncurses
            pkgs.libxml2
            pkgs.libxslt
            # Building running and documenting rabbit
            pkgs.gnumake
            pkgs.mandoc
            pkgs.openssl
            pkgs.python3
            perf-test
            # Kubernetes testing
            pkgs.ytt
            pkgs.kubectl
            (pkgs.google-cloud-sdk.withExtraComponents [pkgs.google-cloud-sdk.components.gke-gcloud-auth-plugin])
          ] ++ (pkgs.lib.optionals pkgs.stdenv.isLinux [openWrapper pkgs.linuxPackages-libre.perf pkgs.hotspot]);
          shellHook = ''
            # This is used by perf-test. I can't tell what sets it in the first place :/
            unset SIZE
          '';
          MAKEFLAGS = "--jobs=16 --no-print-directory";
        });
    };
}
