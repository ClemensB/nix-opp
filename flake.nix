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
            };

        packages.x86_64-linux = {
          inherit (pkgs) omnetpp osgearth example-project;
        };
      };
}
