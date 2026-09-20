# URL Parser

<img src="assets/AppIcon.png" width="128" alt="URL Parser icon">

供开发调试使用的 macOS 原生 URL 参数编辑器。Swift + AppKit，无第三方依赖，无 WebView，不发网络请求。最低 macOS 13。

## 运行

从 [GitHub Releases](https://github.com/langweicheng/urlparse/releases/latest) 下载 `URL-Parser-1.0.0-macOS-universal.zip`，解压后将 `URL Parser.app` 拖到「应用程序」。支持 macOS 13 及以上，Apple Silicon / Intel 使用同一个安装包。

应用采用 ad-hoc 本地签名，未使用 Apple Developer ID 签名或公证。首次打开若被 macOS 拦截，请在确认来源后前往「系统设置 → 隐私与安全性」选择「仍要打开」。Release 附带 `SHA256SUMS.txt` 可供校验。

```sh
./scripts/build-app.sh
open 'dist/URL Parser.app'
```

需要安装 Xcode 或 Swift 命令行工具。脚本生成 Release 应用并进行本地 ad-hoc 签名；默认构建当前 Mac 的 CPU 架构。运行 `./scripts/package-release.sh` 可构建 arm64 + x86_64 通用应用、ZIP 及 SHA-256 校验文件。项目使用 Swift Package Manager，可用 Xcode 打开 `Package.swift`。

## 使用

- 左侧输入或粘贴完整 URL，右侧立即显示解码后、按键名排序的 Query JSON。
- 右侧增删改字段，有效 JSON 会立即写回左侧。JSON 尚未写完或类型错误时，底部显示原因，保留上一条有效 URL。
- 两侧支持 ⌘C、⌘V、⌘X、⌘A。⌘Z 撤销，⇧⌘Z 重做，URL 和 JSON 一起恢复。工具栏也提供复制、粘贴、清空、撤销和重做按钮。
- 点击「生成二维码」为左侧当前 URL 生成二维码；超出单个二维码容量时提示缩短链接。二维码按需生成，不调用在线服务。

## 参数规则

```json
{
  "city": "北京",
  "id": "00123",
  "tag": ["a", "b"],
  "empty": "",
  "flag": null
}
```

这里 `tag` 对应重复的 `tag=a&tag=b`，`empty` 对应 `empty=`，`flag` 对应无等号的 `flag`。删除整个字段即删除参数。重复参数必须用数组表示，不要在 JSON 中重复写同名键。

参数值使用字符串，避免长整数、前导零、布尔文本被隐式转换。数组仅用于重复参数，成员可以是字符串或 null。参数内嵌 JSON 仍作为字符串保留，不递归展开。

百分号编码只解码一层，`+` 保留为加号，不按表单规则转为空格。修改过的键值按 UTF-8 百分号编码；未修改参数保留原始编码和顺序。协议、路径、fragment 保留，新增参数放在 Query 末尾。支持自定义协议，例如 `imeituan://`。

数据只保留在本次进程中，关闭应用后不会保存。撤销历史最多保留 100 组操作，每组仅保存变化片段。

## 校验与性能

```sh
swift test
swift build -c release
```

测试覆盖中文解码、特殊字符回写、重复参数、空值、参数增删、非法 JSON、fragment、一层解码、1000 参数往返，以及二维码生成后识别回原 URL。

本机调试构建中，1000 参数的解析和 JSON 格式化约 3 毫秒（不含文本绘制）。此前不含图标的单架构应用体积约 232 KB；发行版增加通用架构和图标，体积以下载文件为准。AppKit、字体和系统框架仍有运行时开销；实际内存会随文本长度、撤销历史及二维码生成变化。

## 目录

- `Sources/URLCore`：URL 参数往返转换、二维码生成。
- `Sources/URLParser`：AppKit 窗口、文本编辑和双向同步。
- `Tests/URLCoreTests`：解析和二维码测试。
- `scripts/build-app.sh`：生成可双击的 `.app`。

## 内存优化（2026-09-20）

文本编辑使用显式 TextKit 1 布局，正常保留完整文档排版和滚动；将子视图绘制合并到滚动区域的图层，减少长文档绘制缓存。关闭系统写作、预测补全和文本检测。撤销记录改为文本差量；同步成功后不再重复解析 JSON。二维码以小尺寸矩阵渲染、灰度放大，关闭窗口后释放图像和窗口引用。

同一台 Apple Silicon Mac、macOS 26.5.2、Release 构建，两轮独立进程运行；每阶段等待 2 秒采样。下表为 `TASK_VM_INFO.phys_footprint`，单位 MiB，不是 RSS。

| 场景 | 修改前 | 修改后 |
| --- | ---: | ---: |
| 空白启动 | 25.1–25.7 | 31.4–31.7 |
| 1000 个参数 | 148.3–156.3 | 41.4–42.5 |
| 再连续编辑 100 次 | 167.8–169.8 | 46.0–47.0 |
| 改为短链接并打开二维码 | 53.1–53.7 | 50.7–50.8 |
| 关闭二维码 | 49.5–50.6 | 49.6–49.9 |

长文档场景的物理内存减少约 73%，空白启动并没有降低。对应的长文档 RSS 为修改前 107.0–110.3 MiB、修改后 98.7–108.6 MiB；RSS 包含共享框架驻留页，不能与物理内存数字混用。结果随系统缓存、窗口大小和输入内容变化，不是内存上限。

复测命令：`./scripts/measure-memory.sh`。脚本在临时目录编译测量程序，自动依次执行上述场景并退出；测量代码不进入正式应用。原始记录见 `docs/memory-before.txt` 和 `docs/memory-after.txt`。

本轮通过 11 项自动化测试，并在独立测试应用中检查了千行 JSON 滚动到底部、右侧编辑回写、⌘Z/⇧⌘Z 双侧恢复及二维码显示。

## 分栏与 JSON 编辑

首次打开左右各占 50%；拖动分隔线后自动保存比例，下次打开恢复，调整窗口尺寸时也沿用比例。

右侧单击键名可选中完整 key（不含引号），对应 key/value 整项显示浅黄色背景。右键点击键名或值，会选中当前目标并显示复制、删除菜单：

- 复制 Key：复制解码后的键名，不带 JSON 引号。
- 删除 Key：删除该参数及其值，并自动处理逗号。
- 复制 Value：字符串复制解码后的内容；数组或 null 复制其 JSON 文本。
- 删除 Value：清空为 `""`，保留 key，URL 中变为 `key=`。重复参数数组作为整个 value 处理。

这些删除操作实时同步左侧，支持撤销和重做。无效或未写完的 JSON 暂不提供键值删除菜单，普通文本编辑仍可使用。

右侧固定浅色背景，键名紫色 `#660E7A`、字符串绿色 `#008000`、数字蓝色 `#0000FF`、关键字深蓝 `#000080`；选区蓝底白字。颜色取自 [JetBrains 默认浅色方案](https://github.com/JetBrains/intellij-community/blob/master/platform/platform-resources/src/DefaultColorSchemesManager.xml)，JSON 属性名对应 INSTANCE_FIELD，参见 [JSON 高亮映射](https://github.com/JetBrains/intellij-community/blob/master/json/src/com/intellij/json/highlighting/JsonSyntaxHighlighterFactory.java)。语法颜色及整项背景使用 TextKit 临时属性，不写入正文或撤销历史。

加入这些交互后的同一内存脚本单次复测：1000 参数约 44.5 MiB，连续编辑 100 次约 45.2 MiB（物理内存口径，窗口默认 50:50）。
