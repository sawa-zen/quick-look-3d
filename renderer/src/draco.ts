/// <reference types="vite/client" />
import { DRACOLoader } from 'three/examples/jsm/loaders/DRACOLoader.js';
// The decoder that ships with three.js, inlined into the single-file bundle.
// (`gltf/` is the variant for KHR_draco_mesh_compression.)
import dracoWrapperJs from 'three/examples/jsm/libs/draco/gltf/draco_wasm_wrapper.js?raw';
// `?url` resolves to a data: URL because vite.config.ts sets assetsInlineLimit very high.
import dracoWasmDataUrl from 'three/examples/jsm/libs/draco/gltf/draco_decoder.wasm?url';

function dataUrlToArrayBuffer(dataUrl: string): ArrayBuffer {
  const binary = atob(dataUrl.slice(dataUrl.indexOf(',') + 1));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

// DRACOLoader normally fetches its decoder from `decoderPath`. That would need separate
// asset files next to index.html (see vite.config.ts), so serve the inlined copy instead.
class InlineDRACOLoader extends DRACOLoader {
  _loadLibrary(url: string): Promise<string | ArrayBuffer> {
    return Promise.resolve(
      url.endsWith('.wasm') ? dataUrlToArrayBuffer(dracoWasmDataUrl) : dracoWrapperJs,
    );
  }
}

export function createDracoLoader(): DRACOLoader {
  return new InlineDRACOLoader();
}
