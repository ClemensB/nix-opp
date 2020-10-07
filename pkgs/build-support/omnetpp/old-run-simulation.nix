{
  lib,

  stdenv,

  omnetpp
}:

{
  name,

  nativeBuildInputs ? [],

  config ? {},
  configname,

  ...
} @ attrs:

let
  configParamsList = lib.attrsets.mapAttrsToList (option: value: "--${option}=${value}") config;
  configParams = lib.strings.concatStringsSep " " configParamsList;

in stdenv.mkDerivation ((builtins.removeAttrs attrs [ "config" "configname" ]) // {
  nativeBuildInputs = nativeBuildInputs ++ [
    omnetpp
  ];

  phases = [ "unpackPhase" "patchPhase" "buildPhase" ];

  buildPhase = ''
    runHook preBuild

    IFS=':' read -a nix_omnetpp_libs <<< "$NIX_OMNETPP_LIBS"
    lib_options=''${nix_omnetpp_libs[@]/#/-l }

    opp_runall opp_run $lib_options \
      -u Cmdenv \
      --result-dir $out \
      ${configParams} \
      -c ${configname}

    runHook postBuild
  '';
})
