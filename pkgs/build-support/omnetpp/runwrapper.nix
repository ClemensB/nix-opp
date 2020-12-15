{
  stdenv,
  lib,

  omnetpp
}:

{
  buildInputs ? [],
  runtimeDeps ? [],

  changeDir ? null,
  extraNedDirs ? []
}:

stdenv.mkDerivation {
  name = "opp_run";

  buildInputs = buildInputs ++ [
    omnetpp
  ];

  phases = [ "buildPhase" ];

  buildPhase = ''
    runHook preBuild

    opp_run=${omnetpp.run}/bin/opp_run

    IFS=':' read -a nix_omnetpp_libs <<< "$NIX_OMNETPP_LIBS"
    lib_options=''${nix_omnetpp_libs[@]/#/-l }

    cat << EOF > $out
    #!$SHELL
    export NEDPATH="$NEDPATH"
    export OMNETPP_IMAGE_PATH="$OMNETPP_IMAGE_PATH"

    '' + (lib.optionalString ((builtins.length runtimeDeps) > 0) ''
    export PATH="\''${PATH:+\''${PATH}:}${lib.makeBinPath runtimeDeps}"
    '') + ''

    '' + (lib.optionalString (changeDir != null) ''
    cd "${changeDir}"
    '') + ''

    '' + (lib.optionalString (extraNedDirs != []) ''
    export NEDPATH="\''${NEDPATH:+\''${NEDPATH};}${lib.concatStringsSep ";" extraNedDirs}"
    '') + ''

    $opp_run $lib_options \$@
    EOF

    chmod +x $out

    runHook postBuild
  '';
}
