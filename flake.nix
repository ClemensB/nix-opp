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
              omnetpp = final.libsForQt5.callPackage ./pkgs/omnetpp {};
              osgearth = callPackage ./pkgs/osgearth {};

              example-project = callPackage ./pkgs/omnetpp/model.nix {
                pname = "example-project";
                version = "0.0.1";

                src = "${self}/example-project";
              };

              inet = callPackage ./pkgs/omnetpp/model.nix {
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
            };

        packages.x86_64-linux = {
          inherit (pkgs) omnetpp osgearth example-project inet;
        };
      };
}
