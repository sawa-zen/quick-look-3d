import { defineConfig, type Plugin } from 'vite';
import { viteSingleFile } from 'vite-plugin-singlefile';

// With WKWebView's loadFileURL, loading separate JS/CSS files is finicky because
// allowingReadAccessTo has to be set just right. So we inline all JS/CSS into
// index.html with vite-plugin-singlefile, so dropping in a single file just works.
// Content-Security-Policy for the shipped page (build only; the dev server needs
// same-origin scripts and its HMR socket, so it stays unrestricted).
// A model file can reference absolute URLs (glTF uri, FBX textures). Only blob:/data:
// resources built from the already-loaded file are allowed, so the preview never
// touches the network. Deliberately no 'self': on a file:// page WebKit lets 'self'
// match https:// URLs. 'unsafe-inline' is needed because the bundle is inlined.
const CSP = [
  "default-src 'none'",
  "script-src 'unsafe-inline'",
  "style-src 'unsafe-inline'",
  'img-src blob: data:',
  'connect-src blob: data:',
  'media-src blob: data:',
].join('; ');

function cspMeta(): Plugin {
  return {
    name: 'csp-meta',
    apply: 'build',
    transformIndexHtml: () => [
      {
        tag: 'meta',
        attrs: { 'http-equiv': 'Content-Security-Policy', content: CSP },
        injectTo: 'head-prepend',
      },
    ],
  };
}

export default defineConfig({
  base: './',
  plugins: [viteSingleFile(), cspMeta()],
  build: {
    target: 'esnext',
    assetsInlineLimit: 100_000_000,
    chunkSizeWarningLimit: 100_000,
    cssCodeSplit: false,
    outDir: 'dist',
    emptyOutDir: true,
  },
});
