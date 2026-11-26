# Unmodified Cloudflare workerd fixtures

These files come from Cloudflare's [workerd](https://github.com/cloudflare/workerd)
project under the Apache License, Version 2.0 (see [LICENSE](LICENSE)). The
upstream repository contains no separate `NOTICE` file.

- Pinned workerd release: `@cloudflare/workerd-linux-64@1.20261112.1` / `@cloudflare/workerd-windows-64@1.20261112.1`
- Pinned upstream Git revision: [`e0240debf4d6a5042a02a45311b51c61d13bd0fb`](https://github.com/cloudflare/workerd/tree/e0240debf4d6a5042a02a45311b51c61d13bd0fb)
- Local Git attributes (`fixtures/upstream/workerd/** -text`) preserve exact upstream bytes across platforms.

`config/unit-tests/config.bin` is the binary output produced from
`config/unit-tests/config.capnp` and `config/unit-tests/worker.js` by the
pinned official `workerd compile --config-only config.capnp` command; see
[`examples/workerd_config/README.md`](../../../examples/workerd_config/README.md)
for replay instructions.

## SHA-256 manifest

Paths are relative to this directory.

| Path | Upstream origin | SHA-256 |
| --- | --- | --- |
| `LICENSE` | `LICENSE` | `0d542e0c8804e39aa7f37eb00da5a762149dc682d7829451287e11b938e94594` |
| `modules.capnp` | `src/workerd/jsg/modules.capnp` | `53e87d5229b9b83a5da3e9ec9dcf2eb889dfc15afbee42c63a896775f79430b5` |
| `config/workerd.capnp` | `src/workerd/server/workerd.capnp` | `688a975fd1e784b7d984352e30274e90875df60cfa6186cfd343584c596628dc` |
| `config/unit-tests/config.capnp` | `samples/unit-tests/config.capnp` | `04604ad100616ff7e6df71c334879984083bb963d245bdd74371f5bf8c024ee7` |
| `config/unit-tests/worker.js` | `samples/unit-tests/worker.js` | `004b53a375f06ce29f10bbd2ab5d3eaeea0dbe4ac9cba48fcfae482a4ddd0149` |
| `config/unit-tests/config.bin` | `workerd compile --config-only config.capnp` (`1.20261112.1`) | `d6799e0519b7d08f9d03e24371d3a730a2293d2c441d4028256f09eb18614a67` |
