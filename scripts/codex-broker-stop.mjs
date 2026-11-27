#!/usr/bin/env node
// ABOUTME: Stop a Codex broker process for a workspace after a Codex call ends.
// ABOUTME: Safety: skip if any queued or running job has a live pid. Fail-open.
// ABOUTME: Usage: node codex-broker-stop.mjs <workspace-dir>
// ABOUTME: Written 2026-11-22 per codex-broker-cleanup-spec.md.
// ABOUTME: Logs to ~/.claude/state/codex-broker-stop.log.

import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { execFileSync } from "node:child_process";

const LOG_FILE = path.join(process.env.HOME, ".claude/state/codex-broker-stop.log");

/**
 * Log a message to the stop log file.
 * Purpose: Record all stop attempts for debugging.
 * Usage: Called for every run with timestamp, dir, and action.
 * Gotchas: Creates parent dir if missing. Errors are ignored.
 */
function log(workspaceRoot, action) {
  try {
    const dir = path.dirname(LOG_FILE);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    const line = `${new Date().toISOString()} ${workspaceRoot} ${action}\n`;
    fs.appendFileSync(LOG_FILE, line, "utf8");
  } catch {
    // Fail-open: logging errors do not block the script.
  }
}

/**
 * Find the highest version Codex plugin scripts directory.
 * Purpose: Locate plugin lib modules dynamically.
 * Usage: Returns path or null if not found.
 * Gotchas: Sorts by version number. Env CODEX_PLUGIN_SCRIPTS overrides.
 */
function findPluginScriptsDir() {
  if (process.env.CODEX_PLUGIN_SCRIPTS) {
    return process.env.CODEX_PLUGIN_SCRIPTS;
  }

  const pluginDir = path.join(process.env.HOME, ".claude/plugins/cache/openai-codex/codex");
  if (!fs.existsSync(pluginDir)) {
    return null;
  }

  const versions = fs.readdirSync(pluginDir)
    .filter(name => {
      const scriptsPath = path.join(pluginDir, name, "scripts");
      return fs.existsSync(scriptsPath) && fs.statSync(scriptsPath).isDirectory();
    })
    .sort((a, b) => {
      const aParts = a.split('.').map(x => parseInt(x) || 0);
      const bParts = b.split('.').map(x => parseInt(x) || 0);
      for (let i = 0; i < Math.max(aParts.length, bParts.length); i++) {
        const diff = (aParts[i] || 0) - (bParts[i] || 0);
        if (diff !== 0) return diff;
      }
      return 0;
    });

  if (versions.length === 0) {
    return null;
  }

  return path.join(pluginDir, versions[versions.length - 1], "scripts");
}

/**
 * Check if a process ID is alive.
 * Purpose: Determine if a job's pid is still running.
 * Usage: Returns true if process exists, false otherwise.
 * Gotchas: Signal 0 checks existence without killing. ESRCH means dead.
 */
function isPidAlive(pid) {
  if (!Number.isFinite(pid)) {
    return false;
  }
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    return err.code !== 'ESRCH';
  }
}

/**
 * Find a queued or running job whose pid is alive.
 * Purpose: A live job means the broker is in use.
 * Usage: liveJob(loadState(root)) returns "live job <id>" or null.
 * Gotchas: A job record with a dead pid (crashed job) does not count.
 */
function liveJob(state) {
  for (const job of state.jobs || []) {
    if ((job.status === "queued" || job.status === "running") && isPidAlive(job.pid)) {
      return `live job ${job.id}`;
    }
  }
  return null;
}

/**
 * Find a live codex-companion client process whose working folder is in this workspace.
 * Purpose: Catches a call that has started but has not written its job record yet.
 * Usage: liveClient(root, resolveWorkspaceRoot) returns "live client <pid>" or null.
 * Gotchas: Uses ps and lsof; on any error it returns "client check failed" so the caller skips (fail-safe).
 */
function liveClient(workspaceRoot, resolveWorkspaceRoot) {
  try {
    const ps = execFileSync("ps", ["-Ao", "pid=,args="], { encoding: "utf8" });
    for (const line of ps.split("\n")) {
      const m = line.match(/^\s*(\d+)\s+(.*)$/);
      if (!m || Number(m[1]) === process.pid) continue;
      if (!/codex-companion\.mjs\s+(task|review|adversarial-review|task-worker)\b/.test(m[2])) continue;
      const out = execFileSync("lsof", ["-a", "-p", m[1], "-d", "cwd", "-Fn"], { encoding: "utf8" });
      const cwd = (out.split("\n").find((l) => l.startsWith("n")) || "").slice(1);
      if (cwd && resolveWorkspaceRoot(cwd) === workspaceRoot) return `live client ${m[1]}`;
    }
    return null;
  } catch {
    return "client check failed";
  }
}

/**
 * Stop a Codex broker for a workspace if safe.
 * Purpose: Clean up broker process after a Codex call ends.
 * Usage: Called with workspace root directory path.
 * Gotchas: Skips if any queued/running job has a live pid. Fail-open on errors.
 */
async function stopBroker(workspaceDir) {
  const start = Date.now();

  try {
    const scriptsDir = findPluginScriptsDir();
    if (!scriptsDir) {
      log(workspaceDir, "skip: plugin not found");
      return;
    }

    const libDir = path.join(scriptsDir, "lib");
    const workspaceModule = await import(pathToFileURL(path.join(libDir, "workspace.mjs")).href);
    const brokerLifecycleModule = await import(pathToFileURL(path.join(libDir, "broker-lifecycle.mjs")).href);
    const stateModule = await import(pathToFileURL(path.join(libDir, "state.mjs")).href);
    const processModule = await import(pathToFileURL(path.join(libDir, "process.mjs")).href);

    const { resolveWorkspaceRoot } = workspaceModule;
    const { loadBrokerSession, sendBrokerShutdown, teardownBrokerSession, clearBrokerSession } = brokerLifecycleModule;
    const { loadState } = stateModule;
    const { terminateProcessTree } = processModule;

    const workspaceRoot = resolveWorkspaceRoot(workspaceDir);

    // Check if a broker exists for this workspace.
    const brokerSession = loadBrokerSession(workspaceRoot);
    if (!brokerSession) {
      log(workspaceRoot, "skip: no broker");
      return;
    }

    // Safety check, twice with a gap: skip if a live job or a live Codex client uses this workspace.
    // The gap narrows the race with a call that starts while we decide (Codex review P1, 2026-11-23).
    for (let pass = 0; pass < 2; pass++) {
      const busy = liveJob(loadState(workspaceRoot)) ?? liveClient(workspaceRoot, resolveWorkspaceRoot);
      if (busy) {
        log(workspaceRoot, `skip: ${busy}`);
        return;
      }
      if (pass === 0) await new Promise((r) => setTimeout(r, 1500));
    }

    // Stop the broker using the plugin's own methods. The shutdown message gets a 2 s limit.
    try {
      await Promise.race([
        sendBrokerShutdown(brokerSession.endpoint),
        new Promise((r) => setTimeout(r, 2000)),
      ]);
    } catch {
      // Shutdown command may fail if broker is already dead. Continue to teardown.
    }

    teardownBrokerSession({
      endpoint: brokerSession.endpoint,
      pidFile: brokerSession.pidFile,
      logFile: brokerSession.logFile,
      sessionDir: brokerSession.sessionDir,
      pid: brokerSession.pid,
      killProcess: terminateProcessTree
    });

    clearBrokerSession(workspaceRoot);

    const elapsed = Date.now() - start;
    log(workspaceRoot, `stopped (${elapsed}ms)`);

  } catch (err) {
    // Fail-open: log the error and exit 0.
    log(workspaceDir, `error: ${err.message}`);
  }
}

// Main entry point.
if (process.argv.length < 3) {
  console.error("Usage: codex-broker-stop.mjs <workspace-dir>");
  process.exit(1);
}

const workspaceDir = process.argv[2];
// Hard deadline: never hold up the caller (an EXIT trap waits for this process) past 4.5 s.
setTimeout(() => { log(workspaceDir, "error: 4.5 s deadline hit"); process.exit(0); }, 4500);
stopBroker(workspaceDir).then(() => process.exit(0));
