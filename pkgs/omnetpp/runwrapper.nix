{
  stdenv,
  lib,

  omnetpp
}:

{
  buildInputs ? [],
  runtimeDeps ? [],

  changeDir ? null
}:

stdenv.mkDerivation {
  name = "opp_run";

  buildInputs = buildInputs ++ [
    omnetpp
  ];

  phases = [ "buildPhase" ];

  buildPhase = ''
    runHook preBuild

    opp_run=${omnetpp}/bin/opp_run

    IFS=':' read -a nix_omnetpp_libs <<< "$NIX_OMNETPP_LIBS"
    lib_options=''${nix_omnetpp_libs[@]/#/-l }

    cat << EOF > $out
    export NEDPATH="$NEDPATH"
    export OMNETPP_IMAGE_PATH="$NEDPATH"

    export PATH="\''${PATH:+\''${PATH}:}${lib.makeBinPath runtimeDeps}"

    '' + (lib.optionalString (changeDir != null) ''
    cd "${changeDir}"
    '') + ''

    $opp_run $lib_options \$@
    EOF

    chmod +x $out

    runHook postBuild
  '';
}
