"use strict";

// Products API function: returns the built-in product catalog as JSON.
// Fronted by an APIG API (request path /api/{proxy}); also invoked directly
// by the ssr-render function through the FunctionGraph invocation endpoint.

const PRODUCTS = [
  { id: 1, name: "item 1", desc: "product 1 description", price: "1.00" },
  { id: 2, name: "item 2", desc: "product 2 description", price: "2.00" },
  { id: 3, name: "item 3", desc: "product 3 description", price: "3.00" },
  { id: 4, name: "item 4", desc: "product 4 description", price: "4.00" },
  { id: 5, name: "item 5", desc: "product 5 description", price: "5.00" },
];

exports.handler = async (event, context) => {
  try {
    return {
      statusCode: 200,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
      isBase64Encoded: false,
      body: JSON.stringify(PRODUCTS),
    };
  } catch (error) {
    return {
      statusCode: 500,
      headers: { "Content-Type": "application/json" },
      isBase64Encoded: false,
      body: JSON.stringify({ error: String(error && error.message) }),
    };
  }
};
