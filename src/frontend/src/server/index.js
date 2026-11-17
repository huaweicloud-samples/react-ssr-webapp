import React from "react";
import ReactDOMServer from "react-dom/server";
import https from "https";
import SSRApp from "../SSRApp";
import assets from "../build-assets.json";

// Injected by Terraform (huaweicloud_fgs_function user_data).
const REGION = process.env.REGION || "cn-north-4";
const PROJECT_ID = process.env.PROJECT_ID || "";
const API_FUNCTION_URN = process.env.API_FUNCTION_URN || "";
const STATIC_BASE_URL = (process.env.STATIC_BASE_URL || "").replace(/\/$/, "");

// Invoke the products API function synchronously through the FunctionGraph
// invocation endpoint, authenticated with the platform token provided to
// this function's execution context.
function invokeApiFunction(token) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify({ source: "ssr-render" });
    const urnPath = API_FUNCTION_URN.split("/")
      .map(encodeURIComponent)
      .join("/");
    const options = {
      hostname: `functiongraph.${REGION}.myhuaweicloud.com`,
      path: `/v2/${PROJECT_ID}/fgs/functions/${urnPath}/invocations`,
      method: "POST",
      headers: {
        "X-Auth-Token": token,
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(payload),
      },
    };
    const request = https.request(options, (response) => {
      let data = "";
      response.on("data", (chunk) => {
        data += chunk;
      });
      response.on("end", () => {
        if (response.statusCode !== 200) {
          reject(
            new Error(`api function invoke failed: HTTP ${response.statusCode}: ${data}`)
          );
          return;
        }
        resolve(data);
      });
    });
    request.on("error", reject);
    request.end(payload);
  });
}

// The synchronous invocation response body is the JSON serialization of the
// target function's return value ({ statusCode, headers, body }); the product
// list itself lives in that body field as a JSON string.
function extractProducts(raw) {
  const parsed = JSON.parse(raw);
  if (Array.isArray(parsed)) {
    return parsed;
  }
  if (parsed && typeof parsed.body === "string") {
    return JSON.parse(parsed.body);
  }
  throw new Error("unexpected api function response shape");
}

function assetTags() {
  const css = (assets.css || []).map(
    (file) => `<link rel="stylesheet" href="${STATIC_BASE_URL}/${file}" />`
  );
  const js = (assets.js || []).map(
    (file) => `<script defer src="${STATIC_BASE_URL}/${file}"></script>`
  );
  const icons = [
    `<link rel="icon" href="${STATIC_BASE_URL}/favicon.ico" />`,
    `<link rel="apple-touch-icon" href="${STATIC_BASE_URL}/logo192.png" />`,
    `<link rel="manifest" href="${STATIC_BASE_URL}/manifest.json" />`,
  ];
  return [...icons, ...css, ...js].join("\n    ");
}

function renderPage(products) {
  const appHtml = ReactDOMServer.renderToString(<SSRApp data={products} />);
  const initialData = JSON.stringify(products).replace(/</g, "\\u003c");
  return `<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#000000" />
    <meta
      name="description"
      content="React server-side rendering sample on FunctionGraph"
    />
    <title>React SSR App</title>
    ${assetTags()}
  </head>
  <body>
    <noscript>You need to enable JavaScript to run this app.</noscript>
    <div id="root">${appHtml}</div>
    <div>Rendered on Server</div>
    <script>window.__INITIAL_DATA__ = ${initialData};</script>
  </body>
</html>`;
}

export const handler = async (event, context) => {
  try {
    const token = context.getToken();
    const raw = await invokeApiFunction(token);
    const products = extractProducts(raw);
    const html = renderPage(products);
    return {
      statusCode: 200,
      headers: { "Content-Type": "text/html; charset=utf-8" },
      isBase64Encoded: false,
      body: html,
    };
  } catch (error) {
    console.log(`SSR render error: ${error && error.message}`);
    return {
      statusCode: 500,
      headers: { "Content-Type": "text/plain; charset=utf-8" },
      isBase64Encoded: false,
      body: `SSR render failed: ${error && error.message}`,
    };
  }
};
