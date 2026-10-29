/* Shared browser request handling. Also imported by Node's behavior tests. */
(function () {
  "use strict";

  async function requestJson(url, options, dependencies) {
    var settings = dependencies || {};
    var controller = new AbortController();
    var timeout = setTimeout(function () { controller.abort(); }, settings.timeoutMs || 15000);
    try {
      var response = await (settings.fetch || fetch)(url, Object.assign({}, options, { signal: controller.signal }));
      if (!response.ok) {
        var error = new Error("request_failed");
        error.status = response.status;
        throw error;
      }
      return await response.json();
    } finally {
      clearTimeout(timeout);
    }
  }

  function createListLoader(url, key, render, dependencies) {
    var loading = false;
    return async function load() {
      if (loading) return;
      loading = true;
      render({ status: "loading", items: [] });
      try {
        var data = await requestJson(url, undefined, dependencies);
        if (!data || !Array.isArray(data[key])) throw new Error("invalid_response");
        render({ status: data[key].length ? "ready" : "empty", items: data[key] });
      } catch (_) {
        render({ status: "error", items: [] });
      } finally {
        loading = false;
      }
    };
  }

  globalThis.RegenData = { requestJson: requestJson, createListLoader: createListLoader };
})();
