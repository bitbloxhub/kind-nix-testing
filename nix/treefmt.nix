{
  inputs,
  ...
}:
{
  imports = [
    inputs.treefmt-nix.flakeModule
  ];

  perSystem = {
    treefmt = {
      projectRootFile = "flake.lock";

      programs.nixfmt.enable = true;
      programs.deadnix.enable = true;
      programs.statix.enable = true;
    };
  };
}
