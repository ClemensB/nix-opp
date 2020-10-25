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
          {
            osgearth = final.callPackage ./pkgs/osgearth {};

            omnetpp561 = final.libsForQt5.callPackage ./pkgs/omnetpp/5.6.1.nix {};
            omnetpp562 = final.libsForQt5.callPackage ./pkgs/omnetpp/5.6.2.nix {};
            omnetpp60pre8 = final.libsForQt5.callPackage ./pkgs/omnetpp/6.0pre8.nix {};

            omnetpp = final.omnetpp562;
            omnetppModels = final.omnetpp.models;

            sumo = final.callPackage ./pkgs/sumo {};
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
            omnetpp561
            omnetpp562
            omnetpp60pre8

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
            program = "${self.packages.x86_64-linux.omnetpp561.ide}/bin/omnetpp";
          };

          omnetpp562 = {
            type = "app";
            program = "${self.packages.x86_64-linux.omnetpp562.ide}/bin/omnetpp";
          };

          omnetpp60pre8 = {
            type = "app";
            program = "${self.packages.x86_64-linux.omnetpp60pre8.ide}/bin/omnetpp";
          };

          omnetpp = self.apps.x86_64-linux.omnetpp562;
        };

        defaultApp.x86_64-linux = self.apps.x86_64-linux.omnetpp;
      };
}
