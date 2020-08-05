{
  description = "A Nix flake for the OMNeT++ ecosystem";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-20.03;
  };

  outputs = { self, nixpkgs }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; overlays = [ self.overlay ]; };
    in
      {
        overlay = final: prev:
          let
            callPackage = nixpkgs.lib.callPackageWith final;
          in
            {
              osgearth = callPackage ./pkgs/osgearth {};

              omnetpp = final.libsForQt5.callPackage ./pkgs/omnetpp {};
              buildOmnetppModel = callPackage ./pkgs/omnetpp/model.nix {};

              example-project = final.buildOmnetppModel {
                pname = "example-project";
                version = "0.0.1";

                src = "${self}/example-project";
              };

              inet = final.buildOmnetppModel {
                pname = "inet";
                version = "4.2.0";

                src = final.fetchFromGitHub {
                  owner = "inet-framework";
                  repo = "inet";
                  rev = "cb6c37b3dcb76b0cecf584e87e777d965bf1ca6c";
                  sha256 = "sha256-oxCz5Dwx5/NeINPAaXmx6Ie/gcMLu9pmVb2A35e0C6s=";
                };

                extraIncludeDirs = [ "src" ];
              };

              veins = final.buildOmnetppModel {
                pname = "veins";
                version = "5.0-git";

                src = final.fetchFromGitHub {
                  owner = "sommer";
                  repo = "veins";
                  rev = "c6e7ac7c04d0767fb31376d6f7f106ac85c1e4bb";
                  sha256 = "sha256-4wxKYVtVWhhjt9vwHJcRFh/J8dclOqKtCtKZQZHCn58=";
                };
              };

              veins_inet = final.buildOmnetppModel {
                pname = "veins_inet";
                version = "4.0-git";

                src = final.fetchFromGitHub {
                  owner = "sommer";
                  repo = "veins";
                  rev = "c6e7ac7c04d0767fb31376d6f7f106ac85c1e4bb";
                  sha256 = "sha256-4wxKYVtVWhhjt9vwHJcRFh/J8dclOqKtCtKZQZHCn58=";
                };

                sourceRoot = "source/subprojects/veins_inet";

                buildInputs = with final; [
                  inet
                  veins
                ];
              };
            };

        packages.x86_64-linux = {
          inherit (pkgs)
            osgearth

            omnetpp

            inet
            veins
            veins_inet

            example-project;
        };
      };
}
