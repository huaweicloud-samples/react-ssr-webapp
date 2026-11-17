"use strict";

// Local smoke test for the SSR server bundle.
// Stubs the FunctionGraph invocation endpoint (https.request) and renders
// the page exactly as the deployed handler would.

const assert = require("assert");
const https = require("https");

process.env.REGION = "cn-north-4";
process.env.PROJECT_ID = "test-project";
process.env.API_FUNCTION_URN =
  "urn:hcs:funcgraph:cn-north-4:test-project:function:default:rsw-api";
process.env.STATIC_BASE_URL =
  "https://example-bucket.obs.cn-north-4.myhuaweicloud.com";

const PRODUCTS = [
  { id: 1, name: "item 1", desc: "product 1 description", price: "1.00" },
  { id: 2, name: "item 2", desc: "product 2 description", price: "2.00" },
  { id: 3, name: "item 3", desc: "product 3 description", price: "3.00" },
  { id: 4, name: "item 4", desc: "product 4 description", price: "4.00" },
  { id: 5, name: "item 5", desc: "product 5 description", price: "5.00" },
];

let observed = null;

// Patch https.request BEFORE loading the bundle so the stub is picked up.
https.request = (options, callback) => {
  observed = {
    hostname: options.hostname,
    path: options.path,
    token: options.headers["X-Auth-Token"],
  };
  const body = JSON.stringify({
    statusCode: 200,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(PRODUCTS),
  });
  const response = {
    statusCode: 200,
    on(event, fn) {
      if (event === "data") fn(body);
      if (event === "end") fn();
      return response;
    },
  };
  return {
    on() {},
    end() {
      callback(response);
    },
  };
};

const bundle = require("../dist/server-build/index.js");

(async () => {
  const result = await bundle.handler({}, { getToken: () => "stub-token" });

  assert.strictEqual(result.statusCode, 200, "status code");
  assert.ok(String(result.headers["Content-Type"]).startsWith("text/html"), "content type");
  assert.strictEqual(result.isBase64Encoded, false, "html must not be base64");

  assert.strictEqual(observed.hostname, "functiongraph.cn-north-4.myhuaweicloud.com");
  assert.ok(observed.path.startsWith("/v2/test-project/fgs/functions/"), observed.path);
  assert.ok(observed.path.includes("urn%3Ahcs%3Afuncgraph"), "URN must be URL encoded");
  assert.ok(observed.path.endsWith("/invocations"));
  assert.strictEqual(observed.token, "stub-token");

  const html = result.body;
  assert.ok(html.includes("Rendered on Server"), "SSR marker");
  // React SSR separates text nodes with <!-- --> markers.
  assert.ok(html.includes(">Product <!-- -->item 1</h1>"), "rendered product name");
  assert.ok(html.includes("Price $<!-- -->1.00"), "rendered product price");
  assert.ok(html.includes("product 5 description"), "all products rendered");
  assert.ok(html.includes("window.__INITIAL_DATA__"), "hydration data script");
  assert.ok(!html.includes("<script>window.__INITIAL_DATA__ = [];"), "data not empty");

  const jsMatch = html.match(/src="(https:\/\/[^"]+\.js)"/);
  assert.ok(jsMatch, "client bundle reference present");
  assert.ok(jsMatch[1].startsWith(process.env.STATIC_BASE_URL), "asset URL prefix");
  // This app ships no CSS; assert css links only when the manifest lists some.
  const manifest = require("../frontend/src/build-assets.json");
  for (const file of manifest.css || []) {
    assert.ok(html.includes(`${process.env.STATIC_BASE_URL}/${file}`), `css reference ${file}`);
  }

  const mem = process.memoryUsage();
  console.log(
    JSON.stringify(
      {
        passed: true,
        rssMB: Math.round(mem.rss / 1048576),
        heapUsedMB: Math.round(mem.heapUsed / 1048576),
        htmlBytes: html.length,
        invokePath: observed.path,
        firstAssetUrl: jsMatch[1],
      },
      null,
      2
    )
  );
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
