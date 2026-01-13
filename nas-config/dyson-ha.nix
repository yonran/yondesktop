{ lib
, buildHomeAssistantComponent
, fetchFromGitHub
, libdyson-neon
}:

buildHomeAssistantComponent rec {
  owner = "libdyson-wg";
  domain = "dyson_local";
  version = "1.7.0";

  src = fetchFromGitHub {
    owner = "libdyson-wg";
    repo = "ha-dyson";
    rev = "v${version}";
    hash = "sha256-C5UDK0st0IR3PRsbiG9M9ZfGpDrPYqBcPw/8/2iWJXw=";
  };

  dependencies = [
    libdyson-neon
  ];

  meta = with lib; {
    description = "Home Assistant integration for Dyson devices with local connectivity";
    homepage = "https://github.com/libdyson-wg/ha-dyson";
    license = licenses.mit;
  };
}
