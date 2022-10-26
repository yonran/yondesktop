{ lib, stdenv, fetchurl, undmg, unzip }:

stdenv.mkDerivation {
  pname = "sequel-ace";
  version = "4.0.1";

  src = fetchurl {
    url = "https://github.com/Sequel-Ace/Sequel-Ace/releases/download/production%2F4.0.1-20039/Sequel-Ace-4.0.1.zip";
    sha256 = "1gfgifzgi8i48i3ydqqsf5mrz4dph3frhlsmn00vyngbq8wkc3jm";
  };

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
