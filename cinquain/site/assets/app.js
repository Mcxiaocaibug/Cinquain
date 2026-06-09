(function () {
    var host = window.location.host || "";
    var serverName = host.replace(/:\d+$/, "") || "your domain";
    var nodes = document.querySelectorAll("[data-server-name]");

    nodes.forEach(function (node) {
        node.textContent = serverName;
    });

    function normaliseDomain(value) {
        return (value || "")
            .trim()
            .replace(/^https?:\/\//, "")
            .replace(/\/.*$/, "")
            .replace(/\s+/g, "");
    }

    function isLikelyDomain(value) {
        return /^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$/i.test(value);
    }

    function isLikelyEmail(value) {
        return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value || "");
    }

    function setText(selector, text) {
        var node = document.querySelector(selector);
        if (node) {
            node.textContent = text;
        }
    }

    function buildEnv(values) {
        return [
            "CINQUAIN_STACK_NAME=cinquain",
            "CINQUAIN_BUILD_LOCALLY=" + (values.localBuild ? "1" : "0"),
            "CINQUAIN_HOMESERVER_IMAGE=" + values.image,
            "CINQUAIN_SERVER_NAME=" + values.domain,
            "CINQUAIN_BOOTSTRAP_SECRET=",
            "CINQUAIN_ACME_EMAIL=" + values.email,
            "CINQUAIN_SUPPORT_EMAIL=" + values.email,
            "CINQUAIN_HTTP_PORT=80",
            "CINQUAIN_HTTPS_PORT=443",
            "CINQUAIN_BACKUP_BEFORE_UPGRADE=1"
        ].join("\n");
    }

    function buildInstallCommand(values) {
        return [
            "git clone https://github.com/Mcxiaocaibug/Cinquain.git",
            "cd Cinquain/cinquain",
            "./install.sh " + values.domain + " " + values.email
        ].join("\n");
    }

    function buildExistingRepoCommand(values) {
        return [
            "cd cinquain",
            "./install.sh " + values.domain + " " + values.email
        ].join("\n");
    }

    function copyText(text, button) {
        function markCopied() {
            var original = button.textContent;
            button.textContent = "Copied";
            window.setTimeout(function () {
                button.textContent = original;
            }, 1400);
        }

        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(markCopied);
            return;
        }

        var textarea = document.createElement("textarea");
        textarea.value = text;
        textarea.setAttribute("readonly", "readonly");
        textarea.style.position = "fixed";
        textarea.style.opacity = "0";
        document.body.appendChild(textarea);
        textarea.select();
        document.execCommand("copy");
        document.body.removeChild(textarea);
        markCopied();
    }

    document.querySelectorAll("[data-copy-target]").forEach(function (button) {
        button.addEventListener("click", function () {
            var target = document.querySelector(button.getAttribute("data-copy-target"));
            if (target) {
                copyText(target.textContent, button);
            }
        });
    });

    var form = document.querySelector("[data-deploy-form]");
    if (!form) {
        return;
    }

    var domainInput = form.querySelector("[name='domain']");
    var emailInput = form.querySelector("[name='email']");
    var imageInput = form.querySelector("[name='image']");
    var localBuildInput = form.querySelector("[name='localBuild']");
    var validationNode = document.querySelector("[data-deploy-validation]");
    var defaultDomain = isLikelyDomain(serverName) ? serverName : "matrix.example.com";
    var saved = {};

    try {
        saved = JSON.parse(window.localStorage.getItem("cinquainDeploy") || "{}");
    } catch (error) {
        saved = {};
    }

    domainInput.value = saved.domain || defaultDomain;
    emailInput.value = saved.email || "admin@example.com";
    imageInput.value = saved.image || "ghcr.io/mcxiaocaibug/cinquain:main";
    localBuildInput.checked = saved.localBuild === true;

    function currentValues() {
        return {
            domain: normaliseDomain(domainInput.value),
            email: emailInput.value.trim(),
            image: imageInput.value.trim() || "ghcr.io/mcxiaocaibug/cinquain:main",
            localBuild: localBuildInput.checked
        };
    }

    function render() {
        var values = currentValues();
        var issues = [];

        if (!isLikelyDomain(values.domain) || values.domain === "matrix.example.com") {
            issues.push("Use the real Matrix domain that already points to the server.");
        }

        if (!isLikelyEmail(values.email) || values.email === "admin@example.com") {
            issues.push("Use a real operator email for TLS and support metadata.");
        }

        setText("#env-output", buildEnv(values));
        setText("#install-output", buildInstallCommand(values));
        setText("#existing-repo-output", buildExistingRepoCommand(values));
        setText("[data-live-domain]", values.domain || "matrix.example.com");
        setText("[data-live-email]", values.email || "admin@example.com");

        validationNode.textContent = issues.length ? issues.join(" ") : "Ready: DNS, TLS, database, reverse proxy, and Matrix discovery are handled by the stack.";
        validationNode.classList.toggle("notice--error", issues.length > 0);
        validationNode.classList.toggle("notice--success", issues.length === 0);

        try {
            window.localStorage.setItem("cinquainDeploy", JSON.stringify(values));
        } catch (error) {
            // Storage is optional; the generated commands still work without it.
        }
    }

    form.addEventListener("input", render);
    form.addEventListener("change", render);
    render();
})();
