{ version
, rev
, sha256
}:

{ lib
, buildOmnetppModel
, fetchFromGitHub
, python3
}:

buildOmnetppModel {
  pname = "inet";
  inherit version;

  src = fetchFromGitHub {
    owner = "inet-framework";
    repo = "inet";
    inherit rev sha256;

    fetchSubmodules = true;
  };

  nativeBuildInputs = [ python3 ];

  extraIncludeDirs = [ "src" ];

  preBuild = ''
    patchShebangs bin
  '';

  meta = {
    description = "The INET framework is an open-source communication networks simulation package, written for the OMNEST/OMNeT++ simulation system.";
    homepage = "https://inet.omnetpp.org/";
  };
}
