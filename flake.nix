{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    zig.url = "github:mitchellh/zig-overlay";
    zls.url = "github:zigtools/zls";
    zls.inputs.zig-overlay.follows = "zig";
    zls.inputs.nixpkgs.follows = "nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = {
    zig,
    zls,
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
        packages.default = pkgs.stdenvNoCC.mkDerivation {
          pname = "levent";
          version = "master";

          src = ./.;

          buildInputs = [
            pkgs.libxcrypt
            pkgs.gtk3
          ];
          nativeBuildInputs = [
            pkgs.pkg-config
            zig.packages.${system}.master
          ];

          dontConfigure = true;
          dontCheck = true;

          preBuild = "export HOME=$TMPDIR";
          buildPhase = ''
            runHook preBuild
            zig build
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            mv zig-out $out
            runHook postInstall
          '';
        };
        devShells.default = let
          runtimeLibs = with pkgs; [
            xorg.libX11
            vulkan-loader
          ];
        in
          (pkgs.mkShell.override {stdenv = pkgs.stdenvNoCC;}) {
            packages =
              runtimeLibs
              ++ [
                pkgs.gtk3
                pkgs.pkg-config
                zig.packages.${system}.master
                zls.packages.${system}.zls
              ];
            LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath runtimeLibs}";
            ZLIB_LIBRARY_PATH = "${pkgs.zlib}/lib";
          };
      };
    };
}
