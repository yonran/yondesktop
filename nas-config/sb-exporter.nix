{ lib
, python3Packages
, fetchFromGitHub
, runtimeShell
}:

python3Packages.buildPythonApplication rec {
  pname = "sb-exporter";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "kquinsland";
    repo = "sb820_prometheus_exporter";
    rev = "9d3d4adf51f2e7f63b5d9c5573243c94919e0bd5";
    hash = "sha256-7HH9fml+GBnK/0e53V+f9DvyKRFE2U/JbxhdArReqH0=";
  };
  passthru = {
    # nixos-23.11 still uses prometheus-client 0.17 which is incompatible
    # so we need to override and upgrade to 0.20.0
    prometheus-client = python3Packages.prometheus-client.overrideAttrs (oldAttrs: rec {
      version = "0.20.0";
      src = fetchFromGitHub {
        owner = "prometheus";
        repo = "client_python";
        rev = "refs/tags/v${version}";
        hash = "sha256-IMw0mpOUzjXBy4bMTeSFMc5pdibI5lGxZHKiufjPLbM=";
      };
    });
  };
  postPatch = ''
    substituteInPlace pyproject.toml --replace-fail \
      'structlog = "^24.1.0"' \
      'structlog = "^25"'

    substituteInPlace pyproject.toml --replace-fail \
      'packages = [{ include = "app" }]' \
      'packages = [{ include = "err", from = "app" }, { include = "sb8200", from = "app" }, { include = "err", from = "app" }, { include = "util", from = "app" }]'

    # Adding [tool.poetry.scripts] or [project.scripts]
    cat >> pyproject.toml <<EOF
    [tool.poetry.scripts]
    sb-exporter = { reference = "app/main.py", type = "file" }
    # sb-exporter = "main:main"
    EOF
    #[project.scripts]
    # sb-exporter = "app.main:main"
    # does not work because all the imports assume that main.py is executed directly.
  '';
  # postInstall = ''
  #   mkdir -p $out/bin
  #   cat <<EOF > $out/bin/sb-exporter
  #   #!${runtimeShell}
  #   exec ${python3Packages.python.interpreter} $out/${python3Packages.python.sitePackages}/app/main.py "\$@"
  #   EOF
  #   chmod +x $out/bin/sb-exporter
  # '';

  # do not run tests
  doCheck = false;

  # specific to buildPythonPackage, see its reference
  pyproject = true;
  build-system = [
    python3Packages.setuptools
    python3Packages.wheel
  ];
  nativeBuildInputs = [
    python3Packages.poetry-core
  ];

  propagatedBuildInputs = [
    python3Packages.aiohttp
    passthru.prometheus-client
    python3Packages.structlog
    python3Packages.beautifulsoup4
  ];
}
