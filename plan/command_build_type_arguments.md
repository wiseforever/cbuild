# 命令行构建类型参数

## 目标

- 让 `-g` / `--generate` 与 `-b` 一样支持临时指定 `Debug` 或 `Release`。
- 接受不区分大小写的 `debug` / `release` 参数。
- 保持 `-t` 现有的持久配置修改与组合行为不变。

## 实施步骤

1. 为 Bash/Python 的 `-g` 参数解析加入可选构建类型。
2. 更新帮助和中英文命令示例。

## 验收标准

- `cb.sh -g Debug`、`cb.sh -g release` 都使用对应类型配置，但不写入 `cb_conf.ini`。
- Python 入口与 Bash 行为一致。

## 风险

- `-g` 的可选类型仅对当前命令有效，不会替代 `-t` 的持久配置修改。

## 操作留痕

- 已为 `-g` 添加临时构建类型参数，未改变 `-t Debug -g` 的既有行为。
- 已通过 Bash/Python 参数解析模拟验证：`-g release` / `-g debug` 选择对应类型且不写配置；`-t Debug -g` 仍先写入类型再进入配置流程。并已通过 Bash/Python 语法和 diff 检查。
