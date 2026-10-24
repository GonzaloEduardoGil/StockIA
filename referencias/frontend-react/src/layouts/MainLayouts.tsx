import { Outlet } from "react-router-dom"
import Sidebar from "../components/sidebar"
import Header from "../components/Header"

export default function MainLayout() {
  return (
    <div className="app-layout">
      <Sidebar />

      <div className="main-area">
        <Header />

        <main className="page-content">
          <Outlet />
        </main>
      </div>
    </div>
  );
}