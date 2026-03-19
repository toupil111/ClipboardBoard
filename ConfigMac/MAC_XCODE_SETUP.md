# Mac 版 Xcode 工程使用说明

## 你现在已经有的内容

我已经为现有 Mac 粘贴板生成了 Xcode 工程配置：

- [ConfigMac/project.yml](project.yml)
- [ConfigMac/Mac-Info.plist](Mac-Info.plist)
- [ConfigMac/Mac.entitlements](Mac.entitlements)
- 生成后的工程：`ClipboardBoardMac.xcodeproj`

## 如何打开

1. 安装完整 Xcode
2. 打开 [ClipboardSuite.xcworkspace](../ClipboardSuite.xcworkspace) 或 [ConfigMac/ClipboardBoardMac.xcodeproj](ClipboardBoardMac.xcodeproj)
3. 选择 `ClipboardBoardMac` target
4. 在 `Signing & Capabilities` 中选择你的 Team

## 需要打开的能力

### 1. iCloud

勾选：

- CloudKit

容器建议使用：

- `iCloud.com.liangweibin.clipboardboard`

### 2. Login Items

如果你后续要把开机启动做得更正式稳定，建议在 Xcode 中补全：

- App Sandbox / Login Items 相关配置
- 或单独做 helper app

当前代码里已经接了 `SMAppService`，但正式发布前建议在完整 App 工程里验证一次。

## 需要手动授权的系统权限

### 1. 辅助功能

因为你有“点击后自动粘贴”功能，所以需要：

- 系统设置 -> 隐私与安全性 -> 辅助功能
- 允许 `ClipboardBoard`

### 2. 开机启动

首次启用时，系统可能会要求确认。

## 如何运行

1. 选择 `My Mac`
2. Run
3. 首次运行后测试：
   - `Option + Command + V`
   - 点击条目自动粘贴
   - 状态栏 `C` 图标
   - CloudKit 是否成功同步

## 如何 Archive 导出

1. Product -> Archive
2. Organizer 中导出 App
3. 可继续做 dmg 封装

## 当前限制

如果机器上没有完整 Xcode，只有 Command Line Tools：

- 无法使用 `xcodebuild` 构建 macOS App target
- 也无法做 iOS 真机安装

所以你接下来应先安装完整 Xcode。
