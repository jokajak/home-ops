#!/usr/bin/env bun
import { readdir, readFile, access } from "node:fs/promises";
import { join } from "node:path";

export type AppReadmeAuditReport = {
  appsRoot: string;
  namespacesChecked: number;
  appsChecked: number;
  errors: string[];
  warnings: string[];
};

async function exists(path: string): Promise<boolean> {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

function uniqueSorted(values: string[]): string[] {
  return [...new Set(values)].sort();
}

function difference(left: string[], right: string[]): string[] {
  const rightSet = new Set(right);
  return left.filter((value) => !rightSet.has(value));
}

function parseDeclaredApps(kustomizationText: string): string[] {
  return uniqueSorted(
    [...kustomizationText.matchAll(/^\s*-\s+\.\/([^/\s#]+)\/ks\.ya?ml\b/gm)].map(
      (match) => match[1],
    ),
  );
}

function parseReadmeManifestLinks(readmeText: string): { liveApps: string[]; allApps: string[] } {
  const lines = readmeText.split("\n");
  const header = lines.findIndex(
    (line) => line.startsWith("|") && /\bApp\b/.test(line) && /\bManifest\b/.test(line),
  );

  const liveApps: string[] = [];
  if (header !== -1) {
    for (let lineIndex = header + 2; lineIndex < lines.length; lineIndex += 1) {
      const line = lines[lineIndex];
      if (!line.startsWith("|")) break;

      const manifestLink = line.match(/\]\(\.\/([^/\s)]+)\/ks\.ya?ml\)/);
      if (manifestLink) liveApps.push(manifestLink[1]);
    }
  }

  const allApps = [...readmeText.matchAll(/\]\(\.\/([^/\s)]+)\/ks\.ya?ml\)/g)].map(
    (match) => match[1],
  );

  return { liveApps: uniqueSorted(liveApps), allApps: uniqueSorted(allApps) };
}

function parseNamespaceIndex(readmeText: string): string[] {
  return uniqueSorted(
    [...readmeText.matchAll(/\]\(\.\/([^/\s)]+)\/README\.md\)/g)].map((match) => match[1]),
  );
}

export async function auditAppReadmes(appsRoot = "kubernetes/apps"): Promise<AppReadmeAuditReport> {
  const report: AppReadmeAuditReport = {
    appsRoot,
    namespacesChecked: 0,
    appsChecked: 0,
    errors: [],
    warnings: [],
  };

  const rootReadme = join(appsRoot, "README.md");
  const namespaceIndex = (await exists(rootReadme))
    ? parseNamespaceIndex(await readFile(rootReadme, "utf8"))
    : [];

  const namespaceDirs = (await readdir(appsRoot, { withFileTypes: true }))
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();

  const readmeBackedNamespaces: string[] = [];

  for (const namespaceName of namespaceDirs) {
    const namespaceRoot = join(appsRoot, namespaceName);
    const namespaceKustomization = join(namespaceRoot, "kustomization.yaml");
    if (!(await exists(namespaceKustomization))) continue;

    const declaredApps = parseDeclaredApps(await readFile(namespaceKustomization, "utf8"));
    const namespaceReadme = join(namespaceRoot, "README.md");
    const hasReadme = await exists(namespaceReadme);
    if (hasReadme) readmeBackedNamespaces.push(namespaceName);

    if (!hasReadme) {
      if (declaredApps.length > 0) {
        report.errors.push(
          `${namespaceName} has reconciled app(s) but no README.md: ${declaredApps.join(", ")}`,
        );
      }
      continue;
    }

    const { liveApps, allApps } = parseReadmeManifestLinks(await readFile(namespaceReadme, "utf8"));
    report.namespacesChecked += 1;
    report.appsChecked += declaredApps.length;

    const missingLiveApps = difference(declaredApps, liveApps);
    if (missingLiveApps.length > 0) {
      report.errors.push(
        `${namespaceName} README missing reconciled app(s): ${missingLiveApps.join(", ")}`,
      );
    }

    const staleLiveApps = difference(liveApps, declaredApps);
    if (staleLiveApps.length > 0) {
      report.errors.push(
        `${namespaceName} README lists non-reconciled app(s) in live table: ${staleLiveApps.join(", ")}`,
      );
    }

    const nonLiveLinks = difference(difference(allApps, liveApps), declaredApps);
    if (nonLiveLinks.length > 0) {
      report.warnings.push(
        `${namespaceName} documents non-live manifest link(s) outside the live app table: ${nonLiveLinks.join(", ")}`,
      );
    }
  }

  const missingIndexNamespaces = difference(uniqueSorted(readmeBackedNamespaces), namespaceIndex);
  if (missingIndexNamespaces.length > 0) {
    report.errors.push(`apps README missing namespace link(s): ${missingIndexNamespaces.join(", ")}`);
  }

  const staleIndexNamespaces = difference(namespaceIndex, uniqueSorted(readmeBackedNamespaces));
  if (staleIndexNamespaces.length > 0) {
    report.errors.push(`apps README lists missing namespace(s): ${staleIndexNamespaces.join(", ")}`);
  }

  return report;
}

function printReport(report: AppReadmeAuditReport): void {
  for (const warning of report.warnings) {
    console.warn(`WARN  ${warning}`);
  }

  if (report.errors.length > 0) {
    for (const error of report.errors) {
      console.error(`FAIL  ${error}`);
    }
    console.error(
      `\n✖ README audit failed: ${report.errors.length} error(s), ${report.warnings.length} warning(s).`,
    );
    process.exitCode = 1;
    return;
  }

  console.log(
    `✔ README audit passed: ${report.appsChecked} app(s), ${report.namespacesChecked} namespace README(s), ${report.warnings.length} warning(s).`,
  );
}

if (import.meta.main) {
  const appsRoot = process.argv[2] ?? "kubernetes/apps";
  const report = await auditAppReadmes(appsRoot);
  printReport(report);
}
