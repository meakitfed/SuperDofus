import { useEffect, useState } from "react";
import { WorldPage } from "./pages/WorldPage";
import { WorldsPage } from "./pages/WorldsPage";

/** Tiny router: "/" lists the worlds, "/mondes/<id>" opens one. The server serves the shell for any path. */
export function navigate(path: string) {
  history.pushState({}, "", path);
  window.dispatchEvent(new PopStateEvent("popstate"));
}

const TABS: Record<string, "assets" | "texts" | "items" | "spells" | "monsters" | "classes" | "maps" | "npcs"> = { assets: "assets", textes: "texts", objets: "items", sorts: "spells", monstres: "monsters", classes: "classes", maps: "maps", pnj: "npcs" };

const SOON = ["Quêtes"];

export function App() {
  const [path, setPath] = useState(location.pathname);
  useEffect(() => {
    const on = () => setPath(location.pathname);
    window.addEventListener("popstate", on);
    return () => window.removeEventListener("popstate", on);
  }, []);

  const m = /^\/mondes\/([a-z0-9_]+)(?:\/(assets|textes|objets|sorts|monstres|classes|maps|pnj))?\/?$/.exec(path);
  return (
    <div className="shell">
      <aside className="side">
        <a className="brand" href="/" onClick={(e) => { e.preventDefault(); navigate("/"); }}>
          <span className="logo" aria-hidden>▲</span> Atelier
        </a>
        <nav>
          <a className={"nav-item" + (!m ? " active" : "")} href="/" onClick={(e) => { e.preventDefault(); navigate("/"); }}>Mondes</a>
          <p className="nav-title">À venir</p>
          {SOON.map((s) => <span key={s} className="nav-item soon">{s}</span>)}
        </nav>
      </aside>
      <main className="main">{m ? <WorldPage id={m[1]} tab={TABS[m[2] ?? ""] ?? "overview"} /> : <WorldsPage />}</main>
    </div>
  );
}
