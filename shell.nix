{ pkgs ? import <nixpkgs> { } }:
let
  unstable = import <unstable> { };
in
pkgs.mkShell {
  buildInputs = [
    unstable.zig_0_12 pkgs.zls
  ];
}
