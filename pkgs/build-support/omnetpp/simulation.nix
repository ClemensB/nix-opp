{
  lib,
  stdenv,

  runCommand,
  symlinkJoin,
  singularity-tools,

  omnetpp,

  mkOmnetppRunwrapper
}:

{
  name,

  src,
  sourceRoot ? "",

  propagatedBuildInputs ? [],

  runtimeDeps ? [],

  resultBasename ? "General",

  ...
} @ attrs:

let
  inherit (builtins) head tail;

  self = stdenv.mkDerivation ({
    # inherit name src sourceRoot propagatedBuildInputs;

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
        inherit runtimeDeps;
        changeDir = self;
        extraNedDirs = [ self ];
      };

      runList =
        let
          listPath = runCommand "${self.name}-runs" {} ''
            ${self.run} -c "General" -q runs | sed -nE 's/^Run ([0-9]+)/\1/p' > "$out"
          '';
          listContents = builtins.readFile listPath;
          listLines = builtins.filter (line: line != "") (lib.splitString "\n" listContents);

          # Parses a single line of the run list to an attrset
          parseLine = line:
            let
              split = (lib.splitString ": " line);
              parseItervar = var: let
                  split' = lib.splitString "=" var;
                in
                  { name = lib.removePrefix "\$" (builtins.head split'); value = builtins.head (builtins.tail split'); };
            in
              {
                run = builtins.head split;
                itervars = builtins.listToAttrs (builtins.map parseItervar (lib.splitString ", " (builtins.head (builtins.tail split))));
              };
        in
          listLines; # builtins.map parseLine listLines;

      runListWithConfig =
        let
          listPath = runCommand "${self.name}-runs" {} ''
            ${self.run} -c "General" -q runconfig | sed -nE -e 's/^Run ([0-9]+)/\1/p' -e 's/^\t(.+) = (.+)$/\1, \2/p' > "$out"
          '';
          listContents = builtins.readFile listPath;
          listLines = builtins.filter (line: line != "") (lib.splitString "\n" listContents);

          readSections = readSections' [];
          readSections' = ys: mkSection: isHdr: xs:
            if xs == []
              then
                ys
              else
                readSection ys mkSection isHdr (head xs) (tail xs);

          readSection = readSection' [];
          readSection' = zs: ys: mkSection: isHdr: hdr: xs:
            if xs == []
              then
                ys ++ [(mkSection hdr zs)]
              else
                if isHdr (head xs)
                  then
                    readSections' (ys ++ [(mkSection hdr zs)]) mkSection isHdr xs
                  else
                    readSection' (zs ++ [(head xs)]) ys mkSection isHdr hdr (tail xs);

          isRunHdr = line: !(builtins.isNull (builtins.match "[[:digit:]]*: .*" line));

          parseRunHdr = line:
            let
              parts = lib.splitString ": " line;
              num = lib.toInt (head parts);
              itervars' = head (tail parts);

              parseItervar = s:
                let
                  parts = lib.splitString "=" s;
                  name = head parts;
                  value = head (tail parts);
                in
                  { inherit name value; };

              itervars = builtins.listToAttrs (builtins.map parseItervar (lib.splitString ", " itervars'));
            in
              { inherit num itervars; };

          parseRunConfig = line:
            let
              parts = lib.splitString ", " line;
              name = head parts;
              value = head (tail parts);
            in
              { inherit name value; };

          mkRun = hdr: body: parseRunHdr hdr // {
            config = builtins.map parseRunConfig body;
          };
        in
          readSections mkRun isRunHdr listLines;

      results =
        let
          mkRunDerivation = config: repetition:
            let
              printConfigOpt = { name, value }: "${name} = ${value}\n";
              mkOmnetppConfig = cfgname: config:
                ("[${cfgname}]\n" + lib.concatStrings (builtins.map printConfigOpt config));

              omnetppConfig = mkOmnetppConfig "General" config;
              omnetppIni = builtins.toFile "omnetpp.ini" omnetppConfig;
              configHash = builtins.hashString "sha1" omnetppConfig;

              runwrapperHash = builtins.hashString "sha1" "${self.run}";

              # We build our own unique runid which shall be fully deterministic, i.e. uniquely defined by the simulations' inputs.
              # A run's result should only depend on the used runwrapper (which includes all dependencies)
              # as well as simulation configuration and repetition.
              runid = "General-${runwrapperHash}-${configHash}-${repetition}";

              resultdir= "\${resultdir}";
            in
              runCommand "${self.name}-${runid}" {} ''
                mkdir "$out"
                substitute "${omnetppIni}" "omnetpp.ini" --replace 'results/' "$out/"
                ${self.run} -f "omnetpp.ini" -c "General" -u Cmdenv -r ${repetition} --result-dir "$out"

                # Rewrite run id and strip timestamp and process id to enforce determinism
                sed -i -E \
                  -e '/^run/ s/[^ ]+$/${runid}/' \
                  -e '/^attr datetime/ s/[^ ]+$/19700101-00:00:00/' \
                  -e '/^attr processid/ s/[0-9]+$/1/' \
                  "$out"/*

                # Regenerate vector index files
                ${omnetpp}/bin/opp_scavetool i "$out"/*.vec
              '';

          # Renames a simulation run's output files to match match the given itervars and mimic
          # an OMNeT++ parameter study while executing simulations fully isolated from one another.
          # This also avoids running a simulation for the same set of parameters twice.
          mkRunDerivationForItervars = { config, itervars, num }:
            let
              repetition = itervars."\$repetition";
              itervars' = builtins.removeAttrs itervars [ "\$repetition" ];

              rawResults = mkRunDerivation config repetition;

              printItervar = name: value: "${lib.removePrefix "\$" name}=${value}";
              itervarsStr' = lib.concatStringsSep "-" (lib.mapAttrsToList printItervar itervars');
              itervarsSep = lib.optionalString ((builtins.length (lib.attrValues itervars')) > 0) "-";
              itervarsStr = itervarsSep + itervarsStr';
            in
              runCommand "${rawResults.name}-with-itervars" {} ''
                mkdir "$out"
                for path in "${rawResults}"/*; do
                  filename="''${path##*/}"
                  ext="''${filename##*.}"
                  name="''${filename%.*}"
                  cfgname="''${name%%-#${repetition}}"
                  ln -s "$path" "$out/${resultBasename}${itervarsStr}-#${repetition}.$ext"
                done
              '';

          resultDerivations = builtins.map mkRunDerivationForItervars self.runListWithConfig;
        in
          symlinkJoin {
            name = "${self.name}-results";
            paths = resultDerivations;
          };

      singularity = singularity-tools.buildImage {
        name = "${name}-singularity-image";
        diskSize = 4096;
        runScript = "#!${stdenv.shell}\nexec ${self.run} $@";
      };
    };
  } // attrs);
in
  self
