{
  description = "A Nix flake with packages related to OMNeT++";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs;
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

              omnetpp561 = final.libsForQt5.callPackage ./pkgs/omnetpp/5.6.1.nix {};
              omnetpp561Full = final.omnetpp561.full;

              omnetpp562 = final.libsForQt5.callPackage ./pkgs/omnetpp/5.6.2.nix {};
              omnetpp562Full = final.omnetpp562.full;

              omnetpp60pre8 = final.libsForQt5.callPackage ./pkgs/omnetpp/6.0pre8.nix {};
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
