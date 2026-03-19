# Share Extension 规划

目标：

- 从系统分享面板把文本、图片、PDF、文件追加到你的 iPhone 粘贴板历史
- 与主 App 共用 App Group 存储
- 后续可选择同步回 CloudKit

建议实现：

1. 建立 Share Extension Target
2. 读取 `NSExtensionItem` 中的附件
3. 转成 `ClipboardEntry`
4. 写入 App Group 容器
5. 主 App 下次打开或收到通知后刷新列表

注意：

- Share Extension 生命周期很短
- 不适合做重型上传
- 最好只做落地缓存与通知主 App 同步
