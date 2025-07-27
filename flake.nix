{
  description = "Kernel development environments";

  inputs = {
    systems.url = "github:nix-systems/default-linux";

    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
      fenix,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages."${system}";

        # A set of scripts to simplify kernel development.
        kernelDevTools = pkgs.callPackage ./tools.nix {
          flakeSelf = self;
        };

        linuxCommonDependencies =
          [
            kernelDevTools
          ]
          ++ (with pkgs; [
            bc
            bison
            cpio
            elfutils
            flex
            gmp
            gnumake
            kmod
            libmpc
            mpfr
            nettools
            openssl
            pahole
            perl
            python3Minimal
            rsync
            ubootTools
            zlib
            zstd

            # For make menuconfig
            ncurses

            # For make gtags
            global

            # For git send-email 🫠
            gitFull
          ]);

        rust-analyzer = fenix.packages."${system}".rust-analyzer;

        linuxRustDependencies =
          { clang, rustVersion }:
          let
            rustc = rust-overlay.packages."${system}"."${rustVersion}".override {
              extensions = [
                "rust-src"
                "rustfmt"
                "clippy"
              ];
            };

            rustPlatform = pkgs.makeRustPlatform {
              cargo = rustc;
              rustc = rustc;
            };

            bindgenUnwrapped = pkgs.callPackage ./bindgen/0.65.1.nix {
              inherit rustPlatform clang;
            };

            bindgen = pkgs.rust-bindgen.override {
              rust-bindgen-unwrapped = bindgenUnwrapped;
            };
          in
          [
            bindgen
            rust-analyzer
            rustc
          ];

        mkGccShell =
          { gccVersion }:
          pkgs.mkShell {
            packages = linuxCommonDependencies ++ [ pkgs."gcc${gccVersion}" ];

            # Disable all automatically applied hardening. The Linux
            # kernel will take care of itself.
            NIX_HARDENING_ENABLE = "";
          };

        mkClangShell =
          { clangVersion, rustcVersion }:
          let
            # https://github.com/LavaDesu/flakes/blob/fdf6a3ce627793e66ab9188b4660fecbc1ef0c96/overlays/linux-lava.nix#L3
            llvmPackages = pkgs."llvmPackages_${clangVersion}";
            cc = llvmPackages.stdenv.cc.override {
              # :sob: see https://github.com/NixOS/nixpkgs/issues/142901
              bintools = llvmPackages.bintools;
              extraBuildCommands = ''
                substituteInPlace "$out/nix-support/cc-cflags" --replace " -nostdlibinc" ""
                echo " -resource-dir=${llvmPackages.libclang.lib}/lib/clang/${clangVersion}" >> $out/nix-support/cc-cflags
              '';
            };
            stdenv = pkgs.overrideCC llvmPackages.stdenv cc;
            ccacheStdenv = pkgs.ccacheStdenv.override { inherit stdenv; };
          in
          pkgs.mkShell {
            packages =
              ([
                llvmPackages.bintools
                llvmPackages.llvm
                cc
              ])
              ++ (linuxRustDependencies {
                clang = cc;
                rustVersion = "rust_${rustcVersion}";
              })
              ++ linuxCommonDependencies;

            # To force LLVM build mode. This should create less problems
            # with Rust interop.
            LLVM = "1";

            # Disable all automatically applied hardening. The Linux
            # kernel will take care of itself.
            NIX_HARDENING_ENABLE = "";
          };
      in
      {
        packages = {
          inherit kernelDevTools;
          default = kernelDevTools;
        };

        devShells = {
          default = self.devShells."${system}".linux_6_12;

          linux_6_6 = mkClangShell {
            clangVersion = "19";
            rustcVersion = "1_78_0";
          };
          linux_6_6_gcc = mkGccShell { gccVersion = "14"; };

          linux_6_11 = mkClangShell {
            clangVersion = "19";
            rustcVersion = "1_78_0";
          };
          linux_6_11_gcc = mkGccShell { gccVersion = "14"; };

          linux_6_12 = mkClangShell {
            clangVersion = "19";
            rustcVersion = "1_82_0";
          };
          linux_6_12_gcc = mkGccShell { gccVersion = "14"; };
        };

        formatter = pkgs.nixfmt-rfc-style;
      }
    );
}
