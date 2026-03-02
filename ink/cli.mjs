#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { spawn } from "node:child_process";
import React, { useEffect, useMemo, useRef, useState } from "react";
import { Box, Text, render, useApp, useInput } from "ink";

const h = React.createElement;

const TEST_PATTERNS = [
  /<IsTestProject>\s*true\s*<\/IsTestProject>/i,
  /Microsoft\.NET\.Test\.Sdk/i,
  /xunit/i,
  /NUnit/i,
  /MSTest/i,
];
const CACHE_DIRNAME = ".dottest";
const CACHE_FILENAME = "test-cache.json";
const SUITES_FILENAME = "suites.json";
const COLORS = {
  panelBg: "#1d1d1d",
  scrollBg: "#2f2f2f",
  title: "blue",
  accent: "cyan",
  muted: "gray",
  success: "green",
  warning: "yellow",
  danger: "red",
  scope: "magenta",
  project: "blue",
  info: "blue",
};

function parseArgs(argv) {
  const args = { cwd: process.cwd(), nvimServer: "" };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--cwd") {
      args.cwd = argv[i + 1] ?? args.cwd;
      i += 1;
    } else if (argv[i] === "--nvim-server") {
      args.nvimServer = argv[i + 1] ?? args.nvimServer;
      i += 1;
    }
  }
  return args;
}

async function detectWorkspaceRoot(startPath) {
  let current = path.resolve(startPath);
  const fallback = current;

  while (true) {
    const entries = await fs.readdir(current);
    if (
      entries.some(entry => entry.endsWith(".sln")) ||
      entries.some(entry => entry.endsWith(".csproj")) ||
      entries.includes(".git") ||
      entries.includes("global.json")
    ) {
      return current;
    }

    const parent = path.dirname(current);
    if (parent === current) {
      return fallback;
    }

    current = parent;
  }
}

async function walkFiles(rootDir, predicate) {
  const results = [];

  async function walk(dir) {
    const entries = await fs.readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.name === ".git" || entry.name === "node_modules") {
        continue;
      }

      const fullPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        await walk(fullPath);
      } else if (predicate(entry.name, fullPath)) {
        results.push(fullPath);
      }
    }
  }

  await walk(rootDir);
  return results;
}

async function discoverWorkspace(startDir) {
  const rootDir = await detectWorkspaceRoot(startDir);
  const csprojFiles = await walkFiles(rootDir, name => name.endsWith(".csproj"));
  const solutionFiles = await walkFiles(rootDir, name => name.endsWith(".sln"));
  const projects = [];

  for (const csprojPath of csprojFiles) {
    const contents = await fs.readFile(csprojPath, "utf8");
    const fileName = path.basename(csprojPath);
    if (
      TEST_PATTERNS.some(pattern => pattern.test(contents)) ||
      /\.Tests?\.csproj$/i.test(fileName) ||
      /TestProject\.props/i.test(contents) ||
      /<RootNamespace>.*\.Tests?<\/RootNamespace>/i.test(contents)
    ) {
      projects.push({
        kind: "project",
        name: path.basename(csprojPath, ".csproj"),
        path: csprojPath,
        root: rootDir,
        expanded: false,
        testsLoaded: false,
        children: [],
      });
    }
  }

  projects.sort((a, b) => a.name.localeCompare(b.name));

  return {
    root: rootDir,
    solution: solutionFiles[0] ?? null,
    projects,
  };
}

function cacheFilePath(workspaceRoot) {
  return path.join(workspaceRoot, CACHE_DIRNAME, CACHE_FILENAME);
}

async function loadCache(workspaceRoot) {
  try {
    const raw = await fs.readFile(cacheFilePath(workspaceRoot), "utf8");
    const decoded = JSON.parse(raw);
    return decoded && typeof decoded === "object" ? decoded : { projects: {} };
  } catch {
    return { projects: {} };
  }
}

async function saveCache(workspaceRoot, cache) {
  await fs.mkdir(path.join(workspaceRoot, CACHE_DIRNAME), { recursive: true });
  await fs.writeFile(cacheFilePath(workspaceRoot), JSON.stringify(cache), "utf8");
}

function suitesFilePath(workspaceRoot) {
  return path.join(workspaceRoot, CACHE_DIRNAME, SUITES_FILENAME);
}

async function loadSuites(workspaceRoot) {
  try {
    const raw = await fs.readFile(suitesFilePath(workspaceRoot), "utf8");
    const decoded = JSON.parse(raw);
    return decoded && Array.isArray(decoded.suites) ? decoded.suites : [];
  } catch {
    return [];
  }
}

function itemKey(item) {
  return [item.kind ?? "", item.name ?? "", item.filter ?? "", item.project?.path ?? ""].join("::");
}

async function saveSuite(workspaceRoot, name, items) {
  await fs.mkdir(path.join(workspaceRoot, CACHE_DIRNAME), { recursive: true });
  const existing = await loadSuites(workspaceRoot);
  let inserted = false;
  const next = existing.map(suite => {
    if (suite.name !== name) {
      return suite;
    }
    const seen = new Set((suite.items ?? []).map(itemKey));
    const merged = [...(suite.items ?? [])];
    for (const item of items) {
      if (!seen.has(itemKey(item))) {
        merged.push(item);
      }
    }
    inserted = true;
    return { name, items: merged };
  });
  if (!inserted) {
    next.push({ name, items });
  }
  next.sort((a, b) => a.name.localeCompare(b.name));
  await fs.writeFile(suitesFilePath(workspaceRoot), JSON.stringify({ suites: next }), "utf8");
  return next;
}

function runCommand(command, args, cwd, onLine, options = {}) {
  return new Promise(resolve => {
    const child = spawn(command, args, { cwd, env: process.env });
    let stdout = "";
    let stderr = "";
    let canceled = false;

    if (options.activeChildren) {
      options.activeChildren.add(child);
    }

    if (options.cancelRequestedRef?.current) {
      canceled = true;
      child.kill("SIGINT");
    }

    const push = (chunk, isError) => {
      const text = chunk.toString();
      if (isError) {
        stderr += text;
      } else {
        stdout += text;
      }

      for (const line of text.split(/\r?\n/)) {
        if (line.trim() !== "") {
          onLine(line, isError);
        }
      }
    };

    child.stdout.on("data", chunk => push(chunk, false));
    child.stderr.on("data", chunk => push(chunk, true));
    child.on("close", (code, signal) => {
      if (options.activeChildren) {
        options.activeChildren.delete(child);
      }
      resolve({ code: code ?? 1, stdout, stderr, canceled: canceled || signal != null });
    });
  });
}

async function listTests(project, appendLog, options = {}) {
  const result = await runCommand(
    "dotnet",
    ["test", project.path, "--list-tests", "--nologo", "--verbosity", "quiet"],
    project.root,
    line => appendLog(`[discover] ${line}`),
    options
  );

  if (result.canceled) {
    throw new Error("Canceled");
  }

  if (result.code !== 0) {
    throw new Error(result.stderr || result.stdout || "Failed to list tests");
  }

  const tests = [];
  const seen = new Set();

  for (const rawLine of result.stdout.split(/\r?\n/)) {
    if (/^\s+/.test(rawLine) && !/^The following Tests/i.test(rawLine.trim())) {
      const name = rawLine.trim();
      if (name && !seen.has(name)) {
        seen.add(name);
        tests.push({
          kind: "test",
          name,
          filter: name,
          project,
        });
      }
    }
  }

  return tests;
}

function attachProjectToTests(project, testNames) {
  return testNames.map(name => ({
    kind: "test",
    name,
    filter: name,
    project,
  }));
}

function buildScopeNodes(project, tests) {
  const scopes = new Map();

  for (const test of tests) {
    const parts = test.name.split(".");
    const scopeName = parts.length > 1 ? parts.slice(0, -1).join(".") : project.name;

    if (!scopes.has(scopeName)) {
      scopes.set(scopeName, {
        kind: "scope",
        name: scopeName,
        filter: scopeName,
        project,
        expanded: false,
        children: [],
      });
    }

    scopes.get(scopeName).children.push(test);
  }

  return [...scopes.values()]
    .map(scope => ({
      ...scope,
      children: scope.children.sort((a, b) => a.name.localeCompare(b.name)),
    }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

function flattenNodes(nodes, depth = 0, items = []) {
  for (const node of nodes) {
    items.push({ node, depth });
    if (node.expanded && node.children) {
      flattenNodes(node.children, depth + 1, items);
    }
  }
  return items;
}

function flattenAllNodes(nodes, depth = 0, items = []) {
  for (const node of nodes) {
    items.push({ node, depth });
    if (node.children) {
      flattenAllNodes(node.children, depth + 1, items);
    }
  }
  return items;
}

function expandAllNodes(nodes) {
  for (const node of nodes) {
    if (node.kind === "workspace" || node.kind === "project" || node.kind === "scope") {
      node.expanded = true;
    }
    if (node.children) {
      expandAllNodes(node.children);
    }
  }
}

function nodeKey(node) {
  return [node.kind, node.name, node.filter ?? "", node.project?.path ?? node.path ?? ""].join("::");
}

function cloneTarget(node) {
  return {
    kind: node.kind,
    name: node.name,
    filter: node.filter,
    path: node.path,
    project: node.project,
  };
}

function deletePreviousWord(value) {
  return value.replace(/\s*\S+\s*$/, "");
}

function applyPromptInput(value, input, key) {
  if (key.backspace || key.delete) {
    return value.slice(0, -1);
  }

  if (key.ctrl && input === "w") {
    return deletePreviousWord(value);
  }

  if (key.ctrl && input === "u") {
    return "";
  }

  if (input && !key.ctrl && !key.meta) {
    return value + input;
  }

  return value;
}

function truncateLabel(value, maxWidth = 72) {
  if (value.length <= maxWidth) {
    return value;
  }

  if (maxWidth <= 1) {
    return "…";
  }

  return `${value.slice(0, maxWidth - 1)}…`;
}

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function parseRgLocation(output) {
  const line = output.split(/\r?\n/).find(Boolean);
  if (!line) {
    return null;
  }

  const match = line.match(/^(.*?):(\d+):/);
  if (!match) {
    return null;
  }

  return {
    file: match[1],
    line: Number(match[2]),
  };
}

async function resolveFailureLocation(failure, workspaceRoot) {
  if (failure.file) {
    return failure;
  }

  const parts = failure.name.split(".");
  const methodName = parts.at(-1);
  const className = parts.at(-2);
  const candidates = [methodName, className].filter(Boolean);

  for (const candidate of candidates) {
    const result = await runCommand(
      "rg",
      ["-n", "--glob", "*.cs", `${escapeRegex(candidate)}\\s*\\(`, workspaceRoot],
      workspaceRoot,
      () => {}
    );

    if (result.code === 0) {
      const location = parseRgLocation(result.stdout);
      if (location) {
        return {
          ...failure,
          file: location.file,
          line: location.line,
        };
      }
    }
  }

  return failure;
}

async function resolveTargetLocation(target, workspaceRoot) {
  const parts = target.name.split(".");
  const methodName = parts.at(-1);
  const className = parts.at(-2);
  const candidates = [];

  if (target.kind === "test" && methodName) {
    candidates.push(`${escapeRegex(methodName)}\\s*\\(`);
  }
  if ((target.kind === "test" || target.kind === "scope") && className) {
    candidates.push(`class\\s+${escapeRegex(className)}\\b`);
    candidates.push(`record\\s+${escapeRegex(className)}\\b`);
  }

  for (const pattern of candidates) {
    const result = await runCommand(
      "rg",
      ["-n", "--glob", "*.cs", pattern, workspaceRoot],
      workspaceRoot,
      () => {}
    );

    if (result.code === 0) {
      const location = parseRgLocation(result.stdout);
      if (location) {
        return location;
      }
    }
  }

  return null;
}

async function extractFailures(target, result, workspaceRoot) {
  const failures = [];
  const seen = new Set();
  const text = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
  const lines = text.split(/\r?\n/);
  let currentFailure = null;

  for (const line of lines) {
    const failedMatch = line.match(/^Failed\s+(.+?)\s+\[[^\]]+\]$/);
    if (failedMatch) {
      const failure = {
        name: failedMatch[1],
        target: target.name,
      };
      failures.push(failure);
      currentFailure = failure;
      continue;
    }

    const locationMatch = line.match(/\sin\s(.*?\.cs):line\s(\d+)/);
    if (locationMatch && currentFailure) {
      currentFailure.file = locationMatch[1];
      currentFailure.line = Number(locationMatch[2]);
    }
  }

  const resolved = [];
  for (const failure of failures) {
    if (seen.has(failure.name)) {
      continue;
    }
    seen.add(failure.name);
    resolved.push(await resolveFailureLocation(failure, workspaceRoot));
  }

  return resolved;
}

function openFileInNeovim(server, failure) {
  if (!server || !failure.file) {
    return Promise.resolve(false);
  }

  const escapedPath = failure.file.replace(/'/g, "''");
  const linePart = failure.line ? ` +${failure.line}` : "";
  const expr = `execute('botright vsplit${linePart} ' . fnameescape('${escapedPath}'))`;

  return new Promise(resolve => {
    const child = spawn("nvim", ["--server", server, "--remote-expr", expr], {
      env: process.env,
    });
    child.on("close", code => resolve(code === 0));
  });
}

function quoteForVimscript(value) {
  return `'${value.replace(/'/g, "''")}'`;
}

function updateQuickfix(server, failures) {
  if (!server) {
    return Promise.resolve(false);
  }

  const items = failures
    .filter(failure => failure.file)
    .map(failure => ({
      filename: failure.file,
      lnum: failure.line || 1,
      col: 1,
      text: failure.name,
    }));

  const payload = JSON.stringify(items);
  const expr = `luaeval("(function(payload) local items = vim.json.decode(payload) vim.fn.setqflist({}, 'r', { items = items, title = 'dottest failures' }) if #vim.fn.getqflist() > 0 then vim.cmd('copen') end return true end)(_A)", ${quoteForVimscript(payload)})`;

  return new Promise(resolve => {
    const child = spawn("nvim", ["--server", server, "--remote-expr", expr], {
      env: process.env,
    });
    child.on("close", code => resolve(code === 0));
  });
}

function ProgressBar({ progress }) {
  const total = progress.total || 0;
  const completed = progress.completed || 0;
  const width = 24;
  const filled = total > 0 ? Math.round((completed / total) * width) : 0;
  const bar = `${"=".repeat(filled)}${"-".repeat(Math.max(width - filled, 0))}`;

  return h(
    Text,
    { color: progress.running ? COLORS.warning : progress.failed > 0 ? COLORS.danger : COLORS.success },
    `[${bar}] ${completed}/${total}`
  );
}

function SectionFrame({ title, subtitle, color = "gray", height, children }) {
  return h(
    Box,
    { flexDirection: "column", borderStyle: "round", borderColor: color, paddingX: 1, height },
    h(
      Box,
      { justifyContent: "space-between" },
      h(Text, { bold: true, color }, title),
      subtitle ? h(Text, { color: "gray" }, subtitle) : null
    ),
    children
  );
}

function KeyHint({ label, active = true }) {
  return h(
    Text,
    { color: active ? COLORS.accent : COLORS.muted },
    `[${label}]`
  );
}

function StatusLine({ status }) {
  let color = COLORS.warning;
  if (/passed/i.test(status)) {
    color = COLORS.success;
  } else if (/failed|error|canceled|cancelled/i.test(status)) {
    color = COLORS.danger;
  } else if (/loaded|opened|refreshed/i.test(status)) {
    color = COLORS.info;
  }

  return h(
    Box,
    { borderStyle: "single", borderColor: color, paddingX: 1 },
    h(Text, { color }, status)
  );
}

function statusBadge(status) {
  if (status === "running") {
    return { text: "…", color: COLORS.warning };
  }
  if (status === "passed") {
    return { text: "✓", color: COLORS.success };
  }
  if (status === "failed") {
    return { text: "✗", color: COLORS.danger };
  }
  if (status === "canceled") {
    return { text: "■", color: COLORS.warning };
  }
  return { text: " ", color: undefined };
}

function TreeRow({ item, active, checked, runStatus }) {
  const { node, depth, terminalWidth } = item;
  const hasChildren = node.kind === "workspace" || node.kind === "project" || (node.children && node.children.length > 0);
  const marker = hasChildren ? (node.expanded ? "▾" : "▸") : " ";
  const badge = statusBadge(runStatus);
  const label =
    node.kind === "workspace"
      ? "Workspace"
      : node.kind === "project"
        ? `[project] ${node.name}`
        : node.kind === "scope"
          ? `[scope] ${node.name}`
          : node.name;
  const prefix = `${"  ".repeat(depth)}${marker} ${checked ? "[x]" : "[ ]"} ${badge.text} `;
  const visibleLabel = truncateLabel(label, Math.max(16, terminalWidth - prefix.length - 2));
  const rowColor =
    runStatus === "passed"
      ? COLORS.success
      : runStatus === "failed"
        ? COLORS.danger
        : runStatus === "canceled"
          ? COLORS.warning
          : active
            ? COLORS.accent
            : node.kind === "project"
              ? COLORS.project
              : node.kind === "scope"
                ? COLORS.scope
                : undefined;
  const checkboxColor = checked ? COLORS.success : COLORS.muted;

  return h(
    Text,
    { color: rowColor },
    `${"  ".repeat(depth)}${marker} `,
    h(Text, { color: checkboxColor }, checked ? "[x]" : "[ ]"),
    " ",
    h(Text, { color: badge.color }, badge.text),
    ` ${visibleLabel}`
  );
}

function FailedRow({ failure, active }) {
  const location = failure.file ? `${path.basename(failure.file)}${failure.line ? `:${failure.line}` : ""}` : "location not found";
  const visibleName = truncateLabel(failure.name, Math.max(20, (process.stdout.columns || 100) - location.length - 8));
  return h(
    Box,
    null,
    h(Text, { color: active ? COLORS.accent : COLORS.danger }, `${active ? ">" : " "} ${visibleName}`),
    h(Text, { color: COLORS.muted }, `  ${location}`)
  );
}

function SearchPrompt({ active, value }) {
  if (!active && value === "") {
    return null;
  }

  return h(
    Text,
    { color: active ? COLORS.accent : COLORS.warning },
    `Filter: ${value}${active ? "_" : ""}`
  );
}

function SuitePrompt({ active, value }) {
  if (!active) {
    return null;
  }

  return h(
    Text,
    { color: COLORS.success },
    `Save suite as: ${value}_`
  );
}

function getScrollWindow(items, cursor, height) {
  if (height <= 0) {
    return [];
  }

  if (items.length <= height) {
    return items.map((item, index) => ({ item, index }));
  }

  const half = Math.floor(height / 2);
  let start = Math.max(cursor - half, 0);
  let end = start + height;

  if (end > items.length) {
    end = items.length;
    start = Math.max(end - height, 0);
  }

  return items.slice(start, end).map((item, offset) => ({
    item,
    index: start + offset,
  }));
}

function ScrollableTree({ items, cursor, checkedMap, runStatuses, terminalWidth, height, focused }) {
  const visible = getScrollWindow(items, cursor, height);

  return h(
    Box,
    { flexDirection: "column", height, overflowY: "hidden", backgroundColor: COLORS.scrollBg },
    ...visible.map(({ item, index }) =>
      h(TreeRow, {
        key: `${nodeKey(item.node)}-${index}`,
        item: { ...item, terminalWidth },
        active: focused && index === cursor,
        checked: !!checkedMap[nodeKey(item.node)],
        runStatus: runStatuses[nodeKey(item.node)],
      })
    )
  );
}

function ScrollableFailures({ items, cursor, height, focused }) {
  const visible = getScrollWindow(items, cursor, height);

  return h(
    Box,
    { flexDirection: "column", height, overflowY: "hidden", backgroundColor: COLORS.scrollBg },
    ...visible.map(({ item, index }) =>
      h(FailedRow, {
        key: `${item.name}-${index}`,
        failure: item,
        active: focused && index === cursor,
      })
    )
  );
}

function App({ initialCwd, nvimServer }) {
  const { exit } = useApp();
  const [workspace, setWorkspace] = useState(null);
  const [tree, setTree] = useState([]);
  const [cursor, setCursor] = useState(0);
  const [failureCursor, setFailureCursor] = useState(0);
  const [selected, setSelected] = useState({});
  const [status, setStatus] = useState("Loading workspace...");
  const [logs, setLogs] = useState([]);
  const [busy, setBusy] = useState(false);
  const [logsExpanded, setLogsExpanded] = useState(false);
  const [runStatuses, setRunStatuses] = useState({});
  const [progress, setProgress] = useState({ total: 0, completed: 0, failed: 0, running: false });
  const [failedItems, setFailedItems] = useState([]);
  const [focus, setFocus] = useState("tree");
  const [searchActive, setSearchActive] = useState(false);
  const [searchQuery, setSearchQuery] = useState("");
  const [suitePromptActive, setSuitePromptActive] = useState(false);
  const [suitePromptValue, setSuitePromptValue] = useState("");
  const suitePromptTargetsRef = useRef([]);
  const testsCacheRef = useRef(new Map());
  const failedItemsRef = useRef([]);
  const activeChildrenRef = useRef(new Set());
  const cancelRequestedRef = useRef(false);
  const terminalWidth = process.stdout.columns || 100;
  const terminalHeight = process.stdout.rows || 40;

  const appendLog = line => {
    setLogs(current => [...current, line].slice(-200));
  };

  const flatItems = useMemo(() => flattenNodes(tree), [tree]);
  const searchableItems = useMemo(() => flattenAllNodes(tree), [tree]);
  const visibleItems = useMemo(() => {
    const query = searchQuery.trim().toLowerCase();
    if (query === "") {
      return flatItems;
    }

    return searchableItems.filter(item => {
      if (item.node.kind === "workspace") {
        return false;
      }
      return item.node.name.toLowerCase().includes(query);
    });
  }, [flatItems, searchableItems, searchQuery]);
  const currentNode = visibleItems[cursor]?.node ?? null;
  const pageSize = 10;
  const failedPaneHeight = failedItems.length > 0 ? Math.min(10, Math.max(4, Math.floor(terminalHeight * 0.22))) : 0;
  const outputPaneHeight = logsExpanded ? Math.min(14, Math.max(6, Math.floor(terminalHeight * 0.25))) : 3;
  const topReservedLines =
    3 +
    (searchActive || searchQuery !== "" ? 1 : 0) +
    (suitePromptActive ? 1 : 0) +
    (progress.total > 0 ? 2 : 0) +
    1;
  const treeHeight = Math.max(8, terminalHeight - topReservedLines - failedPaneHeight - outputPaneHeight - 4);

  const hydrateWorkspaceFromCache = (workspaceData, cache) => {
    const projects = workspaceData.projects.map(project => {
      const cachedNames = cache.projects?.[project.path]?.tests;
      if (!Array.isArray(cachedNames) || cachedNames.length === 0) {
        return project;
      }

      testsCacheRef.current.set(project.path, cachedNames);
      return {
        ...project,
        testsLoaded: true,
        children: buildScopeNodes(project, attachProjectToTests(project, cachedNames)),
      };
    });

    return {
      ...workspaceData,
      projects,
    };
  };

  const preloadProjects = async (workspaceData, forceRefresh) => {
    let cache = await loadCache(workspaceData.root);
    let cacheChanged = false;
    let completed = 0;

    for (const project of workspaceData.projects) {
      const cachedNames = cache.projects?.[project.path]?.tests;
      if (!forceRefresh && Array.isArray(cachedNames) && cachedNames.length > 0) {
        testsCacheRef.current.set(project.path, cachedNames);
        completed += 1;
        continue;
      }

      setBusy(true);
      setStatus(`Preloading tests ${completed + 1}/${workspaceData.projects.length}: ${project.name}`);

      try {
        const tests = await listTests(project, appendLog, {
          activeChildren: activeChildrenRef.current,
          cancelRequestedRef,
        });
        const names = tests.map(test => test.name);
        testsCacheRef.current.set(project.path, names);
        cache.projects = cache.projects || {};
        cache.projects[project.path] = {
          tests: names,
          updatedAt: new Date().toISOString(),
        };
        cacheChanged = true;

        setTree(prevTree => {
          const nextTree = structuredClone(prevTree);
          const found = flattenAllNodes(nextTree).find(item => item.node.path === project.path);
          if (found) {
            found.node.testsLoaded = true;
            found.node.children = buildScopeNodes(found.node, attachProjectToTests(found.node, names));
          }
          return nextTree;
        });
      } catch (error) {
        if (error.message === "Canceled") {
          break;
        }
        appendLog(`[error] ${error.message}`);
      } finally {
        completed += 1;
      }
    }

    if (cacheChanged) {
      await saveCache(workspaceData.root, cache);
    }

    setBusy(false);
    setStatus(cancelRequestedRef.current ? "Canceled" : workspaceData.projects.length > 0 ? "Workspace loaded" : "No test projects found");
    cancelRequestedRef.current = false;
  };

  const loadWorkspace = async (forceRefresh = false) => {
    setBusy(true);
    setStatus("Refreshing workspace...");

    try {
      cancelRequestedRef.current = false;
      testsCacheRef.current.clear();
      const discoveredWorkspace = await discoverWorkspace(initialCwd);
      const cache = await loadCache(discoveredWorkspace.root);
      const nextWorkspace = hydrateWorkspaceFromCache(discoveredWorkspace, cache);
      setWorkspace(nextWorkspace);
      setTree([
        {
          kind: "workspace",
          name: nextWorkspace.solution ? path.basename(nextWorkspace.solution, ".sln") : nextWorkspace.root,
          path: nextWorkspace.solution,
          project: {
            path: nextWorkspace.solution ?? nextWorkspace.root,
            root: nextWorkspace.root,
          },
          expanded: true,
          children: nextWorkspace.projects,
        },
      ]);
      setCursor(0);
      setSelected({});
      setRunStatuses({});
      setFailedItems([]);
      failedItemsRef.current = [];
      await updateQuickfix(nvimServer, []);
      setFailureCursor(0);
      setFocus("tree");
      setSearchActive(false);
      setSearchQuery("");
      setProgress({ total: 0, completed: 0, failed: 0, running: false });
      setStatus(nextWorkspace.projects.length > 0 ? "Workspace loaded" : "No test projects found");
      await preloadProjects(nextWorkspace, forceRefresh);
    } catch (error) {
      setStatus(`Failed to load workspace: ${error.message}`);
      appendLog(`[error] ${error.message}`);
    } finally {
      setBusy(false);
    }
  };

  useEffect(() => {
    loadWorkspace(false);
  }, []);

  const ensureProjectLoaded = async itemIndex => {
    const item = flattenAllNodes(tree)[itemIndex];
    if (!item || item.node.kind !== "project" || item.node.testsLoaded) {
      return;
    }

    setBusy(true);
    setStatus(`Loading tests for ${item.node.name}...`);

    try {
      const cachedNames = testsCacheRef.current.get(item.node.path);
      const tests = cachedNames
        ? attachProjectToTests(item.node, cachedNames)
        : await listTests(item.node, appendLog, {
            activeChildren: activeChildrenRef.current,
            cancelRequestedRef,
          });

      if (!cachedNames) {
        testsCacheRef.current.set(item.node.path, tests.map(test => test.name));
      }

      setTree(prevTree => {
        const nextTree = structuredClone(prevTree);
        const nextItem = flattenAllNodes(nextTree)[itemIndex];
        if (nextItem) {
          nextItem.node.children = buildScopeNodes(nextItem.node, tests);
          nextItem.node.testsLoaded = true;
        }
        return nextTree;
      });
      setStatus(cachedNames ? `Loaded ${tests.length} cached tests for ${item.node.name}` : `Loaded ${tests.length} tests for ${item.node.name}`);
    } catch (error) {
      if (error.message === "Canceled") {
        setStatus("Canceled");
        cancelRequestedRef.current = false;
        return;
      }
      appendLog(`[error] ${error.message}`);
      setStatus(`Failed to load tests for ${item.node.name}`);
      setTree(prevTree => {
        const nextTree = structuredClone(prevTree);
        const nextItem = flattenAllNodes(nextTree)[itemIndex];
        if (nextItem) {
          nextItem.node.children = [];
          nextItem.node.testsLoaded = true;
        }
        return nextTree;
      });
    } finally {
      setBusy(false);
    }
  };

  const runTarget = async target => {
    const project = target.project ?? target;
    const targetPath = target.path ?? project.path;
    const key = nodeKey(target);
    if (!targetPath) {
      setStatus("Target is missing a path");
      return;
    }

    const args = ["test", targetPath, "--nologo"];
    if (target.filter) {
      args.push("--filter", `FullyQualifiedName~${target.filter}`);
    }

    setBusy(true);
    setRunStatuses(current => ({
      ...current,
      [key]: "running",
    }));
    setStatus(`Running ${target.name}...`);
    appendLog(`$ dotnet ${args.join(" ")}`);

    const result = await runCommand("dotnet", args, project.root, line => appendLog(line), {
      activeChildren: activeChildrenRef.current,
      cancelRequestedRef,
    });
    const failures = result.code === 0 ? [] : await extractFailures(target, result, workspace?.root ?? project.root);

    setBusy(false);
    setRunStatuses(current => ({
      ...current,
      [key]: result.canceled ? "canceled" : result.code === 0 ? "passed" : "failed",
    }));
    const nextFailures = [...failedItemsRef.current.filter(item => item.target !== target.name), ...failures];
    failedItemsRef.current = nextFailures;
    setFailedItems(nextFailures);
    await updateQuickfix(nvimServer, nextFailures);
    if (failures.length > 0) {
      setFocus("failures");
      setFailureCursor(0);
    }
    if (result.canceled) {
      setStatus(`Canceled: ${target.name}`);
      cancelRequestedRef.current = false;
      return false;
    }
    setStatus(result.code === 0 ? `Passed: ${target.name}` : `Failed: ${target.name}`);
    return result.code === 0;
  };

  const collectChecked = () =>
    flatItems
      .filter(item => item.node.kind !== "workspace" && selected[nodeKey(item.node)])
      .map(item => cloneTarget(item.node));

  const collectAllTests = sourceTree =>
    flattenAllNodes(sourceTree)
      .filter(item => item.node.kind === "test")
      .map(item => cloneTarget(item.node));

  const openCurrentTest = async () => {
    if (!currentNode || currentNode.kind !== "test") {
      return false;
    }

    const location = await resolveTargetLocation(currentNode, workspace?.root ?? initialCwd);
    if (!location) {
      setStatus(`Could not resolve file for ${currentNode.name}`);
      return true;
    }

    const opened = await openFileInNeovim(nvimServer, {
      name: currentNode.name,
      file: location.file,
      line: location.line,
    });
    setStatus(opened ? `Opened ${currentNode.name}` : `Failed to open file in Neovim`);
    return true;
  };

  useInput(async (input, key) => {
    if ((key.ctrl && input === "c") || input === "q") {
      exit();
      return;
    }

    if (busy) {
      if (key.escape) {
        cancelRequestedRef.current = true;
        for (const child of activeChildrenRef.current) {
          child.kill("SIGINT");
        }
        setStatus("Cancelling active test run...");
      }
      return;
    }

    if (suitePromptActive) {
      if (key.escape) {
        setSuitePromptActive(false);
        setSuitePromptValue("");
        suitePromptTargetsRef.current = [];
        return;
      }

      if (key.return) {
        const name = suitePromptValue.trim();
        setSuitePromptActive(false);
        setSuitePromptValue("");
        if (name && workspace) {
          const targets = suitePromptTargetsRef.current;
          suitePromptTargetsRef.current = [];
          try {
            await saveSuite(workspace.root, name, targets);
            setStatus(`Saved suite "${name}" (${targets.length} item${targets.length === 1 ? "" : "s"})`);
          } catch (error) {
            setStatus(`Failed to save suite: ${error.message}`);
          }
        } else {
          suitePromptTargetsRef.current = [];
        }
        return;
      }

      setSuitePromptValue(value => applyPromptInput(value, input, key));
      return;
    }

    if (searchActive) {
      if (key.escape) {
        setSearchActive(false);
        setSearchQuery("");
        setCursor(0);
        return;
      }

      if (key.return) {
        setSearchActive(false);
        setCursor(0);
        return;
      }

      setSearchQuery(value => applyPromptInput(value, input, key));
      setCursor(0);
      return;
    }

    if (input === "\t") {
      if (failedItems.length > 0) {
        setFocus(current => (current === "tree" ? "failures" : "tree"));
      }
      return;
    }

    if (key.upArrow || input === "k") {
      if (focus === "failures") {
        setFailureCursor(value => Math.max(value - 1, 0));
        return;
      }
      setCursor(value => Math.max(value - 1, 0));
      return;
    }

    if (key.downArrow || input === "j") {
      if (focus === "failures") {
        setFailureCursor(value => Math.min(value + 1, Math.max(failedItems.length - 1, 0)));
        return;
      }
      setCursor(value => Math.min(value + 1, Math.max(visibleItems.length - 1, 0)));
      return;
    }

    if (key.pageUp) {
      if (focus === "failures") {
        setFailureCursor(value => Math.max(value - pageSize, 0));
        return;
      }
      setCursor(value => Math.max(value - pageSize, 0));
      return;
    }

    if (key.pageDown) {
      if (focus === "failures") {
        setFailureCursor(value => Math.min(value + pageSize, Math.max(failedItems.length - 1, 0)));
        return;
      }
      setCursor(value => Math.min(value + pageSize, Math.max(visibleItems.length - 1, 0)));
      return;
    }

    if (input === "/") {
      setSearchActive(true);
      setSearchQuery("");
      setCursor(0);
      return;
    }

    if (input === "g") {
      await loadWorkspace(true);
      return;
    }

    if (input === "o") {
      setLogsExpanded(value => !value);
      return;
    }

    if (!currentNode) {
      if (focus === "failures" && failedItems[failureCursor] && (key.return || input === "l")) {
        const opened = await openFileInNeovim(nvimServer, failedItems[failureCursor]);
        setStatus(opened ? `Opened ${failedItems[failureCursor].name}` : "Failed to open file in Neovim");
      }
      return;
    }

    if (focus === "failures") {
      if (key.return || input === "l") {
        const opened = await openFileInNeovim(nvimServer, failedItems[failureCursor]);
        setStatus(opened ? `Opened ${failedItems[failureCursor].name}` : "Failed to open file in Neovim");
      }
      return;
    }

    if (key.return || input === "l") {
      if (currentNode.kind === "workspace" || currentNode.kind === "scope") {
        setTree(prevTree => {
          const nextTree = structuredClone(prevTree);
          const nextItem = visibleItems[cursor];
          const nextKey = nextItem ? nodeKey(nextItem.node) : null;
          const flat = flattenNodes(nextTree);
          const found = nextKey ? flat.find(item => nodeKey(item.node) === nextKey) : null;
          const liveNode = found?.node;
          if (liveNode) {
            liveNode.expanded = !liveNode.expanded;
          }
          return nextTree;
        });
        return;
      }

      if (currentNode.kind === "project") {
        if (!currentNode.testsLoaded) {
          const currentKey = nodeKey(currentNode);
          const actualIndex = flatItems.findIndex(item => nodeKey(item.node) === currentKey);
          await ensureProjectLoaded(actualIndex);
        }

        setTree(prevTree => {
          const nextTree = structuredClone(prevTree);
          const currentKey = nodeKey(currentNode);
          const flat = flattenNodes(nextTree);
          const found = flat.find(item => nodeKey(item.node) === currentKey);
          if (found) {
            found.node.expanded = !found.node.expanded;
          }
          return nextTree;
        });
        return;
      }

      if (currentNode.kind === "test") {
        await openCurrentTest();
      }
      return;
    }

    if (input === "h") {
      setTree(prevTree => {
        const nextTree = structuredClone(prevTree);
        const currentKey = currentNode ? nodeKey(currentNode) : null;
        const flat = flattenNodes(nextTree);
        const found = currentKey ? flat.find(item => nodeKey(item.node) === currentKey) : null;
        if (found && found.node.expanded) {
          found.node.expanded = false;
        }
        return nextTree;
      });
      return;
    }

    if (input === " ") {
      if (currentNode.kind === "workspace") {
        return;
      }

      const keyName = nodeKey(currentNode);
      setSelected(prev => ({
        ...prev,
        [keyName]: !prev[keyName],
      }));
      return;
    }

    if (input === "a") {
      const enable = flatItems.some(item => item.node.kind !== "workspace" && !selected[nodeKey(item.node)]);
      const nextSelected = { ...selected };
      for (const item of flatItems) {
        if (item.node.kind !== "workspace") {
          nextSelected[nodeKey(item.node)] = enable;
        }
      }
      setSelected(nextSelected);
      return;
    }

    if (input === "s") {
      const targets = collectChecked();
      if (targets.length === 0) {
        setStatus("Check nodes with <Space> before saving a suite");
        return;
      }
      suitePromptTargetsRef.current = targets;
      setSuitePromptValue("");
      setSuitePromptActive(true);
      return;
    }

    if (input === "r") {
      if (currentNode.kind === "workspace" && workspace) {
        setFailedItems([]);
        failedItemsRef.current = [];
        await updateQuickfix(nvimServer, []);
        setFailureCursor(0);
        const targets = workspace.solution
          ? [{
              kind: "workspace",
              name: path.basename(workspace.solution, ".sln"),
              path: workspace.solution,
              project: {
                path: workspace.solution,
                root: workspace.root,
              },
            }]
          : workspace.projects.map(project => ({
              kind: "project",
              name: project.name,
              project,
            }));

        setProgress({ total: targets.length, completed: 0, failed: 0, running: true });

        let completed = 0;
        let failed = 0;
        for (const target of targets) {
          const ok = await runTarget(target);
          completed += 1;
          if (!ok) {
            failed += 1;
          }
          const canceled = cancelRequestedRef.current;
          setProgress({ total: targets.length, completed, failed, running: !canceled && completed < targets.length });
          if (canceled) {
            break;
          }
        }
        return;
      }

      setFailedItems([]);
      failedItemsRef.current = [];
      await updateQuickfix(nvimServer, []);
      setFailureCursor(0);
      setProgress({ total: 1, completed: 0, failed: 0, running: true });
      const ok = await runTarget(cloneTarget(currentNode));
      setProgress({ total: 1, completed: 1, failed: ok ? 0 : 1, running: false });
      return;
    }

    if (input === "R") {
      const checkedTargets = collectChecked();
      let items;

      if (checkedTargets.length > 0) {
        items = checkedTargets;
        const expandedTree = structuredClone(tree);
        expandAllNodes(expandedTree);
        setTree(expandedTree);
      } else {
        const expandedTree = structuredClone(tree);
        expandAllNodes(expandedTree);
        setTree(expandedTree);
        items = collectAllTests(expandedTree);
      }

      if (items.length === 0) {
        setStatus("No tests found to run");
        return;
      }

      setFailedItems([]);
      failedItemsRef.current = [];
      await updateQuickfix(nvimServer, []);
      setFailureCursor(0);
      setProgress({ total: items.length, completed: 0, failed: 0, running: true });
      let completed = 0;
      let failed = 0;
      for (const item of items) {
        const ok = await runTarget(item);
        completed += 1;
        if (!ok) {
          failed += 1;
        }
        const canceled = cancelRequestedRef.current;
        setProgress({ total: items.length, completed, failed, running: !canceled && completed < items.length });
        if (canceled) {
          break;
        }
      }
    }
  });

  return h(
    Box,
    { flexDirection: "column", height: terminalHeight, overflow: "hidden", backgroundColor: COLORS.panelBg },
    h(Text, { bold: true, color: COLORS.title }, "dottest.nvim"),
    h(Text, { color: COLORS.muted }, workspace ? (workspace.solution ?? workspace.root) : "Loading..."),
    h(
      Box,
      { flexWrap: "wrap" },
      h(KeyHint, { label: "j/k/pgup/pgdn" }),
      h(Text, { color: COLORS.muted }, " move  "),
      h(KeyHint, { label: "/" }),
      h(Text, { color: COLORS.muted }, " filter  "),
      h(KeyHint, { label: "Enter" }),
      h(Text, { color: COLORS.muted }, " open/expand  "),
      h(KeyHint, { label: "r" }),
      h(Text, { color: COLORS.muted }, " run  "),
      h(KeyHint, { label: "R" }),
      h(Text, { color: COLORS.muted }, " run checked (or all)  "),
      h(KeyHint, { label: "Tab" }),
      h(Text, { color: COLORS.muted }, " switch  "),
      h(KeyHint, { label: "Esc" }),
      h(Text, { color: COLORS.muted }, " stop  "),
      h(KeyHint, { label: "s" }),
      h(Text, { color: COLORS.muted }, " save suite  "),
      h(KeyHint, { label: "o" }),
      h(Text, { color: COLORS.muted }, " output")
    ),
    h(SearchPrompt, { active: searchActive, value: searchQuery }),
    h(SuitePrompt, { active: suitePromptActive, value: suitePromptValue }),
    progress.total > 0 ? h(Box, { marginTop: 1, flexDirection: "column" },
      h(ProgressBar, { progress }),
      h(Text, { color: progress.failed > 0 ? COLORS.danger : COLORS.muted }, progress.failed > 0 ? `${progress.failed} failed` : "all passing so far")
    ) : null,
    h(
      SectionFrame,
      {
        title: `Tests (${visibleItems.length})`,
        subtitle: focus === "tree" ? "focused" : "tree",
        color: focus === "tree" ? COLORS.accent : COLORS.muted,
        height: treeHeight + 2,
      },
      h(ScrollableTree, {
        items: visibleItems,
        cursor,
        checkedMap: selected,
        runStatuses,
        terminalWidth: terminalWidth - 4,
        height: treeHeight,
        focused: focus === "tree",
      })
    ),
    failedItems.length > 0
      ? h(
          SectionFrame,
          {
            title: `Failed Tests (${failedItems.length})`,
            subtitle: focus === "failures" ? "focused" : "Tab to focus",
            color: focus === "failures" ? COLORS.danger : COLORS.muted,
            height: failedPaneHeight + 3,
          },
          h(ScrollableFailures, {
            items: failedItems,
            cursor: failureCursor,
            height: failedPaneHeight,
            focused: focus === "failures",
          })
        )
      : null,
    h(Box, { marginTop: 1 }, h(StatusLine, { status })),
    h(
      SectionFrame,
      {
        title: logsExpanded ? "Output" : "Output",
        subtitle: logsExpanded ? "expanded" : "collapsed",
        color: logsExpanded ? "yellow" : "gray",
        height: outputPaneHeight + 2,
      },
      logsExpanded
        ? getScrollWindow(logs, Math.max(logs.length - 1, 0), outputPaneHeight).map(({ item, index }) =>
            h(Text, { key: `${index}-${item}` }, item)
          )
        : h(Text, { color: "gray" }, `${logs.length} line(s). Press o to expand.`)
    )
  );
}

const args = parseArgs(process.argv.slice(2));
render(h(App, { initialCwd: args.cwd, nvimServer: args.nvimServer }));
