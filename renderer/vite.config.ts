import { defineConfig } from 'vite';
import { viteSingleFile } from 'vite-plugin-singlefile';

// With WKWebView's loadFileURL, loading separate JS/CSS files is finicky because
// allowingReadAccessTo has to be set just right. So we inline all JS/CSS into
// index.html with vite-plugin-singlefile, so dropping in a single file just works.
export default defineConfig({
  base: './',
  plugins: [viteSingleFile()],
  build: {
    target: 'esnext',
    assetsInlineLimit: 100_000_000,
    chunkSizeWarningLimit: 100_000,
    cssCodeSplit: false,
    outDir: 'dist',
    emptyOutDir: true,
  },
});
