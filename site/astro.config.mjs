import { fileURLToPath } from "node:url";
import { defineConfig } from "astro/config";
import mdx from "@astrojs/mdx";

export default defineConfig({
  site: "https://thaddeusjiang.github.io",
  base: "/save_it",
  trailingSlash: "ignore",
  integrations: [mdx()],
  vite: {
    resolve: {
      alias: {
        "@components": fileURLToPath(new URL("./src/components", import.meta.url)),
      },
    },
  },
});
