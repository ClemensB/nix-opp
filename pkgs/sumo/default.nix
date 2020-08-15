{
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
  swig,
  xercesc,
  xorg,
  zlib
}:

stdenv.mkDerivation rec {
  name = "sumo-${version}";
  version = "1.5.0";

  src = fetchFromGitHub {
    owner = "eclipse";
    repo = "sumo";
    rev = "3a3be608d2408d7cbf10f6bba939254ef439c209";
    sha256 = "0pflzq3x8blqm4dalla1qdysh7nzc2j4vmb496qr1drnykz9c022";
  };

  nativeBuildInputs = [
    cmake
    git
    makeWrapper
  ];

  buildInputs = [
    eigen
    ffmpeg
    fontconfig # Not checked by configure
    fox_1_6
    freetype # Not checked by configure
    gdal
    gl2ps
    gtest
    jdk
    libGL # Not checked by configure
    libGLU # Not checked by configure
    libjpeg # Not checked by configure
    libtiff # Not checked by configure
    openscenegraph
    proj
    swig
    xercesc
    zlib

    (python3.withPackages (ps: with ps; [
      setuptools
    ]))
  ] ++ (with xorg; [
    libX11
    libXcursor # Not checked by configure
    libXext # Not checked by configure
    libXfixes # Not checked by configure
    libXft # Not checked by configure
    libXrandr # Not checked by configure
    libXrender # Not checked by configure
  ]);

  enableParallelBuild = true;

  postInstall = ''
    # Add SUMO_HOME to environment of binaries
    for f in "$out"/bin/*; do
      wrapProgram "$f" \
        --set SUMO_HOME "$out"/share/sumo
    done
  '';

  setupHooks = [
    (writeScript "setupHook.sh" ''
      export SUMO_HOME=@out@/share/sumo
    '')
  ];

  meta = with stdenv.lib; {
    description = "A road traffic simulation package";
    homepage = https://sumo.dlr.de/docs/;
    license = licenses.epl20;
  };
}
