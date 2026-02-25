/**
 * Sync template migrations from the monorepo's supabase/migrations/
 * into apps/launchpad/supabase/template-migrations/ at build time.
 *
 * This runs as a prebuild step so migration files are always up-to-date
 * in the Launchpad's production bundle. No manual copying needed.
 *
 * Works in both:
 * - Local dev: ../../supabase/migrations/ exists in the monorepo
 * - Vercel: the repo root is available during build
 */

import { readdirSync, readFileSync, writeFileSync, mkdirSync, existsSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const launchpadRoot = join(__dirname, "..");

// Where to look for source migrations (try multiple locations)
const sourceCandidates = [
  join(launchpadRoot, "../../supabase/migrations"),  // monorepo: apps/launchpad/ → repo root
  join(launchpadRoot, "../../../supabase/migrations"), // worktree variant
];

const targetDir = join(launchpadRoot, "supabase/template-migrations");

function findSourceDir() {
  for (const dir of sourceCandidates) {
    try {
      const files = readdirSync(dir);
      if (files.some((f) => f.endsWith(".sql"))) {
        return dir;
      }
    } catch {
      // not found, try next
    }
  }
  return null;
}

const sourceDir = findSourceDir();

if (!sourceDir) {
  console.warn(
    "⚠ sync-migrations: No source migrations directory found. " +
    "Template migrations will use whatever is already in template-migrations/."
  );
  process.exit(0);
}

// Ensure target directory exists
if (!existsSync(targetDir)) {
  mkdirSync(targetDir, { recursive: true });
}

// Get source and target files
const sourceFiles = readdirSync(sourceDir)
  .filter((f) => f.endsWith(".sql"))
  .sort();

const existingFiles = new Set(
  existsSync(targetDir) ? readdirSync(targetDir).filter((f) => f.endsWith(".sql")) : []
);

let copied = 0;
let skipped = 0;

for (const file of sourceFiles) {
  if (existingFiles.has(file)) {
    // Check if content differs (handle edits to existing migrations — shouldn't happen but safe)
    const sourceContent = readFileSync(join(sourceDir, file), "utf-8");
    const targetContent = readFileSync(join(targetDir, file), "utf-8");
    if (sourceContent === targetContent) {
      skipped++;
      continue;
    }
  }

  const content = readFileSync(join(sourceDir, file), "utf-8");
  writeFileSync(join(targetDir, file), content, "utf-8");
  copied++;
}

if (copied > 0) {
  console.log(`✓ sync-migrations: Copied ${copied} migration(s), ${skipped} already up-to-date.`);
} else {
  console.log(`✓ sync-migrations: All ${skipped} migration(s) already up-to-date.`);
}
