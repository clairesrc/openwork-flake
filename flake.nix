{
  description = "NixOS flake for OpenWork – local-first AI agent orchestrator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      version = "0.11.113";

      # Per-platform binary package names and hashes from the npm registry.
      platforms = {
        x86_64-linux = {
          npmPkg = "openwork-orchestrator-linux-x64";
          hash = "sha256-a8F8TYgde7YgnxbQX4CSxtH9SSXKYAifsyIsIjHISkg=";
        };
        aarch64-linux = {
          npmPkg = "openwork-orchestrator-linux-arm64";
          hash = "sha256-hGutvNmU9eBNWjA8bEwmEBcnUWUSn5ECuTQ+gZDRYHM=";
        };
      };

      supportedSystems = builtins.attrNames platforms;

      forEachSystem = f: nixpkgs.lib.genAttrs supportedSystems (system:
        f {
          inherit system;
          pkgs = nixpkgs.legacyPackages.${system};
        }
      );
    in
    {
      packages = forEachSystem ({ system, pkgs }:
        let
          meta = platforms.${system};
        in
        {
          openwork = pkgs.stdenv.mkDerivation {
            pname = "openwork";
            inherit version;

            src = pkgs.fetchurl {
              url = "https://registry.npmjs.org/${meta.npmPkg}/-/${meta.npmPkg}-${version}.tgz";
              inherit (meta) hash;
            };

            sourceRoot = ".";

            nativeBuildInputs = [ pkgs.patchelf ];

            # Bun standalone binaries embed the JS bundle after the ELF data.
            # autoPatchelfHook rewrites ELF sections and corrupts this trailer.
            # We only patch the interpreter so the appended payload stays intact.
            dontBuild = true;
            dontStrip = true;
            dontPatchELF = true;

            installPhase =
              let
                interpreter = "${pkgs.stdenv.cc.libc}/lib/ld-linux-${
                  if system == "aarch64-linux" then "aarch64" else "x86-64"
                }.so.2";
              in
              ''
                runHook preInstall
                mkdir -p $out/bin
                install -m 755 package/bin/openwork $out/bin/openwork
                patchelf --set-interpreter "${interpreter}" $out/bin/openwork
                runHook postInstall
              '';

            meta = with pkgs.lib; {
              description = "OpenWork – local-first AI agent orchestrator (opencode + server + router)";
              homepage = "https://github.com/different-ai/openwork";
              license = licenses.mit;
              platforms = supportedSystems;
              mainProgram = "openwork";
            };
          };

          default = self.packages.${system}.openwork;
        }
      );

      nixosModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.services.openwork;
        in
        {
          options.services.openwork = {
            enable = lib.mkEnableOption "OpenWork orchestrator service";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.system}.openwork;
              defaultText = lib.literalExpression "openwork-flake.packages.\${system}.openwork";
              description = "The openwork package to use.";
            };

            workspace = lib.mkOption {
              type = lib.types.str;
              description = "Absolute path to the workspace directory for OpenWork.";
              example = "/home/user/projects/myapp";
            };

            dataDir = lib.mkOption {
              type = lib.types.str;
              default = "/var/lib/openwork";
              description = "Directory for OpenWork orchestrator state and sidecar cache.";
            };

            host = lib.mkOption {
              type = lib.types.str;
              default = "0.0.0.0";
              description = "Bind address for the OpenWork server.";
            };

            port = lib.mkOption {
              type = lib.types.port;
              default = 8787;
              description = "Port for the OpenWork server.";
            };

            approvalMode = lib.mkOption {
              type = lib.types.enum [ "manual" "auto" ];
              default = "manual";
              description = "Approval mode for privileged operations.";
            };

            approvalTimeout = lib.mkOption {
              type = lib.types.nullOr lib.types.int;
              default = null;
              description = "Approval timeout in milliseconds. Null uses the default (30000).";
            };

            cors = lib.mkOption {
              type = lib.types.str;
              default = "*";
              description = "Comma-separated CORS origins, or * for all.";
            };

            readOnly = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Start OpenWork server in read-only mode.";
            };

            connectHost = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Override LAN host used for pairing URLs.";
            };

            opencode = {
              host = lib.mkOption {
                type = lib.types.str;
                default = "127.0.0.1";
                description = "Bind address for the internal OpenCode server.";
              };

              port = lib.mkOption {
                type = lib.types.nullOr lib.types.port;
                default = 4096;
                description = "Port for the internal OpenCode server. Null picks a random port.";
              };

              auth = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Enable basic auth on the OpenCode server.";
              };

              hotReload = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Enable OpenCode hot reload.";
              };
            };

            router = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Enable the OpenCode Router sidecar (Slack/Telegram/WhatsApp bridge).";
              };

              required = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Exit if the OpenCode Router process stops.";
              };

              healthPort = lib.mkOption {
                type = lib.types.nullOr lib.types.port;
                default = null;
                description = "Health check port for the router. Null picks a random port.";
              };
            };

            sandbox = {
              mode = lib.mkOption {
                type = lib.types.enum [ "none" "auto" "docker" "container" ];
                default = "none";
                description = "Sandbox backend for running agents.";
              };

              image = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Container image for sandbox mode.";
              };
            };

            logFormat = lib.mkOption {
              type = lib.types.enum [ "pretty" "json" ];
              default = "json";
              description = "Log output format.";
            };

            verbose = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable verbose diagnostics.";
            };

            user = lib.mkOption {
              type = lib.types.str;
              default = "openwork";
              description = "User account under which OpenWork runs.";
            };

            group = lib.mkOption {
              type = lib.types.str;
              default = "openwork";
              description = "Group under which OpenWork runs.";
            };

            environmentFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                Path to an environment file loaded by the systemd service.
                Use this for secrets like OPENWORK_TOKEN, OPENWORK_HOST_TOKEN,
                TELEGRAM_BOT_TOKEN, SLACK_BOT_TOKEN, etc.
              '';
            };

            extraArgs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Extra command-line arguments passed to `openwork serve`.";
            };

            openFirewall = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether to open the OpenWork port in the firewall.";
            };
          };

          config = lib.mkIf cfg.enable {
            users.users.${cfg.user} = lib.mkIf (cfg.user == "openwork") {
              isSystemUser = true;
              group = cfg.group;
              home = cfg.dataDir;
              createHome = true;
              description = "OpenWork service user";
            };

            users.groups.${cfg.group} = lib.mkIf (cfg.group == "openwork") { };

            systemd.tmpfiles.rules = [
              "d '${cfg.dataDir}' 0750 ${cfg.user} ${cfg.group} -"
              "d '${cfg.workspace}' 0750 ${cfg.user} ${cfg.group} -"
            ];

            systemd.services.openwork = {
              description = "OpenWork Orchestrator";
              after = [ "network.target" ];
              wantedBy = [ "multi-user.target" ];

              environment = {
                OPENWORK_DATA_DIR = "${cfg.dataDir}/orchestrator";
                OPENWORK_SIDECAR_DIR = "${cfg.dataDir}/sidecars";
                HOME = cfg.dataDir;
                # Sidecar binaries (opencode, openwork-server, opencode-router) are
                # generic Linux ELF binaries downloaded at runtime.  NixOS needs
                # NIX_LD so the stub dynamic linker can find the real interpreter.
                NIX_LD = "${pkgs.stdenv.cc.libc}/lib/ld-linux-${
                  if pkgs.stdenv.hostPlatform.isAarch64 then "aarch64" else "x86-64"
                }.so.2";
                NIX_LD_LIBRARY_PATH = lib.makeLibraryPath [
                  pkgs.stdenv.cc.cc.lib
                  pkgs.stdenv.cc.libc
                ];
              };

              path = with pkgs; [
                git
                curl
                gnutar
                unzip
                gzip
              ] ++ lib.optionals (cfg.sandbox.mode == "docker") [
                pkgs.docker
              ];

              serviceConfig =
                let
                  args = [
                    "${cfg.package}/bin/openwork"
                    "serve"
                    "--workspace" cfg.workspace
                    "--openwork-host" cfg.host
                    "--openwork-port" (toString cfg.port)
                    "--opencode-host" cfg.opencode.host
                    "--approval" cfg.approvalMode
                    "--cors" cfg.cors
                    "--log-format" cfg.logFormat
                    "--sidecar-dir" "${cfg.dataDir}/sidecars"
                  ]
                  ++ lib.optionals (cfg.opencode.port != null) [
                    "--opencode-port" (toString cfg.opencode.port)
                  ]
                  ++ lib.optionals (!cfg.opencode.auth) [ "--no-opencode-auth" ]
                  ++ lib.optionals (!cfg.opencode.hotReload) [ "--no-opencode-hot-reload" ]
                  ++ lib.optionals (cfg.approvalTimeout != null) [
                    "--approval-timeout" (toString cfg.approvalTimeout)
                  ]
                  ++ lib.optionals cfg.readOnly [ "--read-only" ]
                  ++ lib.optionals (cfg.connectHost != null) [
                    "--connect-host" cfg.connectHost
                  ]
                  ++ lib.optionals (!cfg.router.enable) [ "--no-opencode-router" ]
                  ++ lib.optionals cfg.router.required [ "--opencode-router-required" ]
                  ++ lib.optionals (cfg.router.enable && cfg.router.healthPort != null) [
                    "--opencode-router-health-port" (toString cfg.router.healthPort)
                  ]
                  ++ lib.optionals (cfg.sandbox.mode != "none") [
                    "--sandbox" cfg.sandbox.mode
                  ]
                  ++ lib.optionals (cfg.sandbox.image != null) [
                    "--sandbox-image" cfg.sandbox.image
                  ]
                  ++ lib.optionals cfg.verbose [ "--verbose" ]
                  ++ cfg.extraArgs;
                in
                {
                  Type = "simple";
                  User = cfg.user;
                  Group = cfg.group;
                  ExecStart = lib.escapeShellArgs args;
                  Restart = "on-failure";
                  RestartSec = 5;

                  WorkingDirectory = cfg.workspace;

                  # Hardening
                  NoNewPrivileges = true;
                  ProtectSystem = "strict";
                  ProtectHome = "read-only";
                  ReadWritePaths = [
                    cfg.dataDir
                    cfg.workspace
                  ];
                  PrivateTmp = true;
                  ProtectKernelTunables = true;
                  ProtectKernelModules = true;
                  ProtectControlGroups = true;
                  RestrictSUIDSGID = true;
                }
                // lib.optionalAttrs (cfg.environmentFile != null) {
                  EnvironmentFile = cfg.environmentFile;
                };
            };

            networking.firewall.allowedTCPPorts =
              lib.mkIf cfg.openFirewall [ cfg.port ];
          };
        };

      overlays.default = final: prev: {
        openwork = self.packages.${final.system}.openwork;
      };
    };
}
