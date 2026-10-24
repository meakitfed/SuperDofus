import { useEffect, useState } from "react";
import { WorldPage } from "./pages/WorldPage";
import { WorldsPage } from "./pages/WorldsPage";

/** Tiny router: "/" lists the worlds, "/mondes/<id>" opens one. The server serves the shell for any path. */
export function navigate(path: string) {
  history.pushState({}, "", path);
  window.dispatchEvent(new PopStateEvent("popstate"));
}

const SOON = ["Assets", "Textes", "Objets", "Sorts", "Classes", "Monstres", "PNJ et dialogues", "Quêtes", "Maps"];

export function App() {
  const [path, setPath] = useState(location.pathname);
  useEffect(() => {
    const on = () => setPath(location.pathname);
    window.addEventListener("popstate", on);
    return () => window.removeEventListener("popstate", on);
  }, []);

  const m = /^\/mondes\/([a-z0-9_]+)\/?$/.exec(path);
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
      <main className="main">{m ? <WorldPage id={m[1]} /> : <WorldsPage />}</main>
    </div>
  );
}
