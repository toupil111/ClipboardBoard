# macOS Xcode 工程配置

这里是现有 Mac 粘贴板应用的 XcodeGen 配置。

包含：

- `project.yml`
- `Mac-Info.plist`
- `Mac.entitlements`

生成后会得到一个可在 Xcode 中打开的 macOS App 工程，适合：

- 配置 Signing
- 打开 CloudKit capability
- 打开 Login Items / 辅助功能相关权限
- Archive / 导出 app
