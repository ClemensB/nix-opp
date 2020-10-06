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

              omnetpp561 = final.libsForQt5.callPackage ./pkgs/omnetpp rec {
                version = "5.6.1";

                src = final.fetchurl {
                  url = "https://github.com/omnetpp/omnetpp/releases/download/omnetpp-5.6.1/omnetpp-5.6.1-src-linux.tgz";
                  sha256 = "1hfb92zlygj12m9vx2s9x4034s3yw9kp26r4zx44k4x6qdhyq5vz";
                };
              };
              omnetpp561Full = final.omnetpp561.full;

              omnetpp562 = final.libsForQt5.callPackage ./pkgs/omnetpp rec {
                version = "5.6.2";

                src = final.fetchurl {
                  url = "https://github.com/omnetpp/omnetpp/releases/download/omnetpp-5.6.2/omnetpp-5.6.2-src-linux.tgz";
                  sha256 = "sha256-l7DWUzmEhtwXK4Qnb4Xv1izQiwKftpnI5QeqDpJ3G2U=";
                };
              };
              omnetpp562Full = final.omnetpp562.full;

              omnetpp60pre8 = final.libsForQt5.callPackage ./pkgs/omnetpp rec {
                version = "6.0pre8";

                src = final.fetchurl {
                  url = "https://github.com/omnetpp/omnetpp/releases/download/omnetpp-6.0pre8/omnetpp-6.0pre8-src-linux.tgz";
                  sha256 = "09np7gxgyy81v7ld14yv2738laj67966q7d7r4ybrkz01axg1ik5";
                };
              };
              omnetpp60pre8Full = final.omnetpp60pre8.full;

              omnetpp = final.omnetpp562;
              omnetppFull = final.omnetpp.full;

              omnetppModels = final.omnetpp.models;

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
            };

        packages.x86_64-linux = {
          inherit (pkgs)
            osgearth

            omnetpp
            omnetppFull
            omnetpp561
            omnetpp561Full
            omnetpp562
            omnetpp562Full
            omnetpp60pre8
            omnetpp60pre8Full

            sumo
            sumo-minimal;

          inherit (pkgs.omnetppModels)
            #example-project
            inet
            inet411
            inet412
            inet420

            veins
            veins50;
        };

        apps.x86_64-linux = {
          omnetpp561 = {
            type = "app";
            program = "${self.packages.x86_64-linux.omnetpp561.full.ide}/bin/omnetpp";
          };

          omnetpp562 = {
            type = "app";
            program = "${self.packages.x86_64-linux.omnetpp562.full.ide}/bin/omnetpp";
          };

          omnetpp60pre8 = {
            type = "app";
            program = "${self.packages.x86_64-linux.omnetpp60pre8.full.ide}/bin/omnetpp";
          };

          omnetpp = self.apps.x86_64-linux.omnetpp562;
        };

        defaultApp.x86_64-linux = self.apps.x86_64-linux.omnetpp;
      };
}
