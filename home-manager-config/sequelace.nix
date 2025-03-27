{ lib, stdenv, fetchurl, undmg, unzip }:

stdenv.mkDerivation {
  pname = "sequel-ace";
  version = "5.0.3";

  src = fetchurl {
    url = "https://github.com/Sequel-Ace/Sequel-Ace/releases/download/production%2F5.0.3-20089/Sequel-Ace-5.0.3.zip";
    hash = "sha256-XaAlAjPBJHph32bi7wWbxom/NJccONtxy5jTqz44FTA=";
  };
  # ignore __MACOSX dir in the zip file
  sourceRoot = "Sequel Ace.app";

  buildInputs = [ undmg unzip ];
  installPhase = ''
    mkdir -p "$out/Applications/Sequel Ace.app"
    cp -R . "$out/Applications/Sequel Ace.app"
    chmod +x "$out/Applications/Sequel Ace.app/Contents/MacOS/Sequel Ace"
  '';

  meta = {
    description = "MySQL/MariaDB database management for macOS";
    homepage = "http://www.sequel-ace.com/";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
  };
}
