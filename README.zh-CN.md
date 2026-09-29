# HeadHunter 汉化版（简体中文）

给 [HeadHunter - Wanted: Dead or Alive](https://headhunterwow.com) 插件做的简体中文本地化版本。

- **原始项目地址**：https://github.com/GudaAddons/HeadHunter（原作者 Vati / GudaAddons，v0.3.1，官网 [headhunterwow.com](https://headhunterwow.com)）
- **汉化分支地址**：https://github.com/erchezhang/HeadHunter-cn
- **汉化：车长不二 完成**
- 适用客户端：Classic Era（Interface 11509）与 WoW Forever（Interface 16001）
- 本仓库内容：原插件完整文件 + 简体中文翻译 + 中文化相关代码改动

## 汉化做了什么

所有文案原本集中在 `Locales.lua` 的英文表里，UI 与聊天代码全部通过 `ns.L` 取值，没有硬编码英文。本版本在文件末尾**追加了一个 zhCN 覆盖块**：只有 `GetLocale() == "zhCN"`（国服/中文客户端）时才生效，英文客户端读到的仍是原样英文。

| 文件 | 改动 |
|---|---|
| `Locales.lua` | 追加 zhCN 块，覆盖全部 519 个键；并提供种族/职业显示名表 |
| `Core/Utils.lua` | `RaceName` 优先读中文表；新增 `Utils.ClassName`（`ROGUE → 盗贼`） |
| `Detection/DeathReports.lua` | "等级、种族、职业"与通缉令正文的职业名改走 `Utils.ClassName` |
| `UI/MainWindow.lua` | 阵营切换按钮改用游戏全局 `FACTION_ALLIANCE/FACTION_HORDE`（显示"联盟/部落"） |

其余文件与原插件完全一致，**同步、检测、规则逻辑没有任何改动**。

### 翻译范围

- **界面**：主窗口 6 个页签与全部列头、鼠标提示、通缉令海报、耻辱柱、设置页、地图标记、悬赏与赛事对话框、确认弹窗
- **聊天**：`/hh help` 全部命令说明、各命令输出、载入行、未知命令提示
- **提醒**：中屏与聊天的目击/活动/追捕队/分层/热点/正法/悬赏领取/赛事签到/你被通缉等文案
- **词汇表**：通缉等级、徽章、猎人等级、决斗段位、击杀方式、场地名

保留原文：品牌与版本名（HeadHunter / WoW Forever / Classic Era）、命令语法（`/hh …`、`<name>` 等）、玩家名与公会名、地图区域名（由客户端本地化）。

### 主要译名

| 原文 | 中文 | 原文 | 中文 |
|---|---|---|---|
| WANTED | 通缉 | Hall of Shame | 耻辱柱 |
| posse | 追捕队 | bounty（悬赏金） | 悬赏 |
| bounty（积分） | 赏金 | Deadbeat | 老赖 |
| At large | 在逃 | Justice served | 正法 |
| Ganker → Dead or Alive | 偷袭者 → 生死不论 | Tracker → Reaper | 追踪者 → 死神 |

## 安装

1. 关闭游戏客户端。
2. 把本仓库的 `HeadHunter` 文件夹整个放进
   `World of Warcraft\_classic_beta_\Interface\AddOns\`
3. 启动游戏，中文客户端下界面与聊天即为中文。
4. 若客户端是英文但想看中文：把 `Locales.lua` 末尾的
   `if locale == "zhCN" then` 改为 `if locale == "zhCN" or locale == "enUS" then`。

升级原插件时：以上 4 个文件的改动需要保留（或重新应用），其余文件可直接被新版覆盖。

## 验证

| 检查 | 结果 |
|---|---|
| 全插件 Lua 语法（95 个 `.lua`） | 0 失败 |
| 原插件离线测试套件（Lua 5.1，39 个套件） | 477 通过 / 0 失败 |
| 中英文占位符（`%s`/`%d`/`%.1f`）数量与顺序 | 0 处不匹配 |
| 颜色转义码与分隔符一致性 | 0 处差异 |
| zhCN 引导与聊天冒烟（`/hh help`、`status`、`wanted`…） | 全部为中文 |

同步机制与端到端数据流的分析见 [`docs/工作流程与信息同步报告.md`](docs/工作流程与信息同步报告.md)。

## 声明与致谢

- 原插件的全部代码、美术资源与英文文案版权归原作者 **Vati（GudaAddons）** 所有，本仓库只是在其基础上添加中文翻译，任何语言文件的改进都应回馈原作者。
- 原插件发行包中**没有 LICENSE 文件**（默认保留全部权利），因此本汉化版同样不附加开源许可证；如原作者要求下架或调整署名，请开 Issue，我会立即处理。
- 汉化与分析报告由社区完成，与原作者无关；插件功能问题请通过原作者的 Discord（见原 `README.md`）反馈。
