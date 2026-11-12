# Read a module bundle linked into workerd

Cloudflare's [build rule](https://github.com/cloudflare/workerd/blob/e0240debf4d6a5042a02a45311b51c61d13bd0fb/build/wd_js_bundle.bzl) embeds module contents in a Cap’n Proto constant. The Pyodide bundle in the official Windows x64 release contains 28 modules, including JavaScript and Python resources. The MoonBit example lists a framed `Modules.Bundle` and extracts a module to a caller-supplied path. It uses bindings generated from the [workerd schema](https://github.com/cloudflare/workerd/blob/e0240debf4d6a5042a02a45311b51c61d13bd0fb/src/workerd/jsg/modules.capnp).

From the repository root, run with Python 3.11+, MoonBit and Node.js:

```sh
curl -fL https://registry.npmjs.org/@cloudflare/workerd-windows-64/-/workerd-windows-64-1.20261112.1.tgz -o workerd-windows.tgz
python examples/builtin_bundle/release_bundle.py workerd-windows.tgz pyodide.bundle
moon run --release --target js examples/builtin_bundle -- list pyodide.bundle
moon run --release --target js examples/builtin_bundle -- extract pyodide.bundle pyodide-internal:workers-api/src/asgi.py extracted-asgi.py
```

The Python command accepts only that exact npm archive. It copies the linked 206,384-byte segment at PE file offset `0x52f6c80`, prefixes the standard eight-byte single-segment frame header, and verifies the result's SHA-256. It never executes workerd. The offset and checksum belong to that one binary. The MoonBit commands accept standalone framed bundles using the same schema, independent of where the frames came from.

CI lists all 14 source and 14 data modules, compares every extracted payload with a separate C++ reader via pycapnp, and checks the Git blob IDs of [asgi.py](https://github.com/cloudflare/workerd/blob/e0240debf4d6a5042a02a45311b51c61d13bd0fb/src/pyodide/internal/workers-api/src/asgi.py) and [entropy_patches.py](https://github.com/cloudflare/workerd/blob/e0240debf4d6a5042a02a45311b51c61d13bd0fb/src/pyodide/internal/topLevelEntropy/entropy_patches.py). Export preserves the original binary bytes. The Git source comparison normalizes Windows checkout line endings. To reproduce these checks locally, install pycapnp 2.2.1 and run:

```sh
moon build --release --target js examples/builtin_bundle
python examples/builtin_bundle/release_bundle.py workerd-windows.tgz verified.bundle --verify-with node _build/js/release/build/examples/builtin_bundle/builtin_bundle.js
```

The executable and module contents come from the upstream release. Only the schema and generated bindings are distributed in this repository. [Source and license notices](../../docs/PROVENANCE.md)
