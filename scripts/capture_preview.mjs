#!/usr/bin/env node
// Dependency-free visual verification. Uses a fresh, disposable browser profile;
// never opens an existing user profile or touches real hotel inventory.
// Usage: node scripts/capture_preview.mjs build/visual_web [--browser "path/to/chrome"]
// Requires Node 22+ (native WebSocket) and Chrome or another Chromium browser.

import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { createReadStream, constants } from 'node:fs';
import { access, mkdir, mkdtemp, readFile, realpath, stat, writeFile } from 'node:fs/promises';
import { once } from 'node:events';
import { randomUUID } from 'node:crypto';

const argumentsList = process.argv.slice(2);
if (!argumentsList.length || argumentsList.includes('--help')) {
  console.log('Usage: node scripts/capture_preview.mjs <Flutter-web-output-directory> [--browser "path/to/chrome"]');
  console.log('Captures desktop 1440x1000 and phone 390x844 to a new build/previews/capture-* directory.');
  console.log('Serves only on 127.0.0.1; temporary profiles are retained, never recursively deleted.');
  process.exit(argumentsList.includes('--help') ? 0 : 1);
}
if (typeof WebSocket !== 'function') {
  throw new Error('Node with native WebSocket support is required. Use Node 22 or newer; no packages are installed.');
}

const projectDirectory = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const webDirectory = await realpath(path.resolve(process.cwd(), argumentsList[0]));
const browserOptionIndex = argumentsList.indexOf('--browser');
if (argumentsList.length > 1 && (browserOptionIndex !== 1 || argumentsList.length !== 3)) {
  throw new Error('Only the web output directory and optional --browser executable are accepted.');
}
await access(path.join(webDirectory, 'index.html'), constants.R_OK);
await access(path.join(webDirectory, 'flutter_bootstrap.js'), constants.R_OK);

const isWithin = (candidate, parent) => {
  const relative = path.relative(parent, candidate);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
};

async function findBrowser() {
  const specified = browserOptionIndex >= 0 ? argumentsList[browserOptionIndex + 1] : process.env.CHROME_PATH;
  const candidates = specified ? [path.resolve(specified)] : [
    process.env.LOCALAPPDATA && path.join(process.env.LOCALAPPDATA, 'Google/Chrome/Application/chrome.exe'),
    process.env.ProgramFiles && path.join(process.env.ProgramFiles, 'Google/Chrome/Application/chrome.exe'),
    process.env['ProgramFiles(x86)'] && path.join(process.env['ProgramFiles(x86)'], 'Google/Chrome/Application/chrome.exe'),
    process.env['ProgramFiles(x86)'] && path.join(process.env['ProgramFiles(x86)'], 'Microsoft/Edge/Application/msedge.exe'),
    process.env.ProgramFiles && path.join(process.env.ProgramFiles, 'Microsoft/Edge/Application/msedge.exe'),
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    ...((process.env.PATH ?? '').split(path.delimiter).flatMap(directory =>
      ['google-chrome', 'chromium', 'chromium-browser', 'chrome', 'msedge'].map(name => path.join(directory, name))))
  ];
  for (const candidate of candidates.filter(Boolean)) {
    try {
      await access(candidate, constants.X_OK);
      if ((await stat(candidate)).isFile()) return candidate;
    } catch { /* Try another installed Chromium browser. */ }
  }
  throw new Error('Chrome/Chromium was not found. Set CHROME_PATH or pass --browser with its executable path.');
}

const browserExecutable = await findBrowser();
const previewRoot = path.join(projectDirectory, 'build/previews');
await mkdir(previewRoot, { recursive: true });
const captureDirectory = path.join(previewRoot, `capture-${new Date().toISOString().replace(/[:.]/g, '-')}-${randomUUID().slice(0, 8)}`);
if (!isWithin(captureDirectory, previewRoot)) throw new Error('Unsafe preview output directory.');
await mkdir(captureDirectory);
const profileDirectory = await mkdtemp(path.join(captureDirectory, 'profile-'));
const diagnostics = [];
const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const mimeTypes = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8', '.wasm': 'application/wasm',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.gif': 'image/gif', '.webp': 'image/webp', '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon', '.woff': 'font/woff', '.woff2': 'font/woff2',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.map': 'application/json'
};

const server = http.createServer(async (request, response) => {
  try {
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      response.writeHead(405); response.end(); return;
    }
    const pathname = decodeURIComponent(new URL(request.url, 'http://127.0.0.1').pathname);
    // This preview server never proxies to PHP or any live backend.
    if (pathname === '/api' || pathname.startsWith('/api/')) {
      response.writeHead(404, { 'Content-Type': 'application/json' });
      response.end('{"error":"No live API in the visual preview server."}'); return;
    }
    let filename = path.resolve(webDirectory, `.${pathname}`);
    if (!isWithin(filename, webDirectory)) { response.writeHead(403); response.end(); return; }
    try {
      if ((await stat(filename)).isDirectory()) filename = path.join(filename, 'index.html');
      filename = await realpath(filename);
    } catch {
      if (path.extname(pathname)) { response.writeHead(404); response.end(); return; }
      filename = await realpath(path.join(webDirectory, 'index.html'));
    }
    if (!isWithin(filename, webDirectory)) { response.writeHead(403); response.end(); return; }
    const fileInfo = await stat(filename);
    if (!fileInfo.isFile()) { response.writeHead(404); response.end(); return; }
    response.writeHead(200, {
      'Content-Type': mimeTypes[path.extname(filename)] ?? 'application/octet-stream',
      'Content-Length': fileInfo.size,
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff'
    });
    if (request.method === 'HEAD') { response.end(); return; }
    const stream = createReadStream(filename);
    stream.on('error', () => response.destroy());
    stream.pipe(response);
  } catch {
    if (!response.headersSent) response.writeHead(400);
    response.end();
  }
});

class DevToolsClient {
  constructor(socket) {
    this.socket = socket;
    this.nextId = 1;
    this.pending = new Map();
    socket.addEventListener('message', event => {
      const message = JSON.parse(String(event.data));
      if (message.id) {
        const operation = this.pending.get(message.id);
        if (!operation) return;
        this.pending.delete(message.id);
        clearTimeout(operation.timer);
        if (message.error) operation.reject(new Error(`${operation.method}: ${message.error.message}`));
        else operation.resolve(message.result ?? {});
      } else if (['Runtime.exceptionThrown', 'Runtime.consoleAPICalled', 'Log.entryAdded', 'Network.loadingFailed'].includes(message.method)) {
        diagnostics.push({ method: message.method, params: message.params });
      }
    });
    socket.addEventListener('close', () => {
      for (const operation of this.pending.values()) {
        clearTimeout(operation.timer);
        operation.reject(new Error('Browser DevTools connection closed.'));
      }
      this.pending.clear();
    });
  }

  static async connect(url) {
    const socket = new WebSocket(url);
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => { socket.close(); reject(new Error('DevTools connection timed out.')); }, 15000);
      socket.addEventListener('open', () => { clearTimeout(timeout); resolve(); }, { once: true });
      socket.addEventListener('error', () => { clearTimeout(timeout); reject(new Error('Cannot open browser DevTools connection.')); }, { once: true });
    });
    return new DevToolsClient(socket);
  }

  send(method, params = {}, timeout = 15000) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`${method} timed out.`));
      }, timeout);
      this.pending.set(id, { method, resolve, reject, timer });
      try { this.socket.send(JSON.stringify({ id, method, params })); }
      catch (error) { clearTimeout(timer); this.pending.delete(id); reject(error); }
    });
  }
}

let browserProcess;
let devTools;
let browserExited = false;
try {
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const origin = `http://127.0.0.1:${server.address().port}`;
  console.log(`Preview server: ${origin} (${webDirectory})`);
  console.log(`Isolated browser: ${browserExecutable}`);
  browserProcess = spawn(browserExecutable, [
    '--headless=new', '--disable-gpu', '--enable-unsafe-swiftshader', '--no-first-run', '--no-default-browser-check',
    '--disable-extensions', '--disable-sync', '--disable-background-networking',
    '--remote-debugging-address=127.0.0.1', '--remote-debugging-port=0',
    `--user-data-dir=${profileDirectory}`, '--hide-scrollbars',
    '--force-device-scale-factor=1', 'about:blank'
  ], { windowsHide: true, stdio: ['ignore', 'ignore', 'pipe'] });
  browserProcess.once('exit', () => { browserExited = true; });
  browserProcess.on('error', error => diagnostics.push({ browserError: error.message }));
  browserProcess.stderr.on('data', data => {
    const text = data.toString();
    if (diagnostics.length < 300) diagnostics.push({ browserStderr: text.slice(0, 4000) });
  });

  let debuggerPort;
  const debuggerDeadline = Date.now() + 20000;
  while (Date.now() < debuggerDeadline) {
    if (browserExited) throw new Error('The isolated browser exited before DevTools started.');
    try {
      const portText = await readFile(path.join(profileDirectory, 'DevToolsActivePort'), 'utf8');
      const candidatePort = Number(portText.split('\n')[0]);
      if (Number.isInteger(candidatePort) && candidatePort > 0 && candidatePort < 65536) {
        debuggerPort = candidatePort; break;
      }
    } catch { /* Fresh browser has not written its debugging port yet. */ }
    await delay(150);
  }
  if (!debuggerPort) throw new Error('Browser did not publish its local DevTools port within 20 seconds.');
  const pages = await (await fetch(`http://127.0.0.1:${debuggerPort}/json/list`, { signal: AbortSignal.timeout(10000) })).json();
  const page = pages.find(candidate => candidate.type === 'page' && candidate.webSocketDebuggerUrl);
  if (!page) throw new Error('Browser DevTools did not expose a preview page.');
  devTools = await DevToolsClient.connect(page.webSocketDebuggerUrl);
  await devTools.send('Page.enable');
  await devTools.send('Runtime.enable');
  await devTools.send('Log.enable');
  await devTools.send('Network.enable');
  await devTools.send('Page.addScriptToEvaluateOnNewDocument', {
    source: 'window.__dreamstoreFirstFrame = false; window.addEventListener("flutter-first-frame", () => { window.__dreamstoreFirstFrame = true; }, { once: true });'
  });
  await devTools.send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: 'light' }, { name: 'prefers-reduced-motion', value: 'reduce' }] });

  for (const viewport of [
    { name: 'desktop', width: 1440, height: 1000, mobile: false },
    { name: 'phone', width: 390, height: 844, mobile: true }
  ]) {
    console.log(`Rendering ${viewport.name} (${viewport.width}x${viewport.height})...`);
    await devTools.send('Emulation.setDeviceMetricsOverride', {
      width: viewport.width, height: viewport.height, deviceScaleFactor: 1, mobile: viewport.mobile
    });
    await devTools.send('Emulation.setTouchEmulationEnabled', { enabled: viewport.mobile, maxTouchPoints: 1 });
    await devTools.send('Page.navigate', { url: `${origin}/?visual-preview=${viewport.name}` });
    const renderDeadline = Date.now() + 60000;
    let rendered = false;
    while (Date.now() < renderDeadline) {
      let evaluation;
      try {
        evaluation = await devTools.send('Runtime.evaluate', {
          expression: `(() => {
          const loading = document.getElementById('app-loading');
          if (loading && getComputedStyle(loading).opacity !== '0') return false;
          const surfaces = [];
          const inspect = root => {
            for (const element of root.querySelectorAll('*')) {
              if (element.tagName === 'CANVAS' || ['FLUTTER-VIEW', 'FLT-GLASS-PANE', 'FLT-SCENE-HOST'].includes(element.tagName)) surfaces.push(element);
              if (element.shadowRoot) inspect(element.shadowRoot);
            }
          };
          inspect(document);
          const visibleSurface = surfaces.some(surface => {
            const box = surface.getBoundingClientRect();
            return box.width > 100 && box.height > 100;
          });
          return visibleSurface && (window.__dreamstoreFirstFrame || !loading);
          })()`, returnByValue: true
        });
      } catch (error) {
        if (!/context.*(destroyed|not found)|cannot find context/i.test(error.message)) throw error;
        await delay(250);
        continue;
      }
      if (evaluation.result?.value === true) { rendered = true; break; }
      await delay(250);
    }
    if (!rendered) throw new Error(`Flutter did not render ${viewport.name} within 60 seconds; see browser-diagnostics.json.`);
    // Let fonts and short entry animations settle after the first painted view.
    await devTools.send('Runtime.evaluate', {
      expression: 'Promise.resolve(document.fonts.ready).then(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(() => setTimeout(resolve, 800)))))',
      awaitPromise: true
    });
    const screenshot = await devTools.send('Page.captureScreenshot', { format: 'png', fromSurface: true, captureBeyondViewport: false }, 30000);
    const screenshotPath = path.join(captureDirectory, `${viewport.name}.png`);
    await writeFile(screenshotPath, Buffer.from(screenshot.data, 'base64'), { flag: 'wx' });
    console.log(`Captured: ${screenshotPath}`);
  }
} finally {
  await writeFile(path.join(captureDirectory, 'browser-diagnostics.json'), JSON.stringify(diagnostics, null, 2), { flag: 'wx' }).catch(() => {});
  if (devTools) {
    await devTools.send('Browser.close', {}, 3000).catch(() => {});
    devTools.socket.close();
  }
  if (browserProcess && !browserExited) {
    await Promise.race([once(browserProcess, 'exit').catch(() => {}), delay(2000)]);
    if (!browserExited) browserProcess.kill(); // Only this newly spawned isolated browser.
  }
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  console.log(`Artifacts retained in ${captureDirectory}; no existing browser profile was opened or deleted.`);
}
