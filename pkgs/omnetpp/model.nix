{
  pname,
  version,
  src,

  buildInputs ? [],

  stdenv,

  omnetpp,
  xmlstarlet
}:

stdenv.mkDerivation {
  inherit pname version;

  inherit src;

  nativeBuildInputs = [
    xmlstarlet
  ];

  buildInputs = buildInputs ++ [
    omnetpp
  ];

  configurePhase = ''
    runHook preConfigure

    if [ -f .project ]; then
      project_name="''${PWD##*/}"
      echo "Project name is $project_name"
    else
      echo 'OMNet++ project file not found'
      exit 1
    fi

    makemake_feature_options=
    if [ -f .oppfeatures ]; then
      echo "Found feature definition file"
      opp_featuretool repair
      makemake_feature_options=$(opp_featuretool options)
    fi

    include=()
    bins=()
    libs=()

    # Read .oppbuildspec on how to build the project
    while IFS="|" read source_dir makemake_flags; do
        echo "Configuring source directory \"$source_dir\":"
        echo "- IDE Makemake options: $makemake_flags"

        output_name=$project_name
        is_library=false
        export_include=false
        export_library=false

        local_includes=()

        local_libs=()
        other_options=()

        set -- $makemake_flags
        while [[ $# -gt 0 ]]; do
          option="$1"
          case $option in
            -I)
              arg="$2"
              echo "Found include directory ''${arg}"
              include_dir="$source_dir/$arg"
              local_includes+=("$include_dir")
              shift
              shift
            ;;
            -I*)
              arg="''${option:2}"
              echo "Found include directory ''${arg}"
              include_dir="$source_dir/$arg"
              local_includes+=("$include_dir")
              shift
            ;;
            -o)
              arg="$2"
              output_name="$2"
              shift
              shift
            ;;
            --meta:export-include-path)
              echo "Detected meta option ''${option#--meta:}, installing headers"
              export_include=true
              shift
            ;;
            --meta:export-library)
              export_library=true
              shift
            ;;
            --meta:recurse)
              # Doesn't matter
              shift
            ;;
            --meta:use-exported-libs)
              # We always use exported libs
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

        if ! $is_library; then
          echo -n "- Executable: "
          output_file_name="$output_name"
        else
          echo -n "- Library: "
          output_file_name="lib$output_name.so"
        fi
        output_file_path="$source_dir/$output_file_name"
        echo "$output_file_path"

        if $is_binary; then
          bins+=("$output_file_path")
        fi

        if $is_library && $export_library; then
          echo "- Exporting library"
          libs+=("$output_file_path")
        fi

        if $export_include; then
          echo "Exporting include directories: ''${local_includes[@]}"
          include+=(''${local_includes[@]})
        fi

        echo "- Other options: $other_options"

        makemake_options_new=(-o "$output_name" ''${local_includes[@]/#/-I } "''${other_options[@]}")
        echo "- Final Makemake options: ''${makemake_options_new[@]}"

        pushd "$source_dir" > /dev/null
          echo "Running opp_makemake in \"$source_dir\" with parameters \"''${makemake_options_new[@]} $makemake_feature_options\"..."
          opp_makemake ''${makemake_options_new[@]} $makemake_feature_options
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

  enableParallelBuilding = true;
  makeFlags = [ "MODE=release" ];

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
    done

    for lib in "''${libs[@]}"; do
      mkdir -p "$out/lib"
      cp $lib "$out/lib"
    done

    for nedfolder in "''${nedfolders[@]}"; do
      pushd $nedfolder > /dev/null
        package_name=.
        target_nedpath_base="/share/ned"

        if [ -f package.ned ]; then
          while read package; do
            package_name=$package
            target_nedpath_base="/share/ned/''${package//./\/}"
          done < <(sed -En 's/package\s+([\a-z_.]+);/\1/p' package.ned)

          # Remove package declaration
          sed -Ei '/package\s+([\a-z_.]+);/d' package.ned
        fi

        target_nedpath="$out$target_nedpath_base"

        echo "Installing NEDs from $nedfolder for package $package_name to $target_nedpath_base..."
        mkdir -p "$target_nedpath"
        find . -name '*.ned' -exec cp --parents '{}' "$target_nedpath" \;
      popd > /dev/null
    done

    echo "Removing exluded NED packages..."
    for package in "''${nedexclusions[@]}"; do
      target_package="$out/share/ned/''${package//./\/}"
      if [ -e "$target_package" ]; then
        echo "Found excluded package $package at $target_package, removing"
        rm -r "$target_package"
      else
        echo "Did not find excluded package $package"
      fi
    done

    runHook postInstall
  '';
}
