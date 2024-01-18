import { defineConfig } from "vite";
import { resolve } from "path";
import { createHtmlPlugin } from "vite-plugin-html"
import solid from 'vite-plugin-solid'

export default defineConfig({
    base: "localhost:5173/",
    plugins: [solid(),
  
],
    build: {
        target: 'esnext'
    }
})