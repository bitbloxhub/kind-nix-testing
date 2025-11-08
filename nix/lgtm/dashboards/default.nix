{
  lib,
  ...
}:
{
  flake.modules.kubenix.lgtm = {
    imports =
      builtins.map
        (path: {
          kubernetes.resources.grafanadashboards.${"${builtins.elemAt path 0}-${builtins.replaceStrings [ ".json" ] [ "" ] (builtins.elemAt path 1)}"} =
            {
              metadata.namespace = "grafana";
              spec = {
                instanceSelector = {
                  matchLabels.dashboards = "grafana";
                };
                folder = builtins.elemAt path 0;
                json = builtins.readFile ./${builtins.elemAt path 0}/${builtins.elemAt path 1};
              };
            };
        })
        (
          builtins.map (path: lib.takeEnd 2 path) (
            builtins.map (path: lib.splitString "/" path) (
              builtins.filter (path: (builtins.match ".*\.json$" path) == [ ]) (
                builtins.map (path: builtins.toString path) (lib.filesystem.listFilesRecursive ./.)
              )
            )
          )
        );
  };
}
