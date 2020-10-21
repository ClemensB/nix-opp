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
    writeScript,

    bison,
    doxygen,
    expat,
    flex,
    gcc,
    gdb,
    glib,
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
    buildSamples ? false,

    installIDE ? true,
    installDoc ? true
  }@attrs:
  let
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

      nativeBuildInputs = [
        makeWrapper
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

      outputs = [ "out" ]
        ++ lib.optional installDoc "doc"
        ++ lib.optional buildSamples "samples";

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

      inherit buildDebug;

      preBuild = lib.optionalString buildDebug ''
        # Make sure debug information points to $out instead of /build
        export NIX_CFLAGS_COMPILE="-fdebug-prefix-map=/build/$name/src=$out/share/omnetpp/src $NIX_CFLAGS_COMPILE"
      '';

      enableParallelBuilding = true;
      buildModes = [ "release" ] ++ lib.optional buildDebug "debug";
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

        mkdir -p "$out/share/omnetpp"
        cp -r bin include lib "$out"
        cp -r images "$out/share/omnetpp"
        cp -r misc "$out/share/omnetpp"
        ln -s "$out/"{bin,include,lib} "$out/share/omnetpp/"

        # Remove IDE launchers
        rm "$out/share/omnetpp/bin/"{omnetpp,omnest}

        # Hardcode OMNeT++ path in installed Makefile.inc
        substitute Makefile.inc "$out/share/omnetpp/Makefile.inc" \
          --replace '$(abspath $(dir $(lastword $(MAKEFILE_LIST))))' "$out"

        # Amend Makefile.inc to make builds work by default even outside a Nix shell
        cat << EOF >> $out/share/omnetpp/Makefile.inc
        CFLAGS += -fPIC
        EOF

      '' + lib.optionalString (withOsg && false) /* Disable due to closure size */ ''
        cat << EOF >> $out/share/omnetpp/Makefile.inc
        CFLAGS += \
          -I${libglvnd.dev}/include \
          -I${openscenegraph}/include \
        LDFLAGS += \
          -L${openscenegraph}/lib \
        EOF
      '' + ''

      '' + lib.optionalString (withOsgEarth && false) /* Disable due to closure size */ ''
        cat << EOF >> $out/share/omnetpp/Makefile.inc
        CFLAGS += \
          -I${osgearth}/include
        LDFLAGS += \
          -L${osgearth}/lib
        EOF
      '' + ''

        # Create new opp_configfilepath script pointing to Makefile.inc in $out
        echo "#!$SHELL" > "$out/bin/opp_configfilepath"
        echo "echo '$out/share/omnetpp/Makefile.inc'" >> "$out/bin/opp_configfilepath"

        if [ "$buildDebug" == "1" ]; then
          cp -r src "$out/share/omnetpp"
        fi

        if ! [ -z ''${doc+x} ]; then
          echo "Installing documentation..."

          mkdir -p "$doc/share/omnetpp"
          cp -r doc "$doc/share/omnetpp/"
        fi

        if [ "${lib.boolToString installIDE}" == "true" ]; then
          echo "Installing IDE..."

          cp -r ide "$out/share/omnetpp/"
          cp -r "${desktopItem}/share/applications" "$out/share/"
          mkdir "$out/share/icons"
          ln -s "$out/share/omnetpp/ide/icon.png" "$out/share/icons/omnetpp.png"

          # Remove JRE if included
          if [ -e $out/share/omnetpp/ide/jre ]; then
            rm -r $out/share/omnetpp/ide/jre
          fi
        fi

        if ! [ -z ''${samples+x} ]; then
          echo "Installing samples..."

          # Clean up samples
          for sample in samples/*/; do
            rm -rf "$sample"out
          done

          # Install samples
          mkdir -p "$samples/share/omnetpp"
          cp -r samples "$samples/share/omnetpp/"
        fi

        runHook postInstall
      '';

      dontStrip = true;

      preFixup = ''
        # Manually strip here for two reasons:
        # - We need to avoid stripping *_dbg libraries
        # - Strip may fail after using patchelf, see https://github.com/NixOS/nixpkgs/pull/85592
        echo Stripping binaries...
        find "$out/bin" "$out/lib" -type f -not -name '*_dbg.so' -exec $STRIP -S {} \;

        # Replace the build directory in the RPATH of all executables
        pre_strip_rpath() {
          OLD_RPATH=$(patchelf --print-rpath "$1")
          NEW_RPATH=''${OLD_RPATH//"$PWD"/"$out"}
          patchelf --set-rpath "$NEW_RPATH" "$1"
        }
        export -f pre_strip_rpath

        echo "Fixing up RPATHs in $out..."
        find "$out" -type f -executable -exec $SHELL -c 'pre_strip_rpath "$0"' {} \;

        if ! [ -z ''${samples+x} ];  then
          echo "Fixing up RPATHs in $samples.."
          find "$samples" -type f -executable -exec $SHELL -c 'pre_strip_rpath "$0"' {} \;
        fi

        if [ "${lib.boolToString installIDE}" == "true" ]; then
          ide_bin="$out/share/omnetpp/ide/${if isPre6 then "omnetpp" else "opp_ide"}"

          # Patch IDE binary
          echo "Patching IDE launcher interpreter..."
          interpreter=$(echo ${stdenv.glibc.out}/lib/ld-linux*.so.2)
          patchelf --set-interpreter "$interpreter" "$ide_bin"

          # Create wrapper for IDE
          echo "Generating IDE launch wrapper..."
          makeWrapper "$ide_bin" "$out/bin/omnetpp" \
            --set OMNETPP_ROOT "$out/share/omnetpp" \
            --set OMNETPP_CONFIGFILE "$out/share/omnetpp/Makefile.inc" \
            --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ glib gtk3-x11 webkitgtk xorg.libXtst ]}" \
            --prefix PATH : "${lib.makeBinPath ([ jdk11 gnumake graphviz doxygen gcc gdb ] ++ lib.optional (!isPre6) python)}"
        fi
      '';

      setupHooks = [
        (writeScript "setupHook.sh" ''
          export OMNETPP_ROOT=@out@/share/omnetpp
          export OMNETPP_CONFIGFILE=@out@/share/omnetpp/Makefile.inc

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
        core = callPackage pkg (attrs // {
          installIDE = false;
        });

        minimal = callPackage pkg (attrs // {
          installIDE = false;
          buildDebug = false;

          withQtenv = false;
          withOsg = false;
          withOsgEarth = false;
        });

        minimal-gui = callPackage pkg (attrs // {
          installIDE = false;
          buildDebug = false;

          withQtenv = true;
          withOsg = true;
          withOsgEarth = true;
        });

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
