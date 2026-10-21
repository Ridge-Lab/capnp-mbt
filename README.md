# Cap'n Proto for MoonBit

[![Checks](https://github.com/Ridge-Lab/capnp-mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/Ridge-Lab/capnp-mbt/actions/workflows/ci.yml)

用同一份 `.capnp` 协议定义，在 MoonBit 与 C++、Python 等语言之间交换二进制数据。本项目提供 **MoonBit 序列化运行库**和 **`capnp` 编译器插件**，从正式的 schema 生成带类型的 MoonBit reader / builder。

适合已有 Cap'n Proto 协议的服务、数据采集程序、离线处理工具和二进制文件消费者接入 MoonBit。协议定义、字段布局和已有数据格式可以继续使用，业务代码无需手写偏移或经 JSON 中转。这里实现的是序列化层；网络传输和 RPC 不在本版本范围内。

**0.2.0 的兼容基准是 Cap'n Proto 1.5.0。** 泛型容器、AnyPointer 和常量均纳入序列化支持，使用未经删改的官方 `test.capnp` 验证。[标准目标与证据](docs/SERIALIZATION-STANDARD.md)说明完成标准及已测试范围，不以少数样例推断所有协议均兼容。

## 可运行的完整流程

[`examples/telemetry`](examples/telemetry) 演示一个数据处理任务：

1. MoonBit 用生成的 API 写入任务 ID、纳秒时间戳、读数和质量标记。
2. Python 使用 `pycapnp`（官方 C++ Cap'n Proto 实现的 Python 绑定）读取数据，剔除缺失值和 NaN，计算统计结果。
3. MoonBit 读取 Python 写出的结果，核对数量、均值、极值和超过 JavaScript 安全整数范围的 64 位 ID。

这是仓库提供的互操作示例，不代表已有外部用户部署。它说明该库如何用于实际的跨语言批处理；相同接口也可用于文件交换和消息队列的负载编解码。

[`examples/schema_compat`](examples/schema_compat/README.md) 验证接入既有协议：两端直接使用官方 1.5.0 `test.capnp`，Python/C++ 写入分段及 packed 数据，MoonBit 读取嵌套泛型与五种 AnyPointer 负载，再用生成的 builder 写回；Python 核对泛型绑定、默认值、常量及未知负载的内容。原文件中的接口、常量、别名和嵌入数据均保留，复现步骤见示例文档。

## 安装与快速运行

需要 MoonBit **0.10.14 或更新版本**。CI 固定验证 `0.10.14+7d59c7ec9`。运行库支持 `wasm`、`wasm-gc`、`js`、`native`，无需 C++ Cap'n Proto 动态库。

在自己的 MoonBit 项目中添加依赖：

```sh
moon add Ridge-Lab/capnp@0.2.0
```

包的 `moon.pkg` 中导入：

```moonbit
import {
  "Ridge-Lab/capnp",
}
```

直接运行本仓库的例子：

```sh
git clone https://github.com/Ridge-Lab/capnp-mbt
cd capnp-mbt
moon update
moon run --target js examples/roundtrip
```

输出包含 `Read job 9007199254740993` 和 6 个样本。生成代码已随例子提交，因此运行例子无需先安装 `capnp`。Node.js 需支持 ESM；本项目在 Node.js 24 上验证。

## 从 schema 生成 MoonBit API

先安装[官方 Cap'n Proto 编译器](https://capnproto.org/install.html)及 native 后端所需 C 编译器。在本仓库根目录执行：

```sh
moon build --target native --release cmd/capnpc-moonbit
capnp compile -o./_build/native/release/build/cmd/capnpc-moonbit/capnpc-moonbit.exe:examples/telemetry/generated examples/telemetry/schema/telemetry.capnp
moon fmt
moon check --target native --deny-warn
```

插件接收官方 `CodeGeneratorRequest`，由官方编译器处理 schema 语法和字段布局。所有所需声明（含 import）生成到同一个 `capnp_generated.mbt`，同时在目标目录缺少 `moon.pkg` 时创建运行库导入。多份相关 schema 应在一次 `capnp compile` 调用中传入；每次生成会替换目标文件。

也可使用请求文件和 Node.js，不必编译 native 插件：

```sh
capnp compile -o- fixtures/conformance.capnp > request.bin
moon run --target js cmd/capnpc-moonbit -- --request request.bin --out generated
moon fmt
```

二进制重定向使用 Bash 或 `cmd.exe`；旧版 PowerShell 的文本管道可能损坏二进制内容。Windows native 构建说明见[开发文档](docs/DEVELOPMENT.md)。

使用生成 API 的代码片段（完整可运行代码见 [`sample.mbt`](examples/telemetry/sample/sample.mbt)）：

```moonbit
let message = @capnp.Builder::new()
let batch = @telemetry.BatchBuilder::init_root(message)
batch.set_job_id(9007199254740993UL)
batch.set_source("room-temperature")
let samples = batch.init_samples(1)
samples.get(0).set_value(21.5)
samples.get(0).set_quality(@telemetry.Valid)
let bytes = message.finish()
let received = @telemetry.BatchReader::from_message(@capnp.read_message(bytes))
assert_eq(received.get_samples().get(0).get_value(), 21.5)
```

生成包在使用方 `moon.pkg` 中以 `@telemetry` 导入。reader 返回字段视图，实际访问指针时验证目标范围；Text 转换会进行 UTF-8 验证。低层接口见 [`pkg.generated.mbti`](pkg.generated.mbti)。

## 功能与边界

| 能力 | 当前范围 |
| --- | --- |
| 数据类型 | Void、Bool、所有整数和浮点宽度、Text、Data、enum、struct、嵌套声明 |
| 容器和字段 | primitive / pointer / inline-composite list、嵌套 list、group、union、标量及复合默认值 |
| 泛型与常量 | 显式及祖先作用域绑定、嵌套泛型、别名、未绑定参数；标量、列表、结构体及泛型常量 |
| 动态负载 | AnyPointer / AnyStruct / AnyList 视图与写入；保留未知字段的深拷贝，失败时回滚目标 |
| 帧和指针 | 标准分段帧、近指针、单跳和双跳 far pointer 的读取；writer 生成单段帧 |
| 压缩与流 | 标准 packed 编解码；`frame_length` 识别部分输入和串联帧边界 |
| Canonical 格式 | `canonicalize` 生成无 segment table 的 canonical segment，与官方转换器输出比较 |
| 防护 | 指针越界检查、共享遍历预算、嵌套深度限制、段数限制、解包和 writer 分配上限 |
| 演进 | 缺失字段默认值、额外字段跳过、未知 enum 值保留、兼容的 list / struct 扩展 |
| 范围外 | RPC 客户端/服务器、活动 capability table、builder 原位编辑收到的消息 |

已知泛型绑定生成具体类型；未绑定参数和递归增长的泛型边界保留动态视图，业务代码可通过公开的 `.inner` 继续访问，无需改写 schema。接口声明不会阻止同文件中的数据类型生成，但不生成 RPC 调用代码。低层 capability index API 只表示数字索引；跨消息深拷贝拒绝未提供表映射的非空 capability。

`finish()` 返回普通标准帧；需要 canonical 数据时单独调用 `canonicalize`，其结果不含帧头，不能直接交给 `read_message`。运行库错误使用 `CapnpError`，生成器对无效请求、无法消解的命名冲突或资源限制返回 `CodegenError`。

默认 reader 遍历预算为 8,388,608 words，嵌套深度 64，最多 512 段；`unpack` 默认最多输出 64 MiB。reader 的预算会被重复访问消耗，按需缓存已取得的视图。`read_message` 要求恰好一帧，流式输入先用 `frame_length` 划分。builder 使用追加式 arena，替换指针不会回收旧对象，`finish()` 返回快照。详见[兼容性和资源限制](docs/COMPATIBILITY.md)。

## 验证

```sh
moon fmt --check
moon check --target all --deny-warn
moon test --target all --deny-warn
moon build --target all --release
```

测试覆盖官方编译器样例、packed 对照、多段与 double-far 指针、泛型及常量、AnyPointer 深拷贝、canonical 输出、截断和恶意输入。CI 工作流覆盖四个后端的检查、构建和测试，并安排独立的跨语言验证；具体执行结果以工作流记录为准。[基础样例](fixtures/README.md)、[原样上游协议](fixtures/upstream/capnproto-1.5.0/README.md)和[官方 oracle 数据](fixtures/upstream/oracle-1.5.0/README.md)均附来源或再生方法。本项目尚未进行生产负载验证，不宣称优于其他实现的性能。

## 来源与许可证

MIT。运行库按[公开编码规范](https://capnproto.org/encoding.html)实现；生成器接入[官方插件协议](https://capnproto.org/otherlang.html)。不是 C++ 库的 FFI 包装，也未使用 MoonBit SWE-AGI 中的 Cap'n Proto 解码题解。独立贡献包括 writer、packing、类型代码生成及跨语言工作流；生态中已有相关题目并不等于已有相同 SDK。

第三方依赖、测试数据及生成文件的来源见 [`docs/PROVENANCE.md`](docs/PROVENANCE.md)。
