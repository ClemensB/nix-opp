{
  stdenv,
  lib,

  omnetpp
}:

{
  buildInputs ? [],
  runtimeDeps ? [],

  changeDir ? null,
  withGUI ? false
}:

let
  myOmnetpp = if withGUI then omnetpp.minimal-gui else omnetpp.minimal;
in
  stdenv.mkDerivation {
    name = "opp_run";

    buildInputs = buildInputs ++ [
      myOmnetpp
    ];

    phases = [ "buildPhase" ];

    buildPhase = ''
      runHook preBuild

      opp_run=${myOmnetpp}/bin/opp_run

      IFS=':' read -a nix_omnetpp_libs <<< "$NIX_OMNETPP_LIBS"
      lib_options=''${nix_omnetpp_libs[@]/#/-l }

      cat << EOF > $out
      export NEDPATH="$NEDPATH"
      export OMNETPP_IMAGE_PATH="$NEDPATH"

      '' + (lib.optionalString ((builtins.length runtimeDeps) > 0) ''
      export PATH="\''${PATH:+\''${PATH}:}${lib.makeBinPath runtimeDeps}"
      '') + ''

      '' + (lib.optionalString (changeDir != null) ''
      cd "${changeDir}"
      '') + ''

      $opp_run $lib_options \$@
      EOF

      chmod +x $out

      runHook postBuild
    '';
  }
