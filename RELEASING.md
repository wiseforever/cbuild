# 发布流程

cbuild 使用统一版本号：`cb.sh` / `cb.py` 的 `CBUILD_VERSION`、VS Code 插件的 `package.json` / `package-lock.json`，以及记录最后发布 tag 的 `LATEST`。tag 使用 `v` 前缀，例如 `v0.1.0`。

仓库同时推送到 GitHub（`origin`）和 Gitee（`gitee`）两个远端，代码、tag 和 `LATEST` 内容保持一致。

## 版本规则

- 正式版本形如 `v0.1.0`；预发布版本形如 `v0.1.0-rc.1`，脚本中的 `CBUILD_VERSION` 仍为 `0.1.0`。
- 已发布的 tag 和 tag 内文件不移动、不覆盖；修正内容时发布新版本。
- 默认安装读取所选源 `master/LATEST` 中的 tag，再从该 tag 下载全部文件。
- `--release vX.Y.Z` 直接使用对应 tag，不读取 `master/LATEST`。
- GitHub 和 Gitee 各自以自己的 `master/LATEST` 为准，不互相借用版本号。

## 发布前检查

```bash
tools/check_version.sh
python3 -m unittest discover -s tests -v
cd tools/cbuild-plugin-vscode
npm ci --ignore-scripts
npm test
npm run package
```

所有版本来源不一致时，`tools/check_version.sh` 会失败。

## 发布步骤

1. 修改代码，并在需要时统一更新 `CBUILD_VERSION`、插件版本，以及 `LATEST`（发布 tag，例如 `v0.1.0`）。
2. 提交 `master`，并确认发布前检查通过。
3. 创建 tag，并**先推送 tag 到两个远端**：

   ```bash
   git tag v0.1.0
   git push origin v0.1.0
   git push gitee  v0.1.0
   ```

4. tag 完整后，再推送 `master` 到两个远端。`master` 中的 `LATEST` 一旦推送，就会成为该远端默认安装的 tag：

   ```bash
   git push origin master
   git push gitee  master
   ```

5. 验证两个源：

   ```bash
   curl -fsSL https://raw.githubusercontent.com/wiseforever/cbuild/master/LATEST
   curl -fsSL https://gitee.com/wiseforever/cbuild/raw/master/LATEST
   curl -fsSL https://raw.githubusercontent.com/wiseforever/cbuild/master/install.sh | bash -s -- --help
   curl -fsSL https://gitee.com/wiseforever/cbuild/raw/master/install.sh | bash -s -- --source gitee --help
   # 安装后运行 cb.sh --version 确认版本
   ```

## 注意事项

- **必须先推 tag，再推带新 `LATEST` 的 `master`。** 顺序反了会让默认安装暂时指向不存在的 tag。
- `master/LATEST` 只能指向已经推送完成的 tag；安装器会校验 tag 内脚本的 `CBUILD_VERSION`。
- `CBUILD_VERSION` 必须是 `X.Y.Z` 或 `X.Y.Z-prerelease`，并与 tag 内容匹配；`LATEST` 保存发布 tag，例如 `v0.1.0`。
- 两个远端独立生效：只更新 GitHub 的 `master` 不影响 Gitee，反之亦然。
- 首次发布前对应的 `vX.Y.Z` tag 不存在，默认安装会失败；此时使用显式 tag 或本地 `install.sh`。
- Release 和 Release 附件不参与安装；tag 内文件才是版本化内容来源。
- 同一安装目录仍不支持并发安装/更新，不提供互斥锁。
