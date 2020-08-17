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

              sumo = callPackage ./pkgs/sumo {};
              sumo-minimal = final.sumo.override {
                withEigen = false;
                withFfmpeg = false;
                withGDAL = false;
                withGL2PS = false;
                withGUI = false;
                withOSG = false;
                withProj = false;
                withSWIG = false;
              };

              omnetppModels = final.lib.makeOverridable ({ omnetpp }: {
                example-project = omnetpp.buildModel {
                  pname = "example-project";
                  version = "0.0.1";

                  src = "${self}/example-project";
                };

                inet = omnetpp.buildModel {
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

                veins = omnetpp.buildModel {
                  pname = "veins";
                  version = "5.0-git";

                  src = final.fetchFromGitHub {
                    owner = "ClemensB";
                    repo = "veins";
                    rev = "e9fcb936f17f9938be8d8f46be2d086f05744bf8";
                    sha256 = "sha256-pAJ9IiKry+uwVz3UizzJ2fzhmucU7b2Gm/RtdvHc4oI=";
                  };
                };

                veins_inet = omnetpp.buildModel {
                  pname = "veins_inet";
                  version = "4.0-git";

                  src = final.veins.src;
                  sourceRoot = "source/subprojects/veins_inet";

                  buildInputs = with final; [
                    inet
                    veins
                  ];
                };
              }) { omnetpp = final.omnetpp; };
            };

        packages.x86_64-linux = {
          inherit (pkgs)
            omnetpp
            osgearth
            sumo
            sumo-minimal;

          inherit (pkgs.omnetppModels)
            example-project
            inet
            veins
            veins_inet;
        };

        apps.x86_64-linux = {
          omnetpp = {
            type = "app";
            program = "${self.packages.x86_64-linux.omnetpp.ide}/bin/omnetpp";
          };
        };

        defaultApp.x86_64-linux = self.apps.x86_64-linux.omnetpp;
      };
}
