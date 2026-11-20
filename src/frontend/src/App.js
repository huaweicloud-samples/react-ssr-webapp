import React, { useEffect, useState } from "react";
import ProductList from "./components/ProductList";
import config from "./config.json";
import axios from "axios";

// Data injected by the server-rendered page (window.__INITIAL_DATA__).
// When present the client reuses it instead of fetching again, keeping
// hydration consistent with the server markup.
const initialData =
  typeof window !== "undefined" && Array.isArray(window.__INITIAL_DATA__)
    ? window.__INITIAL_DATA__
    : null;

const App = () => {
  const [err, setErr] = useState(false);
  const [result, setResult] = useState(
    initialData
      ? { loading: false, products: initialData }
      : { loading: true, products: null }
  );
  useEffect(() => {
    if (initialData) {
      return;
    }
    const getData = async () => {
      const url = config.api.productsUrl;
      try {
        let result = await axios.get(url);
        setResult({ loading: false, products: result.data });
      } catch (error) {
        setErr(error);
      }
    };
    getData();
  }, []);
  if (err) {
    return <div>Error {String(err)}</div>;
  } else {
    return (
      <div>
        <ProductList result={result} />
      </div>
    );
  }
};

export default App;
