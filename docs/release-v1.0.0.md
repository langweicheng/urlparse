URL Parser 的首个 macOS 原生版本，Swift + AppKit，无第三方运行时依赖，离线处理 URL。

### 功能

- URL 与解码后的 Query JSON 双向实时同步。
- JSON 键值快速选择、当前参数高亮、右键复制与删除。
- IDEA Light 配色，分栏默认 50:50，记住调整后的比例。
- 复制、粘贴、撤销、重做；无效 JSON 保留上一条有效 URL。
- 系统离线二维码生成，超长 URL 显示提示。
- 支持重复参数、空值、自定义协议，保留未修改参数的原始编码。
- 新增原生应用图标；文本绘制和撤销记录经过内存优化。

### 下载与安装

下载 **URL-Parser-1.0.0-macOS-universal.zip**，解压后将 **URL Parser.app** 拖入「应用程序」。

- 系统：macOS 13 或以上。
- 架构：Apple Silicon（arm64）和 Intel（x86_64），同一安装包。
- 签名：ad-hoc 本地签名，未进行 Apple Developer ID 签名或公证。若首次打开被系统拦截，可在确认来源后到「系统设置 → 隐私与安全性」选择「仍要打开」。
- 校验：下载同版本 SHA256SUMS.txt，在两个下载文件所在目录执行 `shasum -a 256 -c SHA256SUMS.txt`。

### 验证与限制

19 项测试通过；两个架构均完成 Release 编译，安装包经过签名与架构检查。界面交互已在 Apple Silicon Mac 上验证，Intel 版本尚未在 Intel 实机运行验证。

URL 内容仅在本次运行中保留，退出前请先复制需要保留的数据。删除 Key 会删除整个参数，删除 Value 会清空为字符串。参数值保持字符串语义；重复参数使用数组。
