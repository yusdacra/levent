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
        devShells.default = let
          runtimeLibs = with pkgs; [
            xorg.libX11
            vulkan-loader
          ];
        in
          pkgs.mkShell {
            packages =
              runtimeLibs
              ++ [
                pkgs.gtk3
                pkgs.pkg-config
                zig.packages.${system}.master
              ];
            LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath runtimeLibs}";
          };
      };
    };
}
