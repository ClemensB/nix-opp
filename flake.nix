{
  description = "A Nix flake for the OMNeT++ ecosystem";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-20.03;
  };

  outputs = { self, nixpkgs }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; overlays = [ self.overlay ]; };

      fix = f: let x = f x; in x;
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

              omnetpp562 = final.libsForQt5.callPackage ./pkgs/omnetpp rec {
                version = "5.6.2";

                src = final.fetchurl {
                  url = "https://github.com/omnetpp/omnetpp/releases/download/omnetpp-5.6.2/omnetpp-5.6.2-src-linux.tgz";
                  sha256 = "sha256-l7DWUzmEhtwXK4Qnb4Xv1izQiwKftpnI5QeqDpJ3G2U=";
                };
              };

              omnetpp60pre8 = final.libsForQt5.callPackage ./pkgs/omnetpp rec {
                version = "6.0pre8";

                src = final.fetchurl {
                  url = "https://github.com/omnetpp/omnetpp/releases/download/omnetpp-6.0pre8/omnetpp-6.0pre8-src-linux.tgz";
                  sha256 = "09np7gxgyy81v7ld14yv2738laj67966q7d7r4ybrkz01axg1ik5";
                };
              };

              omnetpp = final.omnetpp562;

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

              omnetppModels = final.lib.makeOverridable ({ omnetpp }: fix (self: {
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
                    owner = "sommer";
                    repo = "veins";
                    rev = "a367f827a1348471efa42ae0c95983ff0027453d";
                    sha256 = "sha256-R1qfldxeMVZmjZyJb51kWqyN7Wa+Znt5Az0Wj5ucbSQ=";
                  };
                };

                veins_inet = omnetpp.buildModel {
                  pname = "veins_inet";
                  version = "4.0-git";

                  src = self.veins.src;
                  sourceRoot = "source/subprojects/veins_inet";

                  propagatedBuildInputs = with self; [
                    inet
                    veins
                  ];
                };
              })) { omnetpp = final.omnetpp; };
            };

        packages.x86_64-linux = {
          inherit (pkgs)
            omnetpp561
            omnetpp562
            omnetpp60pre8
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
