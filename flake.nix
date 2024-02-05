{
  description = "A feature-rich, multi-protocol messaging broker";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, utils, ... }:
    utils.lib.eachDefaultSystem (system:
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
      in {
        devShells.default = pkgs.mkShell {
          packages = [
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
        };
      });
}
