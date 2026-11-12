# 从 workerd 部署产物取回 Worker 源码

Cloudflare 的 `workerd compile --config-only` 将服务配置和嵌入模块写入一个 Cap’n Proto `Config` 消息。此示例从同版原始 schema 生成 MoonBit reader，列出模块制 Worker 的服务名、模块名和类型，也能从指定服务提取一个模块。可直接传入自己的二进制配置文件。

只想读取文件时，可从 [0.5.0 发布附件](https://github.com/Ridge-Lab/capnp-mbt/releases/tag/v0.5.0) 下载 `workerd-inspectors-0.5.0.zip` 并解压，用 Node.js 24 执行：

```sh
node inspect-config.mjs list sample/config.bin
node inspect-config.mjs extract sample/config.bin main worker recovered.js
```

从源码构建需要 MoonBit 0.10.20、Node.js、Python 3 和官方 Cap’n Proto 编译器 1.5.0。在仓库根目录执行以下命令。输出目录需为新目录，生成的接口和构建文件都放在其中。

```sh
python examples/workerd_config/build.py work/workerd-reader
node work/workerd-reader/_build/js/release/build/example/workerd/cmd/inspect/inspect.js list fixtures/upstream/workerd/config/unit-tests/config.bin
node work/workerd-reader/_build/js/release/build/example/workerd/cmd/inspect/inspect.js extract fixtures/upstream/workerd/config/unit-tests/config.bin main worker recovered.js
```

样例会列出 `[{"service":"main","module":"worker","kind":"esModule"}]`。`recovered.js` 与上游的 `worker.js` 逐字节相同。输出路径由调用方指定，已存在的文件会被拒绝。提取支持 ES module、CommonJS、文本、二进制数据、Wasm、JSON 和 Python 模块。内置代码引用可列出，源字节由 workerd 运行时提供。列表仅遍历模块制 Worker 服务；扩展、继承配置和旧式单脚本服务不在此例范围内。工具将单个未压缩配置文件读入内存，并使用运行库的默认遍历和嵌套深度限制。

## 重做上游构建

制品来自官方 `workerd@1.20261112.1`，Git 提交为 `e0240debf4d6a5042a02a45311b51c61d13bd0fb`。[原始协议](https://github.com/cloudflare/workerd/blob/e0240debf4d6a5042a02a45311b51c61d13bd0fb/src/workerd/server/workerd.capnp) · [上游测试 Worker 及配置](https://github.com/cloudflare/workerd/tree/e0240debf4d6a5042a02a45311b51c61d13bd0fb/samples/unit-tests) · [随附 Apache 2.0 许可证](../../fixtures/upstream/workerd/LICENSE)

安装上述精确版本的 workerd 和 `pycapnp==2.2.1` 后执行：

```sh
python examples/workerd_config/verify.py --output work/workerd-replay --targets js --workerd workerd
```

验证器直接接收 `workerd compile --config-only config.capnp` 的二进制 stdout。它与仓库内的 1,112 字节制品比较，交回 `workerd test --binary` 执行 `main:testMath` 和 `main:testStrings`，再用 MoonBit 提取模块并对比原 JS 字节。CI 在 Linux 上为 JS 与 native 运行这一流程。额外构造的混合模块消息覆盖不同载荷、重复名称、引用和错误输入。

| 文件 | SHA-256 |
| --- | --- |
| `config.bin` | `d6799e0519b7d08f9d03e24371d3a730a2293d2c441d4028256f09eb18614a67` |
| `worker.js` | `004b53a375f06ce29f10bbd2ab5d3eaeea0dbe4ac9cba48fcfae482a4ddd0149` |
