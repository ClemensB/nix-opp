{ version
, veins_inet-version
, rev
, sha256
}:

{ lib
, buildOmnetppModel
, fetchFromGitHub

, inet

, veins-src ? (fetchFromGitHub {
    owner = "sommer";
    repo = "veins";
    inherit rev sha256;
  })
}:

let
  self = buildOmnetppModel {
    pname = "veins";
    inherit version;

    src = veins-src;

    passthru = {
      veins_inet = buildOmnetppModel {
        pname = "veins_inet";
        version = veins_inet-version;

        src = "${veins-src}/subprojects/veins_inet";

        propagatedBuildInputs = [ self inet ];
      };
    };

    meta = {
      description = "Veins is an open source framework for running vehicular network simulations.";
      homepage = "https://veins.car2x.org/";
      license = lib.licenses.gpl2;
    };
  };
in
  self
