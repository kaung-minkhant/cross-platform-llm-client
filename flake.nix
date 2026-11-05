{
  description = "Dev shell for the PrivateLM Flutter app";

  inputs = {
    # Main package set.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Pinned only to get Flutter 3.38.4 (Dart 3.10.3), the version the project
    # was created with (see .metadata). This is the nixpkgs commit
    # "flutter: 3.38.3 -> 3.38.4".
    nixpkgs-flutter.url = "github:NixOS/nixpkgs/dbe15c61ad906a93afd062df346057ac263c826d";
  };

  outputs = { self, nixpkgs, nixpkgs-flutter }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system:
          f nixpkgs.legacyPackages.${system} nixpkgs-flutter.legacyPackages.${system});
    in {
      devShells = forAllSystems (pkgs: pkgsFlutter: {
        default = pkgs.mkShell {
          packages = [
            pkgsFlutter.flutter # 3.38.4
            pkgs.jdk17 # Android Gradle build requires JDK 17
            pkgs.git
          ];

          JAVA_HOME = "${pkgs.jdk17}";
        };
      });
    };
}
