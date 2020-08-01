{
  stdenv,

  fetchFromGitHub,

  curl,
  cmake,
  gdal,
  libGL,
  openscenegraph,
  protobuf,
  rocksdb,
  xorg
}:

stdenv.mkDerivation rec {
  pname = "osgearth";
  version = "2.10.1";

  src = fetchFromGitHub {
    owner = "gwaldron";
    repo = "osgearth";
    rev = "1faf43af681e22b0d3b4d0a1ada7e138cf3aac46";
    sha256 = "sha256-lbF98XVeREkF/7Ui9rhOL/kXjJ4DSgndA98+LE4ZH4Y=";
  };

  nativeBuildInputs = [
    cmake
  ];

  buildInputs = [
    curl
    gdal
    libGL
    openscenegraph
    protobuf
    rocksdb

    xorg.libX11
  ];

  meta = with stdenv.lib; {
    description = "Geospatial SDK for OpenSceneGraph";
    homepage = "http://osgearth.org/";
    platforms = platforms.linux;
    license = licenses.lgpl3;
  };
}
