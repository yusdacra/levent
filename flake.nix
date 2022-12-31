{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    zig.url = "github:mitchellh/zig-overlay";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = {
    zig,
    flake-parts,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];
      perSystem = {
        pkgs,
        system,
        ...
      }: {
        devShells.default = pkgs.mkShell {
          packages = [
            zig.packages.${system}.master
            (pkgs.runCommand "dawn" {
                dawnSrc = pkgs.fetchurl {
                  url = "https://github.com/hexops/mach-gpu-dawn/releases/latest/download/x86_64-linux-gnu_release-fast.tar.gz";
                  sha256 = "sha256-hMEKWKWRgK6MgOfbYJBvfrGVla9pBv67gWdNkLLtvJI=";
                };
                buildInputs = [pkgs.gzip pkgs.gnutar];
              } ''
                tar -xf $dawnSrc

                mkdir -p $out/lib
                mv include $out/include
                mv libdawn.a $out/lib
              '')
          ];
        };
      };
    };
}
