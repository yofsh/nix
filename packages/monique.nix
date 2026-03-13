{ lib, python3Packages, fetchFromGitHub, gobject-introspection, wrapGAppsHook4
, gtk4, libadwaita, glib }:

python3Packages.buildPythonApplication rec {
  pname = "monique";
  version = "0.5.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "ToRvaLDz";
    repo = "monique";
    tag = "v${version}";
    hash = "sha256-ck5WYlTsuC6TSulK/597ZjMxBIA7vI/VNwUMrQ+e54g=";
  };

  build-system = [ python3Packages.setuptools ];

  dependencies = [
    python3Packages.pygobject3
    python3Packages.pyudev
  ];

  nativeBuildInputs = [ gobject-introspection wrapGAppsHook4 ];

  buildInputs = [ gtk4 libadwaita glib ];

  postInstall = ''
    install -Dm644 data/com.github.monique.desktop $out/share/applications/com.github.monique.desktop
    install -Dm644 data/com.github.monique.svg $out/share/icons/hicolor/scalable/apps/com.github.monique.svg
  '';

  dontWrapGApps = true;
  preFixup = ''
    makeWrapperArgs+=("''${gappsWrapperArgs[@]}")
  '';

  meta = {
    description = "MONitor Integrated QUick Editor — graphical monitor configurator for Hyprland and Sway";
    homepage = "https://github.com/ToRvaLDz/monique";
    license = lib.licenses.gpl3Plus;
    mainProgram = "monique";
    platforms = lib.platforms.linux;
  };
}
