{ lib
, stdenv
, cmake
, pkg-config
, qt6
, dokit
, bluez
}:

stdenv.mkDerivation {
  pname = "pokitd";
  version = "0.1.0";

  src = ./src;

  nativeBuildInputs = [
    cmake
    pkg-config
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtconnectivity
    dokit
    bluez
  ];

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON"
    "-DCMAKE_INSTALL_RPATH=${dokit}/lib"
  ];

  meta = with lib; {
    description = "Persistent BLE daemon for Pokit multimeters";
    license = licenses.mit;
    mainProgram = "pokitd";
    platforms = platforms.linux;
  };
}
