# Dashboard — 项目状态管理界面

单文件 HTML 应用，浏览器打开即用，无需安装任何依赖。

## 使用方式

直接在浏览器中打开 `mimir-bo.html`。

## 特性

| 特性 | 说明 |
|------|------|
| 状态追踪 | Phase / Step 粒度，点击切换状态 |
| Pipeline 可视化 | 流水线视图，一目了然 |
| 内嵌 AI Chat | 项目上下文自动注入 system prompt |
| 持久化 | localStorage + 30 秒自动备份 JSON |
| 导入/导出 | JSON 格式，可手动备份恢复 |
| 配色 | Claude.ai 风格暖米色系 |

## 注意事项

- 数据存储在浏览器 localStorage 中，清除浏览器缓存会丢失数据
- 建议定期通过"导出 JSON"功能手动备份
- 30 秒自动备份机制会在检测到数据变化时自动下载备份文件

## TODO

`mimir-bo.html` 文件待放入此目录。
