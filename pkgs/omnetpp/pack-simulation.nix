{
  lib,
  stdenv
}:

{
  name,

  src,
  sourceRoot ? ""
} @ attrs:

stdenv.mkDerivation {
  inherit name src sourceRoot;

  phases = [ "unpackPhase" "patchPhase" "installPhase" ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r . $out

    runHook postInstall
  '';
}
