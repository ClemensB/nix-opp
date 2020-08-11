{
  lib,
  makeWrapper,
  stdenv,
  writeScript,

  omnetpp,
  xmlstarlet
}:

{
  name ? "${attrs.pname}-${attrs.version}",

  pname,
  version,

  buildInputs ? [],
  nativeBuildInputs ? [],

  enableParallelBuilding ? true,
  makeFlags ? [],

  extraIncludeDirs ? [],

  ...
} @ attrs:

stdenv.mkDerivation (attrs // {
  nativeBuildInputs = nativeBuildInputs ++ [
    makeWrapper
    xmlstarlet
  ];

  buildInputs = buildInputs ++ [
    omnetpp
  ];

  configurePhase = ''
    runHook preConfigure

    if [ -f .project ]; then
      project_name="''${PWD##*/}"

      if [ "$project_name" == "source" ]; then
        echo "Project name \"$project_name\" is probably wrong, setting it to package name \"$pname\" instead"
        project_name="$pname"
      fi

      echo "Project name is \"$project_name\""
    else
      echo "OMNet++ project .project not found"
      exit 1
    fi

    makemake_feature_options=
    if [ -f .oppfeatures ]; then
      echo "Found .oppfeatures, running feature tool..."
      opp_featuretool repair
      makemake_feature_options=$(opp_featuretool options)
    fi

    include=()
    bins=()
    libs=()
    exported_libs=()

    # Read .oppbuildspec on how to build the project
    while IFS="|" read source_dir makemake_options; do
        echo "Configuring source directory $source_dir:"
        echo "- IDE Makemake options: $makemake_options"

        output_name=
        is_library=false
        export_include=false
        export_library=false

        local_includes=()

        local_libs=()
        other_options=()

        set -- $makemake_options $makemake_feature_options
        while [[ $# -gt 0 ]]; do
          option="$1"
          case $option in
            -I)
              include_dir="$2"
              local_includes+=("$include_dir")
              shift
              shift
            ;;
            -I*)
              include_dir="''${option:2}"
              local_includes+=("$include_dir")
              shift
            ;;
            -o)
              output_name="$2"
              shift
              shift
            ;;
            --make-so)
              is_library=true
              shift
            ;;
            --meta:export-include-path)
              export_include=true
              shift
            ;;
            --meta:export-library)
              export_library=true
              shift
            ;;
            --meta:recurse | --meta:feature-cflags | --meta:feature-ldflags)
              # Ignore
              shift
            ;;
            --meta:use-exported-libs)
              # Ignore, we always use exported libs
              shift
            ;;
            --meta:*)
              echo "- Unknown meta option ''${option#--meta:}"
              shift
            ;;
            *)
              other_options+=("$1")
              shift
            ;;
          esac
        done

        for extra_include in $extraIncludeDirs; do
          extra_include_resolved=$(realpath --relative-to "$source_dir" "$extra_include")
          local_includes+=("$extra_include_resolved")
        done

        # Add includes for $NEDPATH entries
        ned_includes=()
        IFS=':'; ned_path=($NEDPATH); unset IFS
        for entry in "''${ned_path[@]}"; do
          if [ -d "$entry" ]; then
            ned_includes+=("$entry")
          fi
        done

        if [ -z "$output_name" ]; then
          output_name=$project_name
        fi

        echo "- Include directories: ''${local_includes[@]}"

        if ! $is_library; then
          echo -n "- Executable: "
          output_file_name="$output_name"
        else
          echo -n "- Library: "
          output_file_name="lib$output_name.so"
        fi
        output_file_path="$source_dir/$output_file_name"
        echo "$output_file_path"

        if ! $is_library; then
          bins+=("$output_file_path")
        fi

        if $is_library; then
          libs+=("$output_file_path")
        fi

        if $is_library && $export_library; then
          echo "- Exporting library"
          exported_libs+=("$output_file_path")
        fi

        if $export_include; then
          echo "- Exporting headers"
          for local_include in "''${local_includes[@]}"; do
            local_include_resolved=$(realpath --relative-to "$PWD" "$source_dir/$local_include")
            include+=("$local_include_resolved")
          done
        fi

        echo "- Other options: ''${other_options[@]}"

        makemake_options_new=(
          -o "$output_name"
          ''${local_includes[@]/#/-I }
          ''${ned_includes[@]/#/-I }
          "''${other_options[@]}"
        )

        if $is_library; then
          makemake_options_new+=("--make-so")
        fi
        echo "- Final Makemake options: ''${makemake_options_new[@]}"

        pushd "$source_dir" > /dev/null
          echo "Running opp_makemake in $source_dir..."
          opp_makemake ''${makemake_options_new[@]}
        popd > /dev/null
    done < <(xml sel -t -m "/buildspec/dir[@type='makemake']" -v "@path" -o "|" -v "@makemake-options" -nl .oppbuildspec)

    readarray -t nedfolders < .nedfolders

    nedexclusions=()
    if [ -e .nedexclusions ]; then
      readarray -t nedexclusions < .nedexclusions
    fi

    echo "Configuration summary:"
    echo "- Exported include directories: ''${include[@]}"
    echo "- Exported libraries: ''${libs[@]}"
    echo "- Binaries: ''${bins[@]}"
    echo "- NED folders: ''${nedfolders[@]}"
    echo "- Excluded NED packages: ''${nedexclusions[@]}"

    runHook postConfigure
  '';

  inherit enableParallelBuilding;
  makeFlags = makeFlags ++ [ "MODE=release" ];

  installPhase = ''
    runHook preInstall

    for include_dir in "''${include[@]}"; do
      pushd $include_dir > /dev/null
        mkdir -p "$out/include"
        find . -name '*.h' -exec cp --parents '{}' "$out/include" \;
      popd > /dev/null
    done

    for bin in "''${bins[@]}"; do
      mkdir -p "$out/bin"
      cp $bin "$out/bin"
      wrapProgram "$out/bin/''${bin##*/}" \
        --set NEDPATH "''${NEDPATH}''${NEDPATH:+:}$out/share/omnetpp/ned"
    done

    for lib in "''${libs[@]}"; do
      mkdir -p "$out/lib"
      cp $lib "$out/lib"
    done

    for nedfolder in "''${nedfolders[@]}"; do
      pushd $nedfolder > /dev/null
        package_name=.
        target_nedpath_base="share/omnetpp/ned"

        if [ -f package.ned ]; then
          while read package; do
            package_name=$package
            target_nedpath_base="share/omnetpp/ned/''${package//./\/}"
          done < <(sed -En 's/package\s+([\a-z_.]+);/\1/p' package.ned)

          # Remove package declaration
          # sed -Ei '/package\s+([\a-z_.]+);/d' package.ned
        fi

        target_nedpath="$out/$target_nedpath_base"

        echo "Installing NEDs from $nedfolder for package $package_name to $target_nedpath_base..."
        mkdir -p "$target_nedpath"
        find . \( -name '*.ned' -or -name '*.msg' \) -exec cp --parents '{}' "$target_nedpath" \;
      popd > /dev/null
    done

    echo "Removing exluded NED packages..."
    for package in "''${nedexclusions[@]}"; do
      target_package="$out/share/ned/''${package//./\/}"
      if [ -e "$target_package" ]; then
        echo "Removing excluded package $package"
        rm -r "$target_package"
      else
        echo "Did not find excluded package $package"
      fi
    done

    if [ -d images ]; then
      mkdir -p $out/share/omnetpp
      cp -r images $out/share/omnetpp/
    fi

    exported_libs_abs=()
    for lib in "''${exported_libs[@]}"; do
      exported_libs_abs+=("$out/lib/''${lib##*/}")
    done


    if [ ''${#exported_libs_abs[@]} -gt 0 ]; then
      mkdir -p $out/nix-support
      for lib in "''${exported_libs_abs[@]}"; do
        echo $lib >> $out/nix-support/opp-libs
      done
    fi

    # NIX_OPP_LIBS=''${exported_libs_abs[*]// /:}
    # mkdir -p $out/nix-support
    # echo "export NIX_OPP_LIBS=\"\$NIX_OPP_LIBS\''${NIX_OPP_LIBS:+:}$NIX_OPP_LIBS\"" >> $out/nix-support/setup-hook

    runHook postInstall
  '';
})
