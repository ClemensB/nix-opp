{
  version,
  sha256
}:

let
  pkg = {
    lib,

    stdenv,

    callPackage,

    fetchurl,

    makeDesktopItem,
    makeWrapper,
    nukeReferences,
    writeScript,

    bison,
    doxygen,
    expat,
    flex,
    gcc,
    gdb,
    glib,
    glibc,
    gnumake,
    graphviz,
    openmpi,
    perl,
    python2,
    python3,
    zlib,

    # OpenSceneGraph support
    libGL,
    libglvnd,
    openscenegraph,
    osgearth,

    # IDE
    gtk3-x11,
    jdk11,
    webkitgtk,
    xorg,

    # Provided by the Qt5 package set
    env,
    qtbase,

    withQtenv ? true,
    withOsg ? true,
    withOsgEarth ? true,

    withOpenMPI ? false,

    buildDebug ? true,
    buildSamples ? true,

    installIDE ? true,
    installDoc ? true,
    installSamples ? true
  }@attrs:
  let
    inherit (lib) boolToString;

    src = fetchurl {
      url = "https://github.com/omnetpp/omnetpp/releases/download/omnetpp-${version}/omnetpp-${version}-src-linux.tgz";
      inherit sha256;
    };

    # The way OMNeT++ checks for Qt5 requires all files to reside in the same derivation
    # since it uses qmake to query the include path which returns an incorrect value otherwise.
    qt5 = env "qt5" [
      qtbase
      qtbase.dev
      qtbase.out
    ];

    oppPythonPackage = python3.pkgs.buildPythonPackage {
      pname = "omnetpp";
      inherit version src;

      propagatedBuildInputs = with python3.pkgs; [
        matplotlib
        numpy
        pandas
        scipy
      ];

      preConfigure = ''
        cd python

        # Add missing __init__.py for modules
        find omnetpp -type d -exec touch {}/__init__.py \;

        # Add setup.py for packaging
        cat << EOF > setup.py
        from setuptools import setup, find_packages

        setup(
          name='omnetpp',
          version='${version}',
          packages=find_packages(),
          install_requires=["matplotlib", "numpy", "pandas", "scipy"],
        )
        EOF
      '';
    };

    oppPython3 = python3.withPackages (ps: with ps; [
      matplotlib
      numpy
      pandas
      posix_ipc

      oppPythonPackage
    ]);

    isPre6 = lib.strings.hasPrefix "5." version;

    python = (if isPre6 then python2 else oppPython3);

    boolToYesNo = b: if b then "yes" else "no";

    self = stdenv.mkDerivation rec {
      name = "omnetpp-${version}";
      inherit version src;

      patches = [
        ./0001-Set-QT_QPA_PLATFORM_PLUGIN_PATH.patch
      ];

      nativeBuildInputs = [
        makeWrapper
        nukeReferences
      ];

      buildInputs = [
        bison
        expat
        flex
        perl
        python
        zlib
      ] ++ lib.optionals withQtenv [
        libGL
        qt5
      ] ++ lib.optionals withOpenMPI [
        openmpi
      ];

      propagatedBuildInputs = lib.optionals withOsg [
        libGL
        openscenegraph
      ] ++ lib.optionals withOsgEarth [
        osgearth
      ];

      outputs = [ "bin" "dev" "run" "full" "out" ]
        ++ lib.optional installDoc "doc"
        ++ lib.optional installIDE "ide"
        ++ lib.optional installSamples "samples";

      postPatch = ''
        # Don't write to $HOME
        substituteInPlace src/utils/Makefile \
          --replace '$(HOME)/.wishname' '/tmp/.wishname'

        # Fix ar invokation
        substituteInPlace src/envir/Makefile \
          --replace '$(Q)$(AR) $(ARFLAG_OUT)$O/$(MAINLIBNAME)$(A_LIB_SUFFIX) $O/main.o' \
                    '$(Q)$(AR) cr $(ARFLAG_OUT)$O/$(MAINLIBNAME)$(A_LIB_SUFFIX) $O/main.o'

        # Make hardcoded default image path point to $out instead of /build
        substituteInPlace src/envir/envirbase.cc \
          --replace 'OMNETPP_IMAGE_PATH)' "\"$out/share/omnetpp/images\")"

        # Help Qt find its plugins
        # Since users are building binaries on their own, we cannot rely on wrappers for this
        if ${boolToString withQtenv}; then
          substituteInPlace src/qtenv/qtenv.cc \
            --subst-var-by QT_QPA_PLATFORM_PLUGIN_PATH "${qtbase}/lib/qt-${qtbase.version}/plugins"
        fi
      '';

      preConfigure = ''
        # OMNeT++ wants its bin folder on the $PATH to compile
        export PATH=$PWD/bin:$PATH

        # Prematurely patch shebangs for utils since they are used during build
        patchShebangs src/utils

        cat << EOF > configure.user
        WITH_QTENV=${boolToYesNo withQtenv}
        WITH_OSG=${boolToYesNo withOsg}
        WITH_OSGEARTH=${boolToYesNo withOsgEarth}

        WITH_NETBUILDER=yes
        WITH_PARSIM=yes
        EOF
      '';

      preBuild = lib.optionalString buildDebug ''
        # Make sure debug information points to $dev instead of /build
        export NIX_CFLAGS_COMPILE="-fdebug-prefix-map=/build/$name/src=$dev/share/omnetpp/src $NIX_CFLAGS_COMPILE"
      '';

      enableParallelBuilding = true;
      buildModes = lib.optional buildDebug "debug" ++ [ "release" ];
      buildTargets = [ "base" ] ++ lib.optional buildSamples "samples";

      buildPhase = ''
        runHook preBuild

        for mode in $buildModes; do
          make MODE=$mode ''${enableParallelBuilding:+-j''${NIX_BUILD_CORES} -l''${NIX_BUILD_CORES}} $buildTargets
        done

        runHook postBuild
      '';

      installPhase = let
        desktopItem = makeDesktopItem {
          name = "OMNeT++";
          exec = "omnetpp";
          icon = "omnetpp";
          comment = "Integrated Development Environment";
          desktopName = "OMNeT++ IDE";
          genericName = "Integrated Development Environment";
          categories = "Application;Development;";
        };
      in ''
        runHook preInstall

        echo "Installing OMNeT++ core..."

        mkdir -p \
          "$out/share/omnetpp" \
          "$dev/share/omnetpp" \
          "$dev/bin" \
          "''${!outputBin}" \
          "''${!outputInclude}" \
          "''${!outputLib}"

        cp -r bin "''${!outputBin}/bin"
        cp -r include "''${!outputInclude}/include"
        cp -r lib "''${!outputLib}/lib"
        cp -r images "$out/share/omnetpp"

        mkdir -p "$run/bin"
        mv "''${!outputBin}/bin/opp_run" "$run/bin"
        ln -s "$run/bin/opp_run" "''${!outputBin}/bin/"

        # Remove IDE launchers
        rm "''${!outputBin}/bin/"{omnetpp,omnest}

        # Hardcode OMNeT++ path in installed Makefile.inc
        substitute Makefile.inc "$dev/share/omnetpp/Makefile.inc" \
          --replace '$(abspath $(dir $(lastword $(MAKEFILE_LIST))))' "$out/share/omnetpp" \
          --replace '$(OMNETPP_ROOT)/include' "$dev/include" \
          --replace '$(OMNETPP_ROOT)/lib' "''${!outputLib}/lib" \
          --replace '$(OMNETPP_ROOT)/bin' "$bin/bin" \
          --replace '$(OMNETPP_ROOT)/src' "$dev/src"

        cat << EOF >> $dev/share/omnetpp/Makefile.inc
        ifeq (\$(MODE),debug)
          OMNETPP_LIB_DIR = "$dev/lib"
        endif
        EOF

        # Amend Makefile.inc to make builds work by default even outside a Nix shell
        cat << EOF >> $dev/share/omnetpp/Makefile.inc
        CFLAGS += -fPIC
        EOF

      '' + lib.optionalString withOsg ''
        cat << EOF >> $dev/share/omnetpp/Makefile.inc
        CFLAGS += \
          -I${libglvnd.dev}/include \
          -I${openscenegraph}/include
        LDFLAGS += \
          -L${openscenegraph}/lib
        EOF
      '' + ''

      '' + lib.optionalString withOsgEarth ''
        cat << EOF >> $dev/share/omnetpp/Makefile.inc
        CFLAGS += \
          -I${osgearth}/include
        LDFLAGS += \
          -L${osgearth}/lib
        EOF
      '' + ''

        # Create new opp_configfilepath script pointing to Makefile.inc in $dev
        echo "#!$SHELL" > "''${!outputBin}/bin/opp_configfilepath"
        echo "echo '$dev/share/omnetpp/Makefile.inc'" >> "''${!outputBin}/bin/opp_configfilepath"

        # Move development binaries
        mv "''${!outputBin}/bin/"{opp_configfilepath,opp_makemake} "$dev/bin/"

        if ${boolToString buildDebug}; then
          # Move debug libraries
          mkdir "$dev/lib"
          find "''${!outputLib}/lib" -type f -name '*_dbg.*' -exec mv {} "$dev/lib/" \;

          # Move debug binaries
          mv "''${!outputBin}/bin/opp_run_dbg" "$dev/bin"

          # Install sources
          cp -r src "$dev/share/omnetpp"
        fi

        if ${boolToString installDoc}; then
          echo "Installing documentation..."

          mkdir -p "$doc/share/omnetpp"
          cp -r doc "$doc/share/omnetpp/"
        fi

        if ${boolToString installIDE}; then
          echo "Installing IDE..."

          mkdir -p "$ide/share/omnetpp"
          cp -r ide "$ide/share/omnetpp/"
          cp -r "${desktopItem}/share/applications" "$ide/share/"
          mkdir "$ide/share/icons"
          ln -s "$ide/share/omnetpp/ide/icon.png" "$ide/share/icons/omnetpp.png"

          # Remove JRE if included
          if [ -e $ide/share/omnetpp/ide/jre ]; then
            rm -r $ide/share/omnetpp/ide/jre
          fi
        fi

        if ${boolToString installSamples}; then
          echo "Installing samples..."

          # Clean up samples
          for sample in samples/*/; do
            rm -rf "$sample"out
          done

          # Install samples
          mkdir -p "$samples/share/omnetpp"
          cp -r samples "$samples/share/omnetpp/"
        fi

        mkdir -p "$full/share/omnetpp/"{bin,lib}
        ln -s "$out/share/omnetpp/images" "''${!outputInclude}/include" "$dev/share/omnetpp/Makefile.inc" "$full/share/omnetpp/"
        ln -s "''${!outputBin}/bin"/* "$dev/bin"/* "$full/share/omnetpp/bin"
        ln -s "''${!outputLib}/lib"/* "$dev/lib"/* "$full/share/omnetpp/lib"
        cp -r misc "$full/share/omnetpp/"

        ${boolToString installDoc} && ln -s "$doc/share/omnetpp/doc" "$full/share/omnetpp/"
        ${boolToString installSamples} && ln -s "$samples/share/omnetpp/samples" "$full/share/omnetpp/"

        runHook postInstall
      '';

      dontStrip = true;

      preFixup = ''
        # Manually strip here for two reasons:
        # - We need to avoid stripping *_dbg libraries
        # - Strip may fail after using patchelf, see https://github.com/NixOS/nixpkgs/pull/85592
        echo Stripping binaries...
        find "''${!outputBin}/bin" "''${!outputLib}/lib" "$run/bin" -type f -not -name '*_dbg.so' -exec $STRIP -S {} \;

        # Replace the build directory in the RPATH of all executables
        # Also, replace full Qt5 package with Qt5 lib output
        pre_strip_rpath() {
          OLD_RPATH=$(patchelf --print-rpath "$1")
          NEW_RPATH=''${OLD_RPATH//"$PWD"/"$2"}
          NEW_RPATH=''${NEW_RPATH//"${qt5}"/"${qtbase.out}"}
          echo "Replacing RPATH \"$OLD_RPATH\" with \"$NEW_RPATH\" in \"$1\""
          patchelf --set-rpath "$NEW_RPATH" "$1"
        }
        export -f pre_strip_rpath

        echo "Fixing up RPATHs..."
        find "''${!outputBin}" "''${!outputLib}" "$run" -type f -executable -exec $SHELL -c "pre_strip_rpath \"\$0\" \"$out\"" {} \;
        find "$dev" -type f -executable -exec $SHELL -c "pre_strip_rpath \"\$0\" \"$dev\"" {} \;

        if ${boolToString buildSamples}; then
          echo "Fixing up RPATHs for samples.."
          find "$samples" -type f -executable -exec $SHELL -c 'pre_strip_rpath "$0"' {} \;
        fi

        if ${boolToString withQtenv}; then
          echo "Nuking references to Qt..."
          nuke-refs -e "$out" -e "${glibc}" -e "${stdenv.cc.cc.lib}" \
             -e "$dev" -e "${glibc.dev}" -e "${stdenv.cc.cc}" \
             -e "${qtbase}" -e "${qtbase.out}" \
            "$out/lib/"liboppqtenv*.so "$dev/lib/"liboppqtenv*.so
          nuke-refs -e "$out" -e "$dev" -e "$bin" \
            '' + lib.optionalString withOsg "-e \"${libglvnd.dev}\" -e \"${openscenegraph}\" \ " + ''
            '' + lib.optionalString withOsgEarth "-e \"${osgearth}\" \ " + ''
            "$dev/share/omnetpp/Makefile.inc"
        fi

        if ${boolToString installIDE}; then
          ide_bin="$ide/share/omnetpp/ide/${if isPre6 then "omnetpp" else "opp_ide"}"

          # Patch IDE binary
          echo "Patching IDE launcher interpreter..."
          interpreter=$(echo ${stdenv.glibc.out}/lib/ld-linux*.so.2)
          patchelf --set-interpreter "$interpreter" "$ide_bin"

          # Create wrapper for IDE
          echo "Generating IDE launch wrapper..."
          makeWrapper "$ide_bin" "$ide/bin/omnetpp" \
            --set OMNETPP_ROOT "$full/share/omnetpp" \
            --set OMNETPP_CONFIGFILE "$full/share/omnetpp/Makefile.inc" \
            --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ glib gtk3-x11 webkitgtk xorg.libXtst ]}" \
            --prefix PATH : "${lib.makeBinPath ([ jdk11 gnumake graphviz doxygen gcc gdb ] ++ lib.optional (!isPre6) python)}"
        fi
      '';

      setupHooks = [
        (writeScript "setupHook.sh" ''
          addToFileSearchPathWithCustomDelimiter() {
              local delimiter="$1"
              local varName="$2"
              local file="$3"
              if [ -f "$file" ]; then
                  export "''${varName}=''${!varName:+''${!varName}''${delimiter}}''${file}"
              fi
          }

          addToFileSearchPath() {
              addToFileSearchPathWithCustomDelimiter ":" "$@"
          }

          addOppParams() {
            addToSearchPath NEDPATH $1/share/omnetpp/ned
            addToSearchPath OMNETPP_IMAGE_PATH $1/share/omnetpp/images

            if [ -f $1/nix-support/opp-libs ]; then
              readarray -t opp_libs < $1/nix-support/opp-libs
              for opp_lib in "''${opp_libs[@]}"; do
                addToFileSearchPath NIX_OMNETPP_LIBS $opp_lib
              done
            fi
          }

          addEnvHooks "$targetOffset" addOppParams
        '')
      ];

      passthru = rec {
        models = callPackage ../omnetpp-models {
          omnetpp = self;
        };
      } // lib.optionalAttrs (!isPre6)  {
        pythonPackage = oppPythonPackage;
      };

      meta = with stdenv.lib; {
        description = "OMNeT++ is an extensible, modular, component-based C++ simulation library and framework, primarily for building network simulators.";
        homepage = https://omnetpp.org/;
        license = {
          fullName = "Academic Public License";
          url = "https://omnetpp.org/intro/license";
        };
        platforms = platforms.all;
      };
    };
  in self;
in pkg
