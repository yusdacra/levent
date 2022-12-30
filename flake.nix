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
  }@inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];
      perSystem = {pkgs, system, ...}: {
        devShells.default = pkgs.mkShell {
          packages = [
            zig.packages.${system}.master
          ];
        };
      };
    };
}
