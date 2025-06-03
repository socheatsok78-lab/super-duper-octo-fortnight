{
  inputs = {
    systems.url = "github:nix-systems/default";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
      ...
    }@inputs:
    let
      forEachSystem =
        f: nixpkgs.lib.genAttrs (import systems) (system: f { pkgs = import nixpkgs { inherit system; }; });

      # Define package specifications for different systems
      # This due to hash mismatch in pnpm deps
      # See https://github.com/NixOS/nixpkgs/pull/350063
      pnpmPackageSpec = {
        "aarch64-darwin" = {
          hash = "sha256-ICAf+9iNGoUH3T1bl2iYfQxtDJ5nJrbT+nLIGBsg0O0=";
        };
        "aarch64-linux" = {
          hash = "";
        };
        "x86_64-darwin" = {
          hash = "";
        };
        "x86_64-linux" = {
          hash = "";
        };
      };
    in
    {
      devShells = forEachSystem (
        { pkgs }:
        {
          default = pkgs.mkShellNoCC {
            nativeBuildInputs = [
              pkgs.nodejs_24
              pkgs.pnpm
            ];
            shellHook = ''
              echo "Welcome to your Node.js development environment!"
              echo "Node.js $(node -v)"
            '';
          };
        }
      );
      packages = forEachSystem (
        { pkgs }:
        (
          let
            pname = "super-duper-octo-fortnight";
            version = "1.0.0";

            frontend = pkgs.stdenv.mkDerivation (finalAttrs: {
              inherit pname version;
              src = ./.;

              prePnpmInstall = ''
                pnpm config set dedupe-peer-dependants false
              '';

              pnpmDeps = pkgs.pnpm.fetchDeps {
                inherit (finalAttrs)
                  pname
                  version
                  src
                  prePnpmInstall
                  ;
                hash = pnpmPackageSpec.${pkgs.stdenv.hostPlatform.system}.hash;
              };

              env = {
                PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
              };

              nativeBuildInputs = [
                pkgs.nodejs_24
                pkgs.pnpm.configHook
              ] ++ pkgs.lib.optional pkgs.stdenv.isDarwin [ ];

              doCheck = false;

              buildPhase = ''
                runHook preBuild

                pnpm run build-only --outDir dist

                runHook postBuild
              '';

              installPhase = ''
                runHook preInstall

                mkdir -p $out/public
                cp -r dist/* $out/public

                runHook postInstall
              '';
            });

            server = pkgs.writeShellApplication {
              name = "${pname}-server";
              runtimeInputs = [
                pkgs.caddy
                caddyfile
                frontend
              ];
              text = ''
                caddy run --adapter=caddyfile --config="${caddyfile}/etc/caddy/Caddyfile"
              '';
            };

            caddyfile = pkgs.writeTextFile {
              name = "${pname}-${version}-caddyfile";
              destination = "/etc/caddy/Caddyfile";
              text = ''
                {
                  admin off
                  auto_https off
                  persist_config off
                }

                :80 {
                  root * ${frontend}/public
                  encode zstd gzip
                  file_server

                  # Remove the server header
                  header -Server

                  # Try to serve static files from the root directory
                  # If the file does not exist, serve the index.html file used by the Single Page Application
                  route {
                    try_files {path} /index.html =404
                    header /index.html {
                      ?Document-Policy "js-profiling"
                      Cache-Control "public, max-age=0, must-revalidate"
                    }
                  }
                }
              '';
            };
          in
          {
            inherit frontend caddyfile server;
            default = server;
          }
        )
      );
    };
}
