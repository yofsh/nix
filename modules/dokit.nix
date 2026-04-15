{ lib
, stdenv
, fetchFromGitHub
, cmake
, pkg-config
, qt6
, bluez
}:

stdenv.mkDerivation rec {
  pname = "dokit";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "pcolby";
    repo = "dokit";
    rev = "v${version}";
    hash = "sha256-Hmuz1hM7hUSOfcEVlJ8DRcH/RSaCtOo5AlRvCLySMf8=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
    qt6.wrapQtAppsHook
    qt6.qttools
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtconnectivity
    qt6.qttools
    bluez
  ];

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DBUILD_TESTING=OFF"
    "-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON"
    "-DCMAKE_INSTALL_RPATH=${placeholder "out"}/lib"
  ];

  # The doc/ subdirectory unconditionally fetches an external CMake-modules
  # repo over the network, which the Nix sandbox forbids. We don't need docs.
  postPatch = ''
    substituteInPlace CMakeLists.txt --replace-fail 'add_subdirectory(doc)' ""
  '';

  # dokit's CMake provides no install target; copy the CLI binary, the
  # QtPokit shared library it links against, and the public headers
  # (needed by downstream consumers like our pokitd daemon).
  installPhase = ''
    runHook preInstall
    install -Dm755 src/cli/dokit $out/bin/dokit
    install -d $out/lib
    cp -P src/lib/libQtPokit.so* $out/lib/
    install -d $out/include/qtpokit
    cp ../include/qtpokit/*.h $out/include/qtpokit/
    runHook postInstall
  '';

  meta = with lib; {
    description = "CLI for Pokit Meter and Pokit Pro Bluetooth multimeters";
    homepage = "https://github.com/pcolby/dokit";
    license = licenses.lgpl3Plus;
    mainProgram = "dokit";
    platforms = platforms.linux;
  };
}
