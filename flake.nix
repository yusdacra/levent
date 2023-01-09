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
        config,
        pkgs,
        system,
        ...
      }: let
        runtimeLibs = with pkgs; [
          xorg.libX11
          vulkan-loader
        ];
      in {
        packages.default = config.packages.levent;
        packages.levent = config.packages.levent-debug.overrideAttrs (old: {
          ZIG_FLAGS = ["-Drelease-safe=true"];
        });
        packages.levent-debug = pkgs.stdenvNoCC.mkDerivation {
          pname = "levent";
          version = "master";

          src = ./.;

          buildInputs = [
            pkgs.gtk3
          ];
          nativeBuildInputs = [
            pkgs.pkg-config
            zig.packages.${system}.master
          ];

          ZLIB_LIBPATH = "${pkgs.zlib}/lib";
          ZIG_FLAGS = [];

          dontConfigure = true;
          dontCheck = true;
          dontInstall = true;

          preBuild = "export HOME=$TMPDIR";
          buildPhase = ''
            runHook preBuild
            zig build install $ZIG_FLAGS -Dcpu=baseline --prefix $out
            runHook postBuild
          '';
          fixupPhase = ''
            runHook preFixup
            # patchelf \
            #   --set-rpath "${pkgs.lib.makeLibraryPath (runtimeLibs ++ [pkgs.glib pkgs.gtk3])}" \
            #   --set-interpreter "${pkgs.bintools.dynamicLinker}" \
            #   "$out/bin/levent"
            runHook postFixup
          '';
        };
        devShells.default = (pkgs.mkShell.override {stdenv = pkgs.stdenvNoCC;}) {
          packages =
            runtimeLibs
            ++ [
              pkgs.gtk3
              pkgs.pkg-config
              zig.packages.${system}.master
              zls.packages.${system}.zls
            ];
          LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath runtimeLibs}";
          ZLIB_LIBPATH = "${pkgs.zlib}/lib";
        };
      };
    };
}
