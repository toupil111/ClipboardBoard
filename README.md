# ClipboardBoard

[中文](#中文说明) | [English](#english)

---

## 中文说明

ClipboardBoard 是一个使用 Swift 开发的 macOS 剪贴板工具，用来快速查看、管理和粘贴常用内容。

### 安装与使用

直接使用 [dist/ClipboardBoard.dmg](dist/ClipboardBoard.dmg) 安装包即可使用，完全本地运行。

### 主要功能

- 最多保留 50 条剪贴板历史
- 支持文本、图片、PDF、音频、视频和常见文件
- 使用 `Option + Command + V` 快速唤醒面板
- 支持粘贴板内容搜索与高亮命中
- 支持超大附件红标提醒与更明显的复制成功 HUD
- 支持重复内容智能合并，避免历史列表被重复内容刷屏
- 支持收藏、置顶、删除和自定义标签分组
- 支持敏感内容保护、Touch ID / 密码验证、本地加密与敏感预览二次加密
- 支持敏感预览仅显示前 2 / 4 / 6 个字符，可在设置中切换
- 支持单条敏感内容独立超时、敏感访问日志、敏感恢复后自动清空系统剪贴板
- 敏感内容独立标签展示，不出现在公共列表中
- 支持加密 JSON 导入 / 导出
- 支持通过勾选启用自动清理旧备份策略
- 支持一键打开本地数据目录、备份目录与附件目录
- 支持明亮 / 暗黑 / 跟随系统主题、面板尺寸、列表密度与强调色设置
- 亮色模式使用更干净的纯白背景，顶部区域不再透明
- 设置主弹窗与二级弹窗会随面板尺寸和紧凑/舒适布局自适应，并支持上下滚动
- 支持点击列表行主体区域直接复制并粘贴，功能按钮不会误触发复制
- 支持更醒目的红色删除按钮，常用操作更直观
- 底部快捷键提示与关闭按钮采用同一行左右布局
- 支持首次使用引导页
- 支持更强的键盘导航与快捷操作：搜索、上下选择、回车粘贴、删除、快捷切换标签
- 支持开机启动
- 本地持久化保存，重启后仍可继续使用

### 说明

- 本项目主要用于 macOS 本地使用
- 安装包目录： [dist](dist)
- 首次使用自动粘贴功能时，可能需要授予辅助功能权限
- 所有历史记录与导入导出文件均优先本地保存和本地加密
- 存储占用在设置页中以进度条方式展示

---

## English

ClipboardBoard is a macOS clipboard manager built with Swift for quickly viewing, organizing, and pasting frequently used content.

### Install and Use

Use the installer in [dist/ClipboardBoard.dmg](dist/ClipboardBoard.dmg) directly.
It runs fully locally on your Mac.

### Features

- Keeps up to 50 clipboard history items
- Supports text, images, PDF, audio, video, and common files
- Open the panel with `Option + Command + V`
- Supports clipboard search and highlighted matches
- Supports oversized-attachment warning badges and a more visible copy-success HUD
- Supports intelligent duplicate merging to keep history cleaner
- Supports favorites, pinning, deletion, and custom tag groups
- Supports sensitive-content protection with Touch ID / password verification, local encryption, and secondary encryption for sensitive previews
- Supports showing only the first 2 / 4 / 6 characters of sensitive previews, configurable in Settings
- Supports per-item sensitive reveal timeout, sensitive access logs, and automatic clipboard clearing after restoring sensitive content
- Sensitive items stay in their own tab and do not appear in public lists
- Supports encrypted JSON import/export
- Supports checkbox-based automatic cleanup policy for old backups
- Supports one-click opening of local data, backup, and payload directories
- Supports light / dark / follow-system appearance, panel size, list density, and accent color customization
- Light mode now uses a cleaner pure-white background, and the top area is no longer transparent
- Settings overlays and secondary popups adapt to panel size and density, with vertical scrolling support
- Supports clicking the main body of a row to copy/paste directly, while action buttons do not trigger accidental copying
- Supports a more visible red delete button for faster removal
- Footer hints and the close button now share a left-right single-line layout
- Supports a first-run onboarding guide
- Supports stronger keyboard navigation and shortcuts for search, selection, paste, delete, and tab switching
- Supports launch at login
- History is stored locally and remains available after restart

### Notes

- This project is mainly designed for local macOS usage
- Installer output directory: [dist](dist)
- Accessibility permission may be required for auto-paste on first use
- Clipboard history and encrypted import/export files are stored and protected locally on the Mac
- Storage usage is shown in Settings with a simple progress bar
