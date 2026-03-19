# ClipboardBoard

直接使用dist目录下的dmg安装包 即可使用 完全本地运行

一个用 Swift 开发的 macOS 粘贴板历史工具，满足以下需求：

- 最多保留 50 条历史记录
- 新内容进入时自动挤出最旧内容（FIFO）
- 支持文字、图片、PDF、MP3、MP4 以及普通文件
- 使用 `Option + Command + V` 唤醒浮动面板
- 支持开机启动
- 点击条目后自动粘贴到上一前台应用
- 关机重启后仍保留最近 50 条记录
- 菜单栏常驻大写 `C` 图标
- 已接入 CloudKit 同步骨架，可把 Mac 历史同步到 iPhone 端(todo)
- 列表滚动时带有过渡动画

## 项目结构

- [Mac CloudKit 服务](Sources/ClipboardBoard/Services/CloudKitSyncService.swift#L1)
- [macOS Xcode 工程配置](ConfigMac/project.yml)
- [iOS Xcode 工程配置](sources%20App/Config/project.yml)
- [统一 Workspace](ClipboardSuite.xcworkspace)

## 运行方式

1. 在 Xcode 中打开 [Package.swift](Package.swift)
2. 选择 `ClipboardBoard` scheme

> 首次使用自动粘贴时，请允许辅助功能权限。

### 8. Xcode 工程

- macOS 工程已生成： [ConfigMac/ClipboardBoardMac.xcodeproj](ConfigMac/ClipboardBoardMac.xcodeproj)
- iOS 工程已生成： [sources App/Config/ClipboardMobile.xcodeproj](sources%20App/Config/ClipboardMobile.xcodeproj)
- 统一 Workspace 已生成： [ClipboardSuite.xcworkspace](ClipboardSuite.xcworkspace)
- 可使用脚本重新生成： [scripts/generate_xcode_projects.sh](scripts/generate_xcode_projects.sh)

### 9. iPhone 文件体验

- 文件项会生成本地缩略图预览
- 已同步到本机的文件可直接系统分享至微信等 App
- 未同步到本机时会提示先刷新再分享

### 10. 动画体验

## 打包 DMG

执行：

1. `chmod +x scripts/build_dmg.sh`
2. `./scripts/build_dmg.sh`

生成物位于：

- [dist/ClipboardBoard.dmg](dist/ClipboardBoard.dmg)

## 已实现能力

### 1. 历史队列

- `ClipboardStore` 会把最新项插入头部
- 超过 50 条时自动截断为前 50 条
- 如果最新一次拷贝与当前头部相同，则不会重复插入

### 2. 内容类型支持

- 文本：直接读取字符串
- 图片：读取图片数据并显示缩略图
- PDF：支持二进制 PDF 数据与 PDF 文件
- 音视频：支持 `mp3`、`m4a`、`wav`、`mp4`、`mov` 等文件路径
- 文件：支持 Finder 中复制的单个或多个文件

### 3. 全局快捷键

使用 Carbon 注册全局热键：

- `Option + Command + V`

### 4. 自动粘贴

- 唤醒面板前会记录当前前台应用
- 点击某一条历史后，会恢复剪贴板并自动发送 `Command + V`
- 需要在 macOS 辅助功能中授予权限

### 5. 开机启动

使用 `ServiceManagement.SMAppService` 切换开机启动。

> 提示：为了让开机启动在正式环境更稳定，建议将构建后的 App 放入“应用程序”目录后再启用。

### 6. 持久化与性能优化

- 最近 50 条历史会写入 `Application Support/ClipboardBoard`
- 图片只在列表中保留缩略图，原始负载写入磁盘
- 预览图标使用 `NSCache`，减少重复解码与内存抖动
- 定时监听增加 `tolerance`，降低空闲 CPU 唤醒频率
- 关键闭包均使用弱引用，避免循环引用

### 7. Mac / iPhone 同步

- Mac 端已新增 CloudKit 上传服务
- 新增记录会自动把最近 50 条同步到私有 CloudKit 数据库
- iPhone 端骨架位于 [sources App](sources%20App)
- 文件会以 CloudKit 资源形式上传，iPhone 拉取后可落地到本地再分享

> 注意：CloudKit 真正运行需要在 Xcode 的 App Target 里打开 iCloud / CloudKit capability。纯 Swift Package 结构只适合代码组织，正式签名与能力配置建议放进 Xcode App 工程。

- 面板显示/隐藏带淡入淡出动画
- 面板打开和关闭时增加位移动画
- 滚动列表使用 `scrollTransition` 增加缩放、透明度、模糊过渡
- 新内容插入列表时使用弹性动画
- 鼠标悬浮条目时增加缩放和阴影动画

## 后续建议

如果你要继续做成完整产品，建议下一步补充：

- 搜索与筛选
- 收藏与置顶
- 更完整的 Quick Look 文件预览

# ClipboardBoard
