# games

Game servers, grouped into their own namespace so they can be easily identified.

| App | Description | Manifest |
| --- | --- | --- |
| [minecraft](https://github.com/itzg/docker-minecraft-server) | Minecraft Java Edition server, with [Geyser](https://geysermc.org/) so Bedrock clients (e.g. the Switch) can connect via a proxy. | [ks.yaml](./minecraft/ks.yaml) |

The two below still have manifests in this directory but are **not listed in
`kustomization.yaml`**, so Flux does not reconcile them and nothing is running. Either wire
them back in or delete the directories.

| Not reconciled | Description | Manifest |
| --- | --- | --- |
| [minecraft-rcon-web](https://github.com/itzg/rcon-web-admin) | Web admin panel for the Minecraft server over RCON. | [ks.yaml](./minecraft-rcon-web/ks.yaml) |
| [minecraft-router](https://github.com/itzg/mc-router) | Routes incoming connections to the correct Minecraft backend by hostname. | [ks.yaml](./minecraft-router/ks.yaml) |
