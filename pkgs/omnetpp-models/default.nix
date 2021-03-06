{ pkgs
# , stdenv
, omnetpp
, overrides ? (final: prev: {})
}:

let
  inherit (pkgs) lib;
  inherit (lib) extends fix' makeOverridable;

  models = (self:
    let
      callPackage = pkgs.newScope self;

      # Copied from python-packages.nix
      makeOverridableOmnetppModel = f: origArgs:
        let
          ff = f origArgs;
          overrideWith = newArgs: origArgs // (if pkgs.lib.isFunction newArgs then newArgs origArgs else newArgs);
        in
          if builtins.isAttrs ff then (ff // {
            overrideOmnetppAttrs = newArgs: makeOverridableOmnetppModel f (overrideWith newArgs);
          })
          else if builtins.isFunction ff then {
            overrideOmnetppAttrs = newArgs: makeOverridableOmnetppModel f (overrideWith newArgs);
            __functor = self: ff;
          }
          else ff;
    in
      {
        buildOmnetppModel = makeOverridableOmnetppModel (makeOverridable (callPackage ../build-support/omnetpp/model.nix {}));
        mkOmnetppRunwrapper = callPackage ../build-support/omnetpp/runwrapper.nix {};
        mkOmnetppSimulation = callPackage ../build-support/omnetpp/simulation.nix {};

        veins = self.veins50;
        veins50 = callPackage ./veins/5.0.nix { inet = self.inet411; };
        veins51 = callPackage ./veins/5.1.nix { inet = self.inet421; };

        inet = self.inet420;
        inet411 = callPackage ./inet/4.1.1.nix {};
        inet412 = callPackage ./inet/4.1.2.nix {};
        inet420 = callPackage ./inet/4.2.0.nix {};
        inet421 = callPackage ./inet/4.2.1.nix {};
      }
  );
in
  fix' (extends overrides models)
