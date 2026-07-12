import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const source = readFileSync(resolve(root, "panel/site/app.js"), "utf8");

function node() {
  return {
    textContent: "", value: "", innerHTML: "", hidden: true, disabled: false, readOnly: false,
    className: "", dataset: {}, href: "", scrollTop: 0, scrollHeight: 0,
    classList: { add() {}, remove() {} },
    addEventListener() {},
  };
}

const nodes = new Map();
const form = node();
form.domain = node();
form.email = node();
nodes.set("[data-deploy-form]", form);
const sandbox = {
  document: {
    querySelector(selector) { if (!nodes.has(selector)) nodes.set(selector, node()); return nodes.get(selector); },
    querySelectorAll() { return []; },
  },
  window: { location: { hash: "#token=" + "a".repeat(64), pathname: "/" }, CinquainPanel: null },
  sessionStorage: { getItem() { return null; }, setItem() {} },
  history: { replaceState() {} },
  URLSearchParams, FormData: class {},
  fetch: async () => ({ ok: false, status: 401, json: async () => ({ error: "unauthorized" }) }),
  setInterval() {}, navigator: { clipboard: { writeText: async () => {} } }, console,
};
sandbox.window.window = sandbox.window;
Object.assign(sandbox, sandbox.window);
vm.createContext(sandbox);
vm.runInContext(source, sandbox, { filename: "app.js" });

assert.equal(sandbox.window.CinquainPanel.escapeHtml('<script>"'), "&lt;script&gt;&quot;");
assert.equal(sandbox.window.CinquainPanel.serviceName({ Service: "Homeserver" }), "homeserver");
assert.match(source, /X-Cinquain-Token/);
assert.doesNotMatch(source, /localStorage/);
console.log("panel-ui: OK");
