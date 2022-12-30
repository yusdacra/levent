{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    zig.url = "github:mitchellh/zig-overlay";
    flake-parts.url = "github:hercules-ci/flake-parts";
    zigmod-binary.url = "https://github.com/nektro/zigmod/releases/download/r84/zigmod-x86_64-linux";
    zigmod-binary.flake = false;
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
            pkgs.pkg-config
            pkgs.gtk3
            zig.packages.${system}.master
            (pkgs.runCommand "zigmod-r84" {
              nativeBuildInputs = [pkgs.autoPatchelfHook];
            } ''
              mkdir -p $out/bin
              cp ${inputs.zigmod-binary} $out/bin/zigmod
              chmod +x $out/bin/zigmod
            '')
          ];
        };
      };
    };
}
