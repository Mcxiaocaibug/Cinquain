(function () {
    var serverName = window.location.host || "this server";
    var nodes = document.querySelectorAll("[data-server-name]");

    nodes.forEach(function (node) {
        node.textContent = serverName;
    });
})();
