# HeadHunter 汉化版(简体中文)

给 [HeadHunter - Wanted: Dead or Alive](https://headhunterwow.com) 插件做的简体中文本地化版本。

- **原始项目地址**：https://github.com/GudaAddons/HeadHunter（原作者 Vati / GudaAddons，当前 **v0.4.5**，官网 [headhunterwow.com](https://headhunterwow.com)）
- **汉化分支地址**：https://github.com/erchezhang/HeadHunter-cn
- **汉化：车长不二 完成**
- 适用客户端：Classic Era（Interface 11509）与 WoW Forever（Interface 16001）
- 本仓库内容：原插件完整文件 + 简体中文翻译，与上游 main 同步

## 汉化做了什么

文案集中在 `Locales.lua` 的英文表里，UI 与聊天代码通过 `ns.L` 取值。本仓库最初在 `Locales.lua` 末尾追加 zhCN 覆盖块，**该汉化已被原作者吸收进上游**（v0.3.2 起）：上游改为官方多语言架构，简体中文独立存放在 **`Locales_zhCN.lua`**，由 `ns.locale == "zhCN"` 门控（还支持 `HeadHunter_Dev` 插件切换语言预览），英文客户端读到的仍是原样英文。

| 文件 | 说明 |
|---|---|
| `Locales_zhCN.lua` | 简体中文全部文案（官方文件，头部署名“by 车长不二”） |
| `HeadHunter.toc` | `## Title-zhCN` / `## Notes-zhCN` 插件列表描述；`## X-Translated-By: 车长不二 (zhCN, zhTW)` |
| 其余代码 | 与上游完全一致——同步、检测、规则逻辑没有任何本地改动 |

### 翻译范围

- **界面**：主窗口各页签（通缉、欺凌者、老赖、落网、酒馆常客、决斗、我的死亡、我的赏金、赛事）与全部列头、鼠标提示、通缉令海报、设置页、地图标记、悬赏与赛事对话框、落网弹窗、确认弹窗
- **聊天**:`/hh help` 全部命令说明、各命令输出、载入行、未知命令提示
- **提醒**:中屏与聊天的目击/活动/追捕队/位面/热点/正法/悬赏领取/赛事签到/你被通缉等文案
- **词汇表**:通缉等级、徽章、猎人等级、决斗段位、击杀方式、场地名

保留原文:品牌与版本名(HeadHunter / WoW Forever / Classic Era)、命令语法(`/hh ...`、`<name>` 等)、玩家名与公会名、地图区域名(由客户端本地化)。

### 主要译名

| 原文 | 中文 | 原文 | 中文 |
|---|---|---|---|
| WANTED | 通缉 | Hall of Shame | 耻辱柱 |
| posse | 追捕队 | bounty(悬赏金) | 悬赏 |
| bounty(积分) | 赏金 | Deadbeat | 老赖 |
| At large | 在逃 | Justice served | 正法 |
| Ganker → Dead or Alive | 偷袭者 → 生死不论 | Tracker → Reaper | 追踪者 → 死神 |
| Bullies（页签） | 欺凌者 | Deadbeats（页签） | 老赖 |
| Busted（页签） | 落网 | Barflies（页签） | 酒馆常客 |
| Raise a glass | 举杯致敬 | Drunken Master | 醉拳大师 |
| layer（游戏机制） | 位面 | Duel spots | 决斗热点 |

## 安装

1. 关闭游戏客户端。
2. 把本仓库的 `HeadHunter` 文件夹整个放进
   `World of Warcraft\_classic_beta_\Interface\AddOns\`
3. 启动游戏，中文客户端下界面与聊天即为中文。
4. 想在英文客户端预览中文：安装可选插件 **HeadHunter_Dev** 并设 `locale = "zhCN"`（上游自带的开发开关）。

升级原插件时，直接用上游新版覆盖即可——汉化位于独立的 `Locales_zhCN.lua`，不会被覆盖冲突。

## 验证

| 检查 | 结果 |
|---|---|
| 官方离线测试套件（Lua 5.1，52 个套件，v0.4.5） | **629 通过 / 0 失败**（含上游 `test_locales`：每个键 zhCN 必须存在且格式符/颜色码一致） |
| zhCN 键覆盖 | enUS 628 键 / zhCN 638 键，缺失 0（0.4.1–0.4.5 新增 44 键均已翻译） |
| 术语修正（2026-10-05） | 汉化中 layer 统一译作**位面**（原“分层”），共修正 `Locales_zhCN.lua` 24 处、README/报告 4 处，残留 0 |
| README 中英对照完整性 | 上游英文行 100% 保留，每段均配中文译文 |

同步机制与端到端数据流的分析见 [`docs/工作流程与信息同步报告.md`](docs/工作流程与信息同步报告.md)。

## 声明与致谢

- 原插件的全部代码、美术资源与英文文案版权归原作者 **Vati(GudaAddons)** 所有,本仓库只是在其基础上添加中文翻译,任何语言文件的改进都应回馈原作者。
- 原插件发行包中**没有 LICENSE 文件**(默认保留全部权利),因此本汉化版同样不附加开源许可证;如原作者要求下架或调整署名,请开 Issue,我会立即处理。
- 汉化与分析报告由社区完成,与原作者无关;插件功能问题请通过原作者的 Discord(见原 `README.md`)反馈。
