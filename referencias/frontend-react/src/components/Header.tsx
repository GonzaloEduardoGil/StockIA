import { Bell, CalendarDays } from "lucide-react";
import { useLocation } from "react-router-dom";

const pageTitles: Record<string, string> = {
  "/": "Dashboard",
  "/inventario": "Inventario",
  "/ventas": "Ventas",
  "/predicciones": "Predicciones de demanda",
  "/configuracion": "Configuración",
};

export default function Header() {
  const location = useLocation();
  const title = pageTitles[location.pathname] ?? "StockIA";

  const fecha = new Intl.DateTimeFormat("es-AR", {
    day: "numeric",
    month: "long",
    year: "numeric",
  }).format(new Date());

  return (
    <header className="topbar">
      <div>
        <span className="breadcrumb">StockIA / Gestión</span>
        <h2>{title}</h2>
      </div>

      <div className="header-actions">
        <div className="date-display">
          <CalendarDays size={17} />
          <span>{fecha}</span>
        </div>

        <button
          className="icon-button"
          type="button"
          aria-label="Notificaciones"
          title="Notificaciones"
        >
          <Bell size={19} />
        </button>

        <div className="user-profile">
          <div className="avatar">AD</div>
          <div className="user-info">
            <strong>Administrador</strong>
            <span>Panel de gestión</span>
          </div>
        </div>
      </div>
    </header>
  );
}