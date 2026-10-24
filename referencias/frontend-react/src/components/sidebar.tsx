import { NavLink } from "react-router-dom";
import {
  LayoutDashboard,
  Package,
  ChartNoAxesCombined,
  BrainCircuit,
  Settings,
  Boxes,
} from "lucide-react";

const menuItems = [
  { label: "Dashboard", path: "/", icon: LayoutDashboard },
  { label: "Inventario", path: "/inventario", icon: Package },
  { label: "Ventas", path: "/ventas", icon: ChartNoAxesCombined },
  { label: "Predicciones", path: "/predicciones", icon: BrainCircuit },
  { label: "Configuración", path: "/configuracion", icon: Settings },
];

export default function Sidebar() {
  return (
    <aside className="sidebar">
      <div className="brand">
        <div className="brand-icon">
          <Boxes size={23} />
        </div>

        <div>
          <h1>StockIA</h1>
          <span>Gestión inteligente</span>
        </div>
      </div>

      <span className="menu-label">MENÚ PRINCIPAL</span>

      <nav className="sidebar-nav">
        {menuItems.map(({ label, path, icon: Icon }) => (
          <NavLink
            key={path}
            to={path}
            end={path === "/"}
            className={({ isActive }) =>
              `nav-item ${isActive ? "active" : ""}`
            }
          >
            <Icon size={19} strokeWidth={1.8} />
            <span>{label}</span>
          </NavLink>
        ))}
      </nav>

      <div className="sidebar-footer">
        <div className="status-dot" />
        <span>Sistema de gestión</span>
      </div>
    </aside>
  );
}