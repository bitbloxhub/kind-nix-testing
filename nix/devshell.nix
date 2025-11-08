{
  perSystem =
    {
      pkgs,
      ...
    }:
    {
      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          nixfmt
          deadnix
          statix
          just
          nushell
          yq-go
          kubectl
          podman
          kind
          tilt
          fluxcd
          tektoncd-cli
        ];
      };
    };
}
