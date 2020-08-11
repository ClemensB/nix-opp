{
  lib,

  stdenv,

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
  zlib,

  # OpenSceneGraph support
  libGL,
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

  buildDebug ? true,
  buildSamples ? true,

  installIDE ? true,
  installDoc ? true
}:
let
  # The way OMNeT++ checks for Qt5 requires all files to reside in the same derivation
  # since it uses qmake to query the include path which returns an incorrect value otherwise.
  qt5 = env "qt5" [
    qtbase
    qtbase.dev
    qtbase.out
  ];

  boolToYesNo = b: if b then "yes" else "no";

in stdenv.mkDerivation rec {
  name = "omnetpp-${version}";
  version = "5.6.1";

  src = fetchurl {
    url = "https://github.com/omnetpp/omnetpp/releases/download/${name}/${name}-src-linux.tgz";
    sha256 = "1hfb92zlygj12m9vx2s9x4034s3yw9kp26r4zx44k4x6qdhyq5vz";
  };

  nativeBuildInputs = [
    makeWrapper
  ];

  buildInputs = [
    bison
    expat
    flex
    openmpi
    perl
    python2
    zlib
  ] ++ lib.optionals withQtenv [
    libGL
    qt5
  ];

  propagatedBuildInputs = lib.optionals withOsg [
    libGL
    openscenegraph
  ] ++ lib.optionals withOsgEarth [
    osgearth
  ];

  outputs = [ "out" ]
    ++ lib.optional installDoc "doc"
    ++ lib.optional installIDE "ide"
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
    cp -r bin include lib images "$out/share/omnetpp"
    ln -s "$out/share/omnetpp/"{bin,include,lib} "$out/"

    # Remove IDE launchers
    rm "$out/share/omnetpp/bin/"{omnetpp,omnest}

    # Hardcode OMNeT++ path in installed Makefile.inc
    substitute Makefile.inc "$out/share/omnetpp/Makefile.inc" \
      --replace '$(abspath $(dir $(lastword $(MAKEFILE_LIST))))' "$out"

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

    if ! [ -z ''${ide+x} ]; then
      echo "Installing IDE..."

      mkdir -p "$ide/share/omnetpp"
      cp -r ide "$ide/share/omnetpp/"
      cp -r "${desktopItem}/share/applications" "$ide/share/"
      mkdir "$ide/share/icons"
      ln -s "$ide/share/omnetpp/ide/icon.png" "$ide/share/icons/omnetpp.png"
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

  preFixup = ''
    # Replace the build directory in the RPATH of all executables
    pre_strip_rpath() {
      OLD_RPATH=$(patchelf --print-rpath "$1")
      NEW_RPATH=''${OLD_RPATH//"$PWD"/"$out"}
      patchelf --set-rpath "$NEW_RPATH" "$1"
    }
    export -f pre_strip_rpath
    find "$out" -type f -executable -exec $SHELL -c 'pre_strip_rpath "$0"' {} \;

    if ! [ -z ''${samples+x} ];  then
      find "$samples" -type f -executable -exec $SHELL -c 'pre_strip_rpath "$0"' {} \;
    fi

    if ! [ -z ''${ide+x} ];  then
      # Patch IDE binary
      interpreter=$(echo ${stdenv.glibc.out}/lib/ld-linux*.so.2)
      patchelf --set-interpreter $interpreter $ide/share/omnetpp/ide/omnetpp

      # Create wrapper for IDE
      makeWrapper "$ide/share/omnetpp/ide/omnetpp" "$ide/bin/omnetpp" \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ glib gtk3-x11 webkitgtk xorg.libXtst ]} \
        --prefix PATH : "${jdk11}/bin:$out/bin:${graphviz}/bin:${doxygen}/bin:${gdb}/bin"
    fi
  '';

  setupHooks = [
    (writeScript "setupHook.sh" ''
      echo "OMNeT++ setup hook"

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
        echo "Adding OMNeT++ parameters for $1"

        addToSearchPath NEDPATH $1/share/omnetpp/ned
        addToSearchPath OMNETPP_IMAGE_PATH $1/share/omnetpp/images

        if [ -f $1/nix-support/opp-libs ]; then
          echo "Found $1/nix-support/opp-libs"

          readarray -t opp_libs < $1/nix-support/opp-libs
          for opp_lib in "''${opp_libs[@]}"; do
            echo "Adding $opp_lib to \$NIX_OMNETPP_LIBS"
            addToFileSearchPath NIX_OMNETPP_LIBS $opp_lib
            echo "\$NIX_OMNETPP_LIBS is now $NIX_OMNETPP_LIBS"
          done
        fi
      }

      addEnvHooks "$targetOffset" addOppParams
    '')
  ];

  meta = with stdenv.lib; {
    description = "OMNeT++ is an extensible, modular, component-based C++ simulation library and framework, primarily for building network simulators.";
    homepage = https://omnetpp.org/;
    license = {
      fullName = "Academic Public License";
      url = "https://omnetpp.org/intro/license";
    };
    platforms = platforms.all;
  };
}
