import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import {
  ArrowDownRight,
  ArrowUpRight,
  AlertTriangle,
  Boxes,
  CircleDollarSign,
  Package,
  ShoppingCart,
} from "lucide-react";

const ventasMensuales = [
  { mes: "May", ventas: 320000 },
  { mes: "Jun", ventas: 385000 },
  { mes: "Jul", ventas: 350000 },
  { mes: "Ago", ventas: 460000 },
  { mes: "Sep", ventas: 430000 },
  { mes: "Oct", ventas: 520000 },
];

const estadoInventario = [
  { categoria: "Electrónica", normal: 68, bajo: 12 },
  { categoria: "Accesorios", normal: 82, bajo: 18 },
  { categoria: "Periféricos", normal: 54, bajo: 21 },
  { categoria: "Almacenamiento", normal: 73, bajo: 9 },
];

const productosStockBajo = [
  { nombre: "Mouse inalámbrico", codigo: "ACC-001", stock: 3, minimo: 10 },
  { nombre: "Teclado mecánico", codigo: "PER-014", stock: 5, minimo: 12 },
  { nombre: "Cable USB-C", codigo: "CAB-008", stock: 7, minimo: 20 },
  { nombre: "SSD 1 TB", codigo: "ALM-003", stock: 2, minimo: 6 },
];

const alertas = [
  {
    titulo: "Stock crítico",
    descripcion: "SSD 1 TB tiene solo 2 unidades disponibles.",
    tipo: "critical",
  },
  {
    titulo: "Reposición recomendada",
    descripcion: "El mouse inalámbrico está por debajo del mínimo.",
    tipo: "warning",
  },
];

function formatCurrency(value: number) {
  return new Intl.NumberFormat("es-AR", {
    style: "currency",
    currency: "ARS",
    maximumFractionDigits: 0,
  }).format(value);
}

type KpiCardProps = {
  title: string;
  value: string;
  detail: string;
  trend: "up" | "down";
  icon: typeof Package;
};

function KpiCard({
  title,
  value,
  detail,
  trend,
  icon: Icon,
}: KpiCardProps) {
  return (
    <article className="kpi-card">
      <div className="kpi-top">
        <span>{title}</span>
        <div className="kpi-icon">
          <Icon size={20} />
        </div>
      </div>

      <strong className="kpi-value">{value}</strong>

      <div className="kpi-detail">
        {trend === "up" ? (
          <ArrowUpRight size={16} />
        ) : (
          <ArrowDownRight size={16} />
        )}
        <span>{detail}</span>
      </div>
    </article>
  );
}

export default function Dashboard() {
  return (
    <div className="dashboard">
      <section className="welcome-section">
        <div>
          <h1>Resumen general</h1>
          <p>
            Visualizá el estado de tu inventario y el rendimiento del negocio.
          </p>
        </div>

        <span className="demo-badge">Datos de demostración</span>
      </section>

      <section className="kpi-grid">
        <KpiCard
          title="Productos registrados"
          value="248"
          detail="+12 este mes"
          trend="up"
          icon={Package}
        />

        <KpiCard
          title="Ventas del mes"
          value={formatCurrency(520000)}
          detail="+8,4% vs. mes anterior"
          trend="up"
          icon={CircleDollarSign}
        />

        <KpiCard
          title="Unidades en inventario"
          value="1.846"
          detail="En todos los productos"
          trend="up"
          icon={Boxes}
        />

        <KpiCard
          title="Productos con stock bajo"
          value="12"
          detail="Requieren revisión"
          trend="down"
          icon={ShoppingCart}
        />
      </section>

      <section className="charts-grid">
        <article className="panel sales-panel">
          <div className="panel-header">
            <div>
              <h3>Evolución de ventas</h3>
              <p>Facturación mensual</p>
            </div>

            <span className="period-label">Últimos 6 meses</span>
          </div>

          <div className="chart-container">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart
                data={ventasMensuales}
                margin={{ top: 10, right: 10, left: 5, bottom: 0 }}
              >
                <defs>
                  <linearGradient
                    id="salesGradient"
                    x1="0"
                    y1="0"
                    x2="0"
                    y2="1"
                  >
                    <stop
                      offset="0%"
                      stopColor="#315A86"
                      stopOpacity={0.22}
                    />
                    <stop
                      offset="95%"
                      stopColor="#315A86"
                      stopOpacity={0}
                    />
                  </linearGradient>
                </defs>

                <CartesianGrid
                  stroke="#E9EDF2"
                  strokeDasharray="4 4"
                  vertical={false}
                />

                <XAxis
                  dataKey="mes"
                  axisLine={false}
                  tickLine={false}
                  tick={{ fill: "#78869A", fontSize: 12 }}
                  dy={10}
                />

                <YAxis
                  tickFormatter={(value: number) =>
                    `${Math.round(value / 1000)}k`
                  }
                  axisLine={false}
                  tickLine={false}
                  tick={{ fill: "#78869A", fontSize: 12 }}
                  width={48}
                />

                <Tooltip
                  formatter={(value) => [
                    formatCurrency(Number(value)),
                    "Ventas",
                  ]}
                  contentStyle={{
                    borderRadius: 10,
                    border: "1px solid #E5EAF0",
                  }}
                />

                <Area
                  type="monotone"
                  dataKey="ventas"
                  stroke="#315A86"
                  strokeWidth={2.5}
                  fill="url(#salesGradient)"
                  activeDot={{ r: 5 }}
                />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </article>

        <article className="panel inventory-panel">
          <div className="panel-header">
            <div>
              <h3>Estado del inventario</h3>
              <p>Unidades por categoría</p>
            </div>
          </div>

          <div className="chart-container">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart
                data={estadoInventario}
                layout="vertical"
                margin={{ top: 5, right: 10, left: 10, bottom: 5 }}
                barSize={14}
              >
                <CartesianGrid
                  stroke="#E9EDF2"
                  strokeDasharray="4 4"
                  horizontal={false}
                />

                <XAxis type="number" hide />

                <YAxis
                  type="category"
                  dataKey="categoria"
                  axisLine={false}
                  tickLine={false}
                  width={100}
                  tick={{ fill: "#65748B", fontSize: 11 }}
                />

                <Tooltip />

                <Bar
                  dataKey="normal"
                  name="Stock normal"
                  stackId="stock"
                  fill="#315A86"
                  radius={[0, 4, 4, 0]}
                />

                <Bar
                  dataKey="bajo"
                  name="Stock bajo"
                  stackId="stock"
                  fill="#D7A44A"
                  radius={[0, 4, 4, 0]}
                />
              </BarChart>
            </ResponsiveContainer>
          </div>

          <div className="chart-legend">
            <span><i className="legend-normal" /> Stock normal</span>
            <span><i className="legend-low" /> Stock bajo</span>
          </div>
        </article>
      </section>

      <section className="bottom-grid">
        <article className="panel">
          <div className="panel-header">
            <div>
              <h3>Productos con stock bajo</h3>
              <p>Productos que necesitan atención</p>
            </div>

            <span className="count-badge">{productosStockBajo.length}</span>
          </div>

          <div className="table-wrapper">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Producto</th>
                  <th>Stock actual</th>
                  <th>Stock mínimo</th>
                  <th>Estado</th>
                </tr>
              </thead>

              <tbody>
                {productosStockBajo.map((producto) => (
                  <tr key={producto.codigo}>
                    <td>
                      <div className="product-name">
                        <strong>{producto.nombre}</strong>
                        <span>{producto.codigo}</span>
                      </div>
                    </td>

                    <td>{producto.stock}</td>
                    <td>{producto.minimo}</td>

                    <td>
                      <span className="status-pill status-low">
                        Bajo
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </article>

        <article className="panel alerts-panel">
          <div className="panel-header">
            <div>
              <h3>Alertas recientes</h3>
              <p>Situaciones para revisar</p>
            </div>
            <AlertTriangle size={20} color="#B7791F" />
          </div>

          <div className="alerts-list">
            {alertas.map((alerta) => (
              <div className="alert-item" key={alerta.titulo}>
                <div
                  className={`alert-icon ${
                    alerta.tipo === "critical"
                      ? "alert-critical"
                      : "alert-warning"
                  }`}
                >
                  <AlertTriangle size={18} />
                </div>

                <div>
                  <strong>{alerta.titulo}</strong>
                  <p>{alerta.descripcion}</p>
                </div>
              </div>
            ))}
          </div>

          <div className="prediction-note">
            <span className="prediction-indicator" />
            <div>
              <strong>Próximo paso</strong>
              <p>
                Las predicciones de demanda se integrarán cuando conectemos
                el modelo de StockIA.
              </p>
            </div>
          </div>
        </article>
      </section>

      <footer className="dashboard-footer">
        StockIA · Sistema de gestión inteligente de inventario
      </footer>
    </div>
  );
}