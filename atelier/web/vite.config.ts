import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

// `npm run build` -> web/dist, served by the atelier server. `npm run dev` proxies /api to it.
export default defineConfig({
  root: __dirname,
  plugins: [react()],
  build: { outDir: "dist", emptyOutDir: true },
  server: { port: 5173, proxy: { "/api": "http://127.0.0.1:5174" } },
});
