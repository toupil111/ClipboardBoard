# sources App

这里放的是 iPhone 版粘贴板的源码骨架与文档。

当前目标系统版本：`iOS 18+`

## 目录

- [iOSApp](iOSApp)
- [Shared](Shared)
- [WidgetExtension](WidgetExtension)
- [ShareExtension](ShareExtension)
- [Docs](Docs)
- [Config](Config)
- [PLAN.md](PLAN.md)

配套工程入口：

- [iOS xcodeproj](Config/ClipboardMobile.xcodeproj)
- [统一 Workspace](../ClipboardSuite.xcworkspace)

## 当前已提供

- `ClipboardEntry` 统一数据模型
- CloudKit 同步服务骨架
- App Group 小组件缓存
- iPhone 列表页、详情页、复制、分享 UI 骨架
- 本地文件缩略图预览与分享可用性提示
- Widget 列表预览骨架
- XcodeGen 工程配置、Info.plist、entitlements
- Share Extension 规划文档
- 真机安装与长期自用说明

## 说明

这是一套可直接拖入 Xcode 工程的源码骨架，也可以通过 [sources App/Config/project.yml](Config/project.yml) 生成 Xcode 工程。

下一步你可以继续让我做：

1. 生成完整 Xcode 工程配置说明
2. 把现有 Mac 端数据模型接到 CloudKit 上传
3. 为 iPhone 端补全文件落地与下载逻辑
4. 细化 Widget 交互与深链复制
