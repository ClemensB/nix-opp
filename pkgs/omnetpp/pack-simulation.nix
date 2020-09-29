{
  lib,
  stdenv,

  runCommand,
  singularity-tools,

  omnetpp
}:

{
  name,

  src,
  sourceRoot ? "",

  propagatedBuildInputs ? []
} @ attrs:

let
  self = stdenv.mkDerivation {
    inherit name src sourceRoot propagatedBuildInputs;

    phases = [ "unpackPhase" "patchPhase" "installPhase" ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp -r . $out

      runHook postInstall
    '';

    passthru = {
      runwrapper = omnetpp.makeRunwrapper {
        buildInputs = [ self ] ++ propagatedBuildInputs;
        changeDir = self;
      };

      results = runCommand "${name}-results" {} ''
        ${self.runwrapper} --result-dir="$out"
      '';

      singularity = singularity-tools.buildImage {
        name = "${name}-singularity-image";
        diskSize = 4096;
        runScript = "#!${stdenv.shell}\nexec ${self.runwrapper} $@";
      };
    };
  };
in
  self
