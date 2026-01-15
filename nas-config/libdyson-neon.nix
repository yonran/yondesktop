{ lib
, buildPythonPackage
, fetchFromGitHub
, paho-mqtt
, cryptography
, requests
, zeroconf
, attrs
}:

buildPythonPackage rec {
  pname = "libdyson-neon";
  version = "1.6.0";
  format = "setuptools";

  src = fetchFromGitHub {
    owner = "libdyson-wg";
    repo = "libdyson-neon";
    rev = "v${version}";
    hash = "sha256-pGDUglM3Rmd/Rn0ZlsSYiS1GyZMFBHtSY8EfLy6MLdc=";
  };

  propagatedBuildInputs = [
    paho-mqtt
    cryptography
    requests
    zeroconf
    attrs
  ];

  # No tests in repository
  doCheck = false;

  pythonImportsCheck = [ "libdyson" ];

  meta = with lib; {
    description = "Python library for Dyson devices";
    homepage = "https://github.com/libdyson-wg/libdyson-neon";
    license = licenses.mit;
  };
}
