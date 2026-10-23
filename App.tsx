import { BrowserRouter, Route, Routes } from "react-router-dom";
import { Construction } from "lucide-react";

import MainLayout from "./layouts/MainLayouts";
import Dashboard from "./pages/Dashboard";

function PlaceholderPage({ title }: { title: string }) {
  return (
    <section className="placeholder-page panel">
      <div className="placeholder-icon">
        <Construction size={28} />
      </div>
      <h1>{title}</h1>
      <p>
        Esta sección está preparada para su próximo desarrollo.
        Vamos a integrarla progresivamente con los datos de StockIA.
      </p>
    </section>
  );
}

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route element={<MainLayout />}>
          <Route index element={<Dashboard />} />

          <Route
            path="inventario"
            element={<PlaceholderPage title="Inventario" />}
          />

          <Route
            path="ventas"
            element={<PlaceholderPage title="Ventas" />}
          />

          <Route
            path="predicciones"
            element={<PlaceholderPage title="Predicciones de demanda" />}
          />

          <Route
            path="configuracion"
            element={<PlaceholderPage title="Configuración" />}
          />
        </Route>
      </Routes>
    </BrowserRouter>
  );
}