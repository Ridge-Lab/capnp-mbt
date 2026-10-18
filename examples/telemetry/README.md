# MoonBit 与 Python 的数据批处理

从仓库根目录执行。需要 MoonBit >= 0.10.14、Node.js 24、Python 3.12。生成代码已包含在仓库中。Python 端通过 `pycapnp` 调用官方 C++ Cap'n Proto 实现，独立于本项目的编解码代码。

```sh
moon update
python -m pip install -r examples/telemetry/requirements.txt
mkdir -p work
moon run --target js examples/telemetry -- produce work/batch.bin
python examples/telemetry/worker.py work/batch.bin work/report.bin
moon run --target js examples/telemetry -- verify work/report.bin
```

PowerShell 将 `mkdir -p work` 换为 `New-Item -ItemType Directory -Force work`。如已配置 C 编译器，可以把 `--target js` 换为 `--target native`。

最后一条命令核对结果，并在不一致时失败：

```text
Verified independent report: accepted=4 rejected=2 mean=21 min=19.5 max=23
```

输入有 6 条读数，其中一条质量为 Missing，一条数值为 NaN。Python 仅统计质量为 Valid 且有限的读数。任务 ID 为 `9007199254740993`，时间戳使用纳秒 UInt64；全流程没有将其转成会丢失精度的 JavaScript Number。

`schema/quality.capnp` 定义质量枚举，`schema/telemetry.capnp` 引用它并定义 Batch / Report。Report 使用 union 表示空结果或含统计数据的结果，`unit` 使用 schema 默认值。

还可让官方工具读取 MoonBit 的 packed 输出：

```sh
moon run --target js cmd/packing -- pack work/batch.bin work/batch.packed.bin
capnp decode --packed examples/telemetry/schema/telemetry.capnp Batch < work/batch.packed.bin
```

使用 Bash 或 `cmd.exe` 执行二进制重定向。本示例是可复现的集成样例，不是对生产系统部署或性能的宣称。
