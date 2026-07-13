(() => {
  "use strict";

  const $ = (selector) => document.querySelector(selector);
  const token = new URLSearchParams(window.location.hash.slice(1)).get("token") || sessionStorage.getItem("cinquain-token") || "";
  if (token) {
    sessionStorage.setItem("cinquain-token", token);
    history.replaceState(null, "", window.location.pathname);
  }

  const state = { busy: false, configured: false, domain: "" };
  const headers = { "Content-Type": "application/json", "X-Cinquain-Token": token };

  async function api(path, options = {}) {
    const response = await fetch(path, { ...options, headers: { ...headers, ...(options.headers || {}) } });
    const body = await response.json().catch(() => ({ ok: false, error: "服务返回了无效响应。" }));
    if (!response.ok) throw new Error(body.error || `HTTP ${response.status}`);
    return body;
  }

  function setFeedback(message, kind = "") {
    const node = $("[data-feedback]");
    node.textContent = message;
    node.className = `feedback ${kind}`;
  }

  function serviceName(row) {
    return String(row.Service || row.Name || "").toLowerCase();
  }

  function renderServices(rows) {
    const services = ["homeserver", "caddy"];
    $("[data-services]").innerHTML = services.map((name) => {
      const row = rows.find((item) => serviceName(item).includes(name));
      const status = String(row?.State || row?.Status || "未启动");
      const live = /running|up/i.test(status);
      return `<div><span class="service-dot ${live ? "live" : ""}"></span>${name}<b>${escapeHtml(status)}</b></div>`;
    }).join("");
  }

  function escapeHtml(value) {
    return String(value).replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);
  }

  function renderOperation(operation) {
    state.busy = Boolean(operation.running);
    $("[data-operation]").textContent = operation.running ? `${operation.name} 执行中` : operation.exit_code === 0 ? `${operation.name} 已完成` : operation.exit_code == null ? "等待操作" : `${operation.name} 失败 (${operation.exit_code})`;
    $("[data-log]").textContent = operation.log || "部署日志将在这里实时显示。";
    $("[data-log]").scrollTop = $("[data-log]").scrollHeight;
    $("[data-deploy-button]").disabled = state.busy;
    document.querySelectorAll("[data-action]").forEach((button) => { button.disabled = state.busy || !state.configured; });
  }

  async function refresh() {
    try {
      const result = await api("/api/status");
      state.configured = result.configured;
      state.domain = result.domain || "";
      $("[data-version]").textContent = result.version;
      $("[data-domain]").textContent = result.domain || "尚未配置";
      $("[data-image]").textContent = result.image || "—";
      $("[data-status-dot]").classList.add("live");
      $("[data-status-label]").textContent = "面板已连接";
      renderServices(result.containers || []);
      renderOperation(result.operation);
      if (result.configured && result.domain) {
        const form = $("[data-deploy-form]");
        if (!form.domain.value) form.domain.value = result.domain;
        if (!form.email.value) form.email.value = result.email || "";
        form.domain.readOnly = Boolean(result.domain_locked);
        $("[data-onboarding]").hidden = false;
        $("[data-register-link]").href = `https://${result.domain}/_continuwuity/account/register/`;
        await refreshToken();
      }
    } catch (error) {
      $("[data-status-dot]").classList.remove("live");
      $("[data-status-label]").textContent = token ? "连接失败" : "需要面板令牌";
      if (!token) setFeedback("请使用 bootstrap.sh 输出的带令牌地址打开面板。", "error");
    }
  }

  async function refreshToken() {
    try {
      const result = await api("/api/registration-token");
      $("[data-registration-token]").textContent = result.token || "管理员已创建，或令牌尚未生成";
      $("[data-copy-token]").disabled = !result.token;
    } catch (_) { /* status refresh will surface authentication errors */ }
  }

  $("[data-deploy-form]").addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    const payload = Object.fromEntries(new FormData(form));
    payload.http_port = Number(payload.http_port);
    payload.https_port = Number(payload.https_port);
    payload.backup_retention = Number(payload.backup_retention);
    delete payload.immutable;
    try {
      setFeedback("正在验证配置并启动部署……");
      await api("/api/deploy", { method: "POST", body: JSON.stringify(payload) });
      setFeedback("部署已启动，可在右侧查看实时日志。", "success");
      await refresh();
    } catch (error) {
      setFeedback(error.message, "error");
    }
  });

  document.querySelectorAll("[data-action]").forEach((button) => button.addEventListener("click", async () => {
    try {
      await api("/api/action", { method: "POST", body: JSON.stringify({ action: button.dataset.action }) });
      setFeedback(`${button.textContent} 已启动。`, "success");
      await refresh();
    } catch (error) { setFeedback(error.message, "error"); }
  }));

  $("[data-copy-token]").addEventListener("click", async () => {
    const value = $("[data-registration-token]").textContent;
    await navigator.clipboard.writeText(value);
    $("[data-copy-token]").textContent = "已复制";
  });

  window.CinquainPanel = { escapeHtml, serviceName };
  refresh();
  setInterval(refresh, 2500);
})();
