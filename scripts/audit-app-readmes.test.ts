import { afterEach, describe, expect, test } from "bun:test";
import { mkdtemp, rm, mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { auditAppReadmes } from "./audit-app-readmes";

const roots: string[] = [];

afterEach(async () => {
  await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
});

async function fixture(): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "audit-app-readmes-"));
  roots.push(root);
  await mkdir(root, { recursive: true });
  return root;
}

async function write(path: string, content: string): Promise<void> {
  await mkdir(join(path, ".."), { recursive: true });
  await writeFile(path, content);
}

async function namespace(root: string, name: string, apps: string[], readme: string): Promise<void> {
  await mkdir(join(root, name), { recursive: true });
  await write(
    join(root, name, "kustomization.yaml"),
    ["resources:", ...apps.map((app) => `  - ./${app}/ks.yaml`), ""].join("\n"),
  );
  for (const app of apps) {
    await mkdir(join(root, name, app), { recursive: true });
  }
  await write(join(root, name, "README.md"), readme);
}

describe("auditAppReadmes", () => {
  test("accepts README app tables whose live manifest links match namespace kustomizations", async () => {
    const root = await fixture();
    await write(
      join(root, "README.md"),
      "# apps\n\n| Namespace | Purpose |\n| --- | --- |\n| [default](./default/README.md) | User-facing apps. |\n",
    );
    await namespace(
      root,
      "default",
      ["home-assistant", "immich"],
      "# default\n\n| App | Description | Backup | Manifest |\n| --- | --- | --- | --- |\n| [home-assistant](https://example.invalid) | Home automation. | VolSync | [ks.yaml](./home-assistant/ks.yaml) |\n| [immich](https://example.invalid) | Photos. | Barman | [ks.yaml](./immich/ks.yaml) |\n",
    );

    const report = await auditAppReadmes(root);

    expect(report.errors).toEqual([]);
    expect(report.namespacesChecked).toBe(1);
    expect(report.appsChecked).toBe(2);
  });

  test("fails when README tables omit reconciled apps or list stale live apps", async () => {
    const root = await fixture();
    await write(
      join(root, "README.md"),
      "# apps\n\n| Namespace | Purpose |\n| --- | --- |\n| [productivity](./productivity/README.md) | Productivity. |\n",
    );
    await namespace(
      root,
      "productivity",
      ["bookstack", "vikunja"],
      "# productivity\n\n| App | Description | Manifest |\n| --- | --- | --- |\n| [bookstack](https://example.invalid) | Wiki. | [ks.yaml](./bookstack/ks.yaml) |\n| [stale](https://example.invalid) | Removed. | [ks.yaml](./stale/ks.yaml) |\n",
    );

    const report = await auditAppReadmes(root);

    expect(report.errors).toContain("productivity README missing reconciled app(s): vikunja");
    expect(report.errors).toContain("productivity README lists non-reconciled app(s) in live table: stale");
  });

  test("warns, but does not fail, for manifests documented outside the live app table", async () => {
    const root = await fixture();
    await write(
      join(root, "README.md"),
      "# apps\n\n| Namespace | Purpose |\n| --- | --- |\n| [games](./games/README.md) | Games. |\n",
    );
    await namespace(
      root,
      "games",
      ["minecraft"],
      "# games\n\n| App | Description | Manifest |\n| --- | --- | --- |\n| [minecraft](https://example.invalid) | Server. | [ks.yaml](./minecraft/ks.yaml) |\n\n## Not reconciled\n\n| App | State | Manifest |\n| --- | --- | --- |\n| minecraft-router | Not listed in kustomization.yaml. | [ks.yaml](./minecraft-router/ks.yaml) |\n",
    );

    const report = await auditAppReadmes(root);

    expect(report.errors).toEqual([]);
    expect(report.warnings).toEqual([
      "games documents non-live manifest link(s) outside the live app table: minecraft-router",
    ]);
  });

  test("fails when the namespace index omits README-backed namespaces", async () => {
    const root = await fixture();
    await write(join(root, "README.md"), "# apps\n");
    await namespace(
      root,
      "ai",
      ["litellm"],
      "# ai\n\n| App | Description | Manifest |\n| --- | --- | --- |\n| [litellm](https://example.invalid) | Router. | [ks.yaml](./litellm/ks.yaml) |\n",
    );

    const report = await auditAppReadmes(root);

    expect(report.errors).toContain("apps README missing namespace link(s): ai");
  });
});
