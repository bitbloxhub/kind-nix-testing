{
  lib,
  inputs,
  ...
}:
{
  flake.modules.kubenix.default = {
    kubernetes.resources.tasks.goodbye = {
      metadata.namespace = "default";
      spec = {
        params = [
          {
            name = "username";
            type = "string";
          }
        ];
        steps = [
          {
            name = "goodbye";
            image = "alpine";
            script = ''
              #!/bin/sh
              echo "Goodbye $(params.username)!"
            '';
          }
        ];
      };
    };

    kubernetes.resources.pipelines.hello-goodbye = {
      metadata.namespace = "default";
      spec = {
        tasks = [
          {
            name = "goodbye";
            taskRef.name = "goodbye";
            params = [
              {
                name = "username";
                value = "a";
              }
            ];
          }
        ];
      };
    };
  };
}
