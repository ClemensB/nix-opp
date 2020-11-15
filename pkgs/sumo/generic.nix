{
  version,
  rev,
  sha256
}:

{
  lib,

  stdenv,

  fetchFromGitHub,

  makeWrapper,
  writeScript,

  cmake,
  git,

  eigen,
  ffmpeg,
  fontconfig,
  fox_1_6,
  freetype,
  gdal,
  gl2ps,
  gtest,
  jdk,
  libGL,
  libGLU,
  libjpeg,
  libtiff,
  openscenegraph,
  proj,
  python3,
  python3Packages,
  swig,
  xercesc,
  xorg,
  zlib,

  withEigen ? true,
  withFfmpeg ? true,
  withGDAL ? true,
  withGL2PS ? true,
  withGUI ? true,
  withOSG ? true,
  withProj ? true,
  withSWIG ? true
}:

assert withFfmpeg -> withGUI;
assert withGL2PS -> withGUI;
assert withOSG -> withGUI;

stdenv.mkDerivation rec {
  name = "sumo-${version}";
  inherit version;

  src = fetchFromGitHub {
    owner = "eclipse";
    repo = "sumo";
    inherit rev sha256;
  };

  nativeBuildInputs = [
    cmake
    git
    makeWrapper
  ];

  buildInputs = [
    # gtest
    # jdk
    xercesc
    zlib

    (python3.withPackages (ps: with ps; [
      setuptools
    ]))
  ] ++ lib.optionals withEigen [
    eigen
  ] ++ lib.optionals withFfmpeg [
    ffmpeg
  ]  ++ lib.optionals withGDAL [
    gdal
  ] ++ lib.optionals withGL2PS [
    gl2ps
  ] ++ lib.optionals withGUI (with xorg; [
    fox_1_6

    libGL # Not checked by configure
    libGLU # Not checked by configure
    libjpeg # Not checked by configure
    libtiff # Not checked by configure

    libX11
    libXcursor # Not checked by configure
    libXext # Not checked by configure
    libXfixes # Not checked by configure
    libXft # Not checked by configure
    libXrandr # Not checked by configure
    libXrender # Not checked by configure
  ]) ++ lib.optionals withOSG [
    openscenegraph
  ] ++ lib.optionals withProj [
    proj
  ] ++ lib.optionals withSWIG [
    swig
  ];

  outputs = [ "out" "tools" "pythonPackage" ];

  postInstall = ''
    # Add SUMO_HOME to environment of binaries
    for f in "$out"/bin/*; do
      wrapProgram "$f" \
        --set SUMO_HOME "$out"/share/sumo
    done

    # Move tools
    mv $out/share/sumo/tools $tools

    # Move python package (Package properly later if required)
    mkdir -p $pythonPackage/lib
    mv $out/lib/python* $pythonPackage/lib
  '';

  # Strip libsumo Python bindings as well
  stripDebugList = [ "bin" "lib" "share/sumo/tools/libsumo" ];

  setupHooks = [
    (writeScript "setupHook.sh" ''
      export SUMO_HOME=@out@/share/sumo
    '')
  ];

  passthru = {
    sumolib = python3Packages.buildPythonPackage {
      pname = "sumolib";
      inherit version;

      inherit src;

      preConfigure = ''
        cd tools/build
        mv setup-sumolib.py setup.py
      '';
    };
  };

  meta = with stdenv.lib; {
    description = "A road traffic simulation package";
    homepage = https://sumo.dlr.de/docs/;
    license = licenses.epl20;
  };
}
