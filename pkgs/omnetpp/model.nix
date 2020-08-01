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

    makemake_feature_options=
    if [ -e .oppfeatures ]; then
      opp_featuretool repair
      makemake_feature_options=$(opp_featuretool options)
    fi

    include=()
    libs=()

    while IFS="|" read source_dir makemake_flags; do
        echo "Found source directory $source_dir"
        echo "Makemake options from oppbuildspec: $makemake_flags"

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
              library_name="lib''${arg}.so"
              echo "Found library $library_name"
              library_path="$source_dir/$library_name"
              local_libs+=("$library_path")
              shift
              shift
            ;;
            --meta:export-include-path)
                echo "Detected meta option ''${option#--meta:}, installing headers"
                export_include=true
                shift
            ;;
            --meta:export-library)
                echo "Detected meta option ''${option#--meta:}, installing library"
                export_library=true
                shift
            ;;
            --meta:*)
                echo "Detected unsupported meta option ''${option#--meta:}"
                shift
            ;;
            *)
                other_options+=("$1")
                shift
            ;;
            esac
        done

        if $export_include; then
          echo "Exporting include directories: ''${local_includes[@]}"
          include+=(''${local_includes[@]})
        fi

        if $export_library; then
          echo "Exporting library: ''${local_libs[@]}"
          libs+=(''${local_libs[@]})
        fi

        # Filter out meta options for the IDE
        makemake_flags_fixed=$(sed -E 's/--meta:(\w|-)*\s*//g' <<< $makemake_flags)

        # Add . as implicit include dir
        makemake_flags_fixed="$makemake_flags_fixed -I."
        include+=("$source_dir/.")

        echo "Running opp_makemake in \"$source_dir\" with parameters \"$makemake_flags_fixed\"..."
        pushd "$source_dir"
        opp_makemake $makemake_flags_fixed $makemake_feature_options
        popd

        #if grep -qoP '\-o ?\K(\w+)' <<< $makemake_flag; then
        #    lib_base=$(grep -oP '\-o ?\K(\w+)' <<< $makemake_flags)
        #    lib=lib"$lib_base".so
        #    lib_path="$dir/$lib"
        #    
        #    echo "Found library $lib_path..."
        #    libs+=("$lib_path")
        #fi

        #if grep -qoP '\-I ?\K([\w\./]+)' <<< $makemake_flags; then
        #    include_dir=$(grep -oP '\-I ?\K([\w\./]+)' <<< $makemake_flags)
        #    include_path="$dir/$include_dir"
        #    
        #    echo "Found include directory $include_path..."
        #    include+=("$include_path")
        #fi
    done < <(xml sel -t -m "/buildspec/dir[@type='makemake']" -v "@path" -o "|" -v "@makemake-options" -nl .oppbuildspec)

    readarray -t nedfolders < .nedfolders

    nedexclusions=()
    if [ -e .nedexclusions ]; then
      readarray -t nedexclusions < .nedexclusions
    fi

    echo Found include directories: "''${include[@]}"
    echo Found libraries: "''${libs[@]}"
    echo Found NED folders: "''${nedfolders[@]}"
    echo Excluded NED packages: "''${nedexclusions[@]}"
    
    runHook postConfigure
  '';

  enableParallelBuilding = true;
  makeFlags = [ "MODE=release" ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/"{include,lib,share/ned}

    for include_dir in "''${include[@]}"; do
      pushd $include_dir
      find . -name '*.h' -exec cp --parents '{}' "$out/include" \;
      popd
    done

    for lib in "''${libs[@]}"; do
      cp $lib "$out/lib"
    done

    for nedfolder in "''${nedfolders[@]}"; do
      pushd $nedfolder
        package=
        target_nedpath="$out/share/ned"
        if [ -e package.ned ]; then
          echo Found package.ned

          while read package; do
            echo Found package $package
            target_nedpath="$out/share/ned/''${package//./\/}"
          done < <(sed -En 's/package\s+([\a-z_.]+);/\1/p' package.ned)

          # Remove package declaration
          sed -Ei '/package\s+([\a-z_.]+);/d' package.ned
        fi

        echo "Installing NEDs from $nedfolder for package \"$package\" to $target_nedpath..."
        mkdir -p "$target_nedpath"
        find . -name '*.ned' -exec cp --parents '{}' "$target_nedpath" \;
      popd
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
