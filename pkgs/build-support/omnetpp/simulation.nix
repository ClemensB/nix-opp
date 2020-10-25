{
  lib,
  stdenv,

  runCommand,
  singularity-tools,

  mkOmnetppRunwrapper
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
      run = mkOmnetppRunwrapper {
        buildInputs = [ self ] ++ propagatedBuildInputs;
        changeDir = self;
      };

      results = runCommand "${name}-results" {} ''
        ${self.run} --result-dir="$out"
      '';

      singularity = singularity-tools.buildImage {
        name = "${name}-singularity-image";
        diskSize = 4096;
        runScript = "#!${stdenv.shell}\nexec ${self.run} $@";
      };
    };
  };
in
  self
