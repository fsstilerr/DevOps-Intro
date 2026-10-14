{
  description = "Reproducible QuickNotes build";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };

          quicknotes = pkgs.buildGoModule {
            pname = "quicknotes";
            version = "0.1.0";

            src = ./app;

            vendorHash = null;

            env.CGO_ENABLED = 0;

            ldflags = [
              "-s"
              "-w"
            ];
          };

          rootfs = pkgs.runCommand "quicknotes-rootfs" { } ''
            mkdir -p $out/bin $out/etc $out/tmp
            cp ${quicknotes}/bin/quicknotes $out/bin/quicknotes

            cat > $out/etc/passwd <<PASSWD
nonroot:x:65532:65532:nonroot:/tmp:/sbin/nologin
PASSWD

            cat > $out/etc/group <<GROUP
nonroot:x:65532:
GROUP

            chmod 1777 $out/tmp
          '';

          dockerImage = pkgs.dockerTools.buildImage {
            name = "quicknotes-nix";
            tag = "latest";

            copyToRoot = rootfs;

            config = {
              Entrypoint = [ "/bin/quicknotes" ];
              ExposedPorts = {
                "8080/tcp" = { };
              };
              User = "nonroot:nonroot";
              WorkingDir = "/tmp";
              Env = [
                "ADDR=:8080"
                "DATA_PATH=/tmp/notes.json"
                "SEED_PATH=/tmp/seed.json"
              ];
            };
          };
        in
        {
          inherit quicknotes;
          default = quicknotes;
        }
        // nixpkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          docker = dockerImage;
        });

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              go
              gopls
              golangci-lint
            ];
          };
        });
    };
}
