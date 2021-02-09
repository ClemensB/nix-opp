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
            omnetpp60pre10 = final.libsForQt5.callPackage ./pkgs/omnetpp/6.0pre10.nix {};

            omnetpp = final.omnetpp562;
            omnetppModels = final.omnetpp.models;

            sumo = final.sumo180;
            sumo120 = final.callPackage ./pkgs/sumo/1.2.0.nix {};
            sumo150 = final.callPackage ./pkgs/sumo/1.5.0.nix {};
            sumo160 = final.callPackage ./pkgs/sumo/1.6.0.nix {};
            sumo170 = final.callPackage ./pkgs/sumo/1.7.0.nix {};
            sumo180 = final.callPackage ./pkgs/sumo/1.8.0.nix {};
          };

        packages.x86_64-linux = {
          inherit (pkgs)
            osgearth

            omnetpp
            omnetpp561
            omnetpp562
            omnetpp60pre10

            sumo
            sumo120
            sumo150
            sumo160
            sumo170
            sumo180;

          inherit (pkgs.omnetppModels)
            #example-project
            inet
            inet411
            inet412
            inet420

            veins
            veins50;
        };

        devShell.x86_64-linux = pkgs.mkShell {
          buildInputs = [
            (pkgs.python3.withPackages (ps: [
              self.packages.x86_64-linux.sumo.sumolib
              self.packages.x86_64-linux.omnetpp60pre9.pythonPackage
            ]))
          ];
        };

        apps.x86_64-linux = {
          omnetpp561 = {
            type = "app";
            program = "${self.packages.x86_64-linux.omnetpp561.ide}/bin/omnetpp-with-tools";
          };

          omnetpp562 = {
            type = "app";
            program = "${self.packages.x86_64-linux.omnetpp562.ide}/bin/omnetpp-with-tools";
          };

          omnetpp60pre10 = {
            type = "app";
            program = "${self.packages.x86_64-linux.omnetpp60pre10.ide}/bin/omnetpp-with-tools";
          };

          omnetpp = self.apps.x86_64-linux.omnetpp562;
        };

        defaultApp.x86_64-linux = self.apps.x86_64-linux.omnetpp;
      };
}
