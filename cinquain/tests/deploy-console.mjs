import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const __dirname = dirname(fileURLToPath(import.meta.url));
const appPath = resolve(__dirname, "../site/assets/app.js");

function makeElement() {
    const classes = new Set();

    return {
        checked: false,
        textContent: "",
        value: "",
        classList: {
            contains(name) {
                return classes.has(name);
            },
            toggle(name, enabled) {
                if (enabled) {
                    classes.add(name);
                } else {
                    classes.delete(name);
                }
            },
        },
        addEventListener() {},
        getAttribute() {
            return "";
        },
        setAttribute() {},
    };
}

function loadDeployConsole(host = "localhost:8080") {
    const domainInput = makeElement();
    const emailInput = makeElement();
    const imageInput = makeElement();
    const localBuildInput = makeElement();
    const envOutput = makeElement();
    const installOutput = makeElement();
    const existingRepoOutput = makeElement();
    const liveDomain = makeElement();
    const liveEmail = makeElement();
    const validationNode = makeElement();
    const serverNameNode = makeElement();
    const listeners = {};

    const form = {
        addEventListener(name, handler) {
            listeners[name] = handler;
        },
        querySelector(selector) {
            return {
                "[name='domain']": domainInput,
                "[name='email']": emailInput,
                "[name='image']": imageInput,
                "[name='localBuild']": localBuildInput,
            }[selector] || null;
        },
    };

    const selectors = {
        "[data-deploy-form]": form,
        "[data-deploy-validation]": validationNode,
        "#env-output": envOutput,
        "#install-output": installOutput,
        "#existing-repo-output": existingRepoOutput,
        "[data-live-domain]": liveDomain,
        "[data-live-email]": liveEmail,
    };

    const storage = new Map();
    const sandbox = {
        document: {
            body: makeElement(),
            createElement: makeElement,
            querySelector(selector) {
                return selectors[selector] || null;
            },
            querySelectorAll(selector) {
                if (selector === "[data-server-name]") {
                    return [serverNameNode];
                }
                if (selector === "[data-copy-target]") {
                    return [];
                }
                return [];
            },
        },
        navigator: {},
        window: {
            location: { host },
            localStorage: {
                getItem(key) {
                    return storage.get(key) || null;
                },
                setItem(key, value) {
                    storage.set(key, value);
                },
            },
            setTimeout() {},
        },
    };

    vm.createContext(sandbox);
    vm.runInContext(readFileSync(appPath, "utf8"), sandbox, { filename: appPath });

    return {
        helpers: sandbox.window.CinquainDeploy,
        fields: { domainInput, emailInput, imageInput, localBuildInput },
        outputs: { envOutput, installOutput, existingRepoOutput, liveDomain, liveEmail, validationNode },
        listeners,
        storage,
    };
}

const { helpers, fields, outputs, listeners } = loadDeployConsole("LOCALHOST:8080");

assert.equal(helpers.normaliseDomain("HTTPS://Matrix.Example.COM:443/path "), "matrix.example.com");
assert.equal(helpers.isLikelyDomain("matrix.example.com"), true);
assert.equal(helpers.isLikelyDomain("matrix.example.com:443"), false);
assert.equal(helpers.isLikelyEmail("ops+test@example.org"), true);
assert.equal(helpers.shellQuote("ops'test@example.org"), "'ops'\\''test@example.org'");

const values = {
    domain: "matrix.azuredream.indevs.in",
    email: "mcxiaocai666@proton.me",
    image: "ghcr.io/mcxiaocaibug/cinquain:main",
    localBuild: false,
};

assert.match(helpers.buildEnv(values), /^CINQUAIN_SERVER_NAME=matrix\.azuredream\.indevs\.in$/m);
assert.match(helpers.buildEnv(values), /^CINQUAIN_RUST_PROFILE=release-fast$/m);
assert.match(helpers.buildInstallCommand(values), /CINQUAIN_BUILD_LOCALLY=0/);
assert.match(helpers.buildInstallCommand(values), /CINQUAIN_HOMESERVER_IMAGE='ghcr\.io\/mcxiaocaibug\/cinquain:main'/);
assert.match(helpers.buildInstallCommand(values), /\.\/install\.sh 'matrix\.azuredream\.indevs\.in' 'mcxiaocai666@proton\.me'/);

fields.domainInput.value = "https://Matrix.Azuredream.InDevs.In:443/install";
fields.emailInput.value = "mcxiaocai666@proton.me";
fields.imageInput.value = "ghcr.io/example/cinquain:test";
fields.localBuildInput.checked = true;
listeners.input();

assert.equal(outputs.liveDomain.textContent, "matrix.azuredream.indevs.in");
assert.equal(outputs.liveEmail.textContent, "mcxiaocai666@proton.me");
assert.match(outputs.envOutput.textContent, /^CINQUAIN_BUILD_LOCALLY=1$/m);
assert.match(outputs.installOutput.textContent, /CINQUAIN_BUILD_LOCALLY=1/);
assert.match(outputs.installOutput.textContent, /CINQUAIN_HOMESERVER_IMAGE='ghcr\.io\/example\/cinquain:test'/);
assert.equal(outputs.validationNode.classList.contains("notice--success"), true);

console.log("deploy-console: OK");
