import React from "react";
import { hydrateRoot, createRoot } from "react-dom/client";
import App from "./App";

const container = document.getElementById("root");
const appElement = (
  <React.StrictMode>
    <App />
  </React.StrictMode>
);

if (container.hasChildNodes()) {
  // Server-rendered markup present: hydrate without re-rendering from scratch.
  hydrateRoot(container, appElement);
} else {
  createRoot(container).render(appElement);
}
