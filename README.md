[![Patreon](https://img.shields.io/badge/Patreon-F96854?logo=patreon&logoColor=white&style=for-the-badge)](https://www.patreon.com/cw/GudaAddons)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-29ABE0?logo=kofi&logoColor=orange&style=for-the-badge)](https://ko-fi.com/guda)
[![Discord](https://img.shields.io/badge/Discord-5865F2?logo=discord&logoColor=white&style=for-the-badge)](https://discord.gg/kcqV4dcrxJ)

# HeadHunter - Wanted: Dead or Alive

> **简体中文汉化版 · Simplified Chinese localization**
>
> 本仓库在原插件 **v0.3.1**（作者 Vati / [GudaAddons](https://headhunterwow.com)）基础上加入了简体中文翻译：
>
> - **翻译范围**：主窗口、通缉令、鼠标提示、设置页、地图标记等浏览界面，`/hh help` 的全部命令说明与输出，以及中屏/聊天提醒——共 **519 条文案**全量覆盖（原插件文案集中在 `Locales.lua`）
> - **实现方式**：`Locales.lua` 末尾的 zhCN 覆盖块仅在 `GetLocale() == "zhCN"` 时生效，英文客户端读到的仍是原版英文；另有 3 处小改动用于种族/职业/阵营的中文显示（`Core/Utils.lua`、`Detection/DeathReports.lua`、`UI/MainWindow.lua`），**同步与游戏逻辑未改动**，原插件 477 项离线测试全部通过
> - **安装 / 译名 / 升级说明**：见 [README.zh-CN.md](README.zh-CN.md)；同步机制与端到端数据流分析见 [docs/工作流程与信息同步报告.md](docs/工作流程与信息同步报告.md)
>
> 原插件无 LICENSE 文件，代码与英文文案版权归原作者；汉化版仅供个人使用与学习，如原作者有异议请开 Issue，会立即处理。
>
> English: this fork adds a Simplified Chinese localization on top of HeadHunter v0.3.1 by Vati (GudaAddons). Everything below is the original, unchanged documentation.

---

**Got ganked? HeadHunter records who killed you, shares it with your faction and marks WANTED outlaws on the map. Form a posse and bring them to justice.**

For **Classic Era** and **WoW: Forever**.

See the WANTED board, the best duelists and the top hunters on **[headhunterwow.com](https://headhunterwow.com)**.

![The WANTED list: outlaws of both factions with their rank, kills, last kill and badges](Assets/1.png)

## How it works

1. **An enemy player kills you.** HeadHunter saves who did it: name, level, class, race and zone. If more than one player attacked you, it saves all of them.
2. **Your report is shared** with every HeadHunter player of your faction.
3. **Gankers become WANTED.** An enemy who kills 4 players within 20 minutes gets a WANTED poster. Every HeadHunter sees the same list.
4. **Hunt them down.** You get an alert when a WANTED outlaw kills someone near you. Join the posse and go after them.
5. **Justice served.** When a HeadHunter, or anyone in their group, kills a WANTED outlaw, the outlaw is no longer WANTED for everyone.
6. **See it all on the website.** With the free **HeadHunter Sync** app, your reports go to [headhunterwow.com](https://headhunterwow.com), and the website's lists come back into your game.

## Features

### WANTED list and ranks
- An outlaw stays WANTED until a HeadHunter kills them, or until 7 days pass without a new kill.
- Ranks grow with kills: **Ganker**, **Outlaw**, **Desperado**, **Most Wanted** and **Dead or Alive**.

### Badges
Badges show *how* someone kills, not only how much:
- **Bully**: killed a player 10 or more levels lower, or a grey level player.
- **Duo**: killed a lone player together with one other enemy (2 vs 1).
- **Gang**: killed a lone player in a group of 3 or more.
- **Serial Killer**: 5 different victims in separate fights within a short time.
- **Gunslinger**: most kills were fair, one on one, at a similar level.
- **Underdog**: killed higher level players alone.

If your own group was in the fight, the kill shows as a **group fight** (for example 4 vs 3) and gives no Duo or Gang badge. It still counts toward WANTED.

### Hall of Shame
- **Bullies**: every enemy with the Bully badge, WANTED or not. They stay as long as HeadHunter knows one of their lowbie kills (30 days). With the HeadHunter Sync app you also get the website's bullies of both factions, so your list matches the website.
- **Deadbeats**: players who did not pay a gold bounty they posted (see *Gold bounties*). They are listed for 30 days, and they cannot post bounties during that time.
- You get an alert when a bully or a Deadbeat is near. Turn it off in the options (**Hall of Shame alerts**).
- Bring down a bully, or a Deadbeat of the other faction, and you get **+3 bounty**, once per player per hour. They stay on the list.

![The Hall of Shame: every known bully, WANTED or not](Assets/5.png)

### Alerts
- **WANTED sighting**: "WANTED Ganker X is here!" when a WANTED outlaw shows up on your screen, even in combat.
- **WANTED activity**: a WANTED outlaw killed someone near you. Click **Join the posse** or **Decline**. HeadHunter shows at most one popup every 3 minutes. After a Decline, or a popup you let close by itself, you get no more of these popups for 20 minutes, only chat lines. While you ride with a posse, other outlaws only ask when they are in your zone. Only players close to the outlaw's level get this popup, the others get a chat line. If the victim is on another layer and died again within 15 minutes, joining also asks them for a group invite.
- **Justice served**: a message when a WANTED outlaw is brought down.
- **Gold bounty sighting**: "BOUNTY: X is here!" when a player with a gold bounty on them shows up.
- **Your bounty is claimed**: a message when a HeadHunter brings down the player you put gold on.
- **Hall of Shame**: "BULLY: X is here!" or "DEADBEAT: X is here!", at most once every 10 minutes per player.
- **You are WANTED**: with the HeadHunter Sync app, HeadHunter tells you at login when the other faction has you on its WANTED list.
- **PvP hotspots**: Skirmish, Battle or Warzone when a big fight happens near you. The popup names the enemies in the fight and the HeadHunters of your side fighting there. Click **Help** to get the way to the fight: the HeadHunters fighting there see that you are coming, and if they are on another layer, one of them is asked for a group invite.

### World map
- A red **PVP** area shows where fights are happening. It gets darker as the fight grows and stays for 20 minutes after the last fight.
- A **skull** shows where a WANTED outlaw made their last kill (for 10 minutes). The map shows the 10 biggest fights and the 10 highest ranked outlaws.

![A PvP area on the world map](Assets/screenshot-map.png)

### HeadHunter window
Type `/hh` or click the minimap button:
- **WANTED**: everyone who is WANTED now, sorted by rank, kills or last kill, with a switch between the Alliance and Horde lists (the enemy list opens first). Gold bounties are listed on top. While few outlaws are WANTED, the list fills up to 25 with outlaws **at large**: their WANTED time ran out, but nobody caught them. You get the same alert when you meet one, and catching one still pays their bounty.
- **Hall of Shame**: every known bully, and the Deadbeats.
- **Duels**: the best duelists, with a switch between the Alliance and Horde lists.
- **My deaths**: who killed you, when and where.
- **My bounty**: the bounty you collected and your hunter rank.

Hover a name for details, or click it to open the outlaw's **poster**: race and class, rank, badges, recent kills, posse, gold bounties and the **Join the posse** and **Post a bounty** buttons.

![My deaths, with the details of a killer on hover](Assets/4.png)

### Enemy tooltips
Mouse over an enemy player to see if they are WANTED, their rank, kills and badges. Any player with duels also shows their duel rank.

### Posse and hunter ranks
- Join a posse to hunt an outlaw together. Posse members see each other.
- Collect **bounty**: +1 for joining a posse (once per outlaw while they are WANTED), and +3 to +20 when you or your group bring down a WANTED outlaw (the higher their rank, the bigger the bounty). +5 for bringing down a player with a gold bounty, +3 for a bully or the other faction's Deadbeat. Declining costs 1; a popup that closes by itself costs nothing.
- No bounty for hunting players 10 or more levels below you. Hunting down is ganking too.
- Hunter ranks: **Tracker**, **Bounty Hunter**, **Manhunter**, **Headhunter** and **Reaper**.

![My bounty: what earned or cost bounty, and your hunter rank](Assets/3.jpg)

### Gold bounties
Got ganked? Put gold on your killer's head.
- From level 15: open the poster of an enemy (level 15 or higher too) who killed you, or helped, in the last 24 hours and click **Post a bounty**. Pick a reason (Camped me, Ganked me while I fought mobs, Killed me at low level, Killed me in a group), the gold (2g to 15g) and how long it runs (1, 2, 3 or 7 days). One bounty at a time.
- Every HeadHunter of your faction sees it: on top of the WANTED list, on the tooltip and the poster, and with an alert when they meet the target.
- The HeadHunter who lands the killing blow wins the gold, and everyone who saw it gets +5 bounty. No gold for hunting 10 or more levels down. One kill wins one bounty (the biggest); the others stay open. The same hunter cannot claim on the same player again for 7 days.
- You get a message when your bounty is claimed. At your next mailbox, HeadHunter asks you to send the gold, and one click writes the mail. HeadHunter never sends gold without your click, and never more than you posted.
- The hunter's HeadHunter sees your mail and marks you as **pays up**. Not paid after 3 days, the claim is unpaid. If you do not pay, you are a **Deadbeat**: no bounties for 30 days and your name in the Hall of Shame. Paying late gets you out.
- If the same hunter claimed on that player before, the mail window warns you that it may be an alt. You can refuse that one without becoming a **Deadbeat**.
- **Classic Era:** after claiming, click **Announce** (or type `/hh claim`) so the owner hears about it, even outside your guild and group.

### Catch-up
When you log in, HeadHunter asks other HeadHunters what you missed while you were offline, so your WANTED list is up to date.

### Who is online
Type `/hh online` to see how many HeadHunters are online right now, how many are Alliance and how many are Horde.
- **WoW Forever:** everyone in your region, both factions.
- **Classic Era:** only your guild and group. The game does not let addons count further.
- With more than 500 online, it says **500+**.

### Duels
- Classic Era: every duel next to a HeadHunter counts, even when the duelists do not use the addon, as long as HeadHunter knows both levels (target or mouse over the duelists). WoW Forever: duels count when one of the duelists uses HeadHunter. Running away counts as a loss.
- Only duels between players of level 10 or higher, at most 5 levels apart, count. Beating lowbies does not help.
- Duels are shared like death reports, and never make anyone WANTED.
- Click a player of your own faction in the Duels list to whisper them.
- Ranked by record: wins minus losses first, then fewer losses. 6-1 is ahead of 8-3. With the same record, whoever got there first is ahead. You are listed from your first duel.
- Ranks by net wins: **Quickdraw**, **Sharpshooter** (+5), **Deadeye** (+15) and **Legend** (+30). Under 5 duels you are a **Greenhorn**, listed after everyone with 5 or more.
- The #1 of each faction is the **Top Gun**, once they are 5 or more wins ahead (Sharpshooter) and nobody else at the top has the same record. A Greenhorn cannot be Top Gun.

![Duels: the Horde list with its Top Gun and records](Assets/2.jpg)

## Website and the HeadHunter Sync app

**[headhunterwow.com](https://headhunterwow.com)** is the bounty board of every HeadHunter player: WANTED posters, the best duelists, the top hunters and the Hall of Shame, for each game and realm. Sign in with Battle.net, Discord, Google or email to see your own characters.

A WoW addon cannot use the internet. That is why there is a small, free desktop app: **HeadHunter Sync**. It connects the game and the website.

1. **Download** HeadHunter Sync for Windows or Mac from [GitHub](https://github.com/GudaAddons/headhunter-sync/releases/latest) and sign in with your website account.
2. **Play as usual.** When the game saves (logout, `/reload` or quit), the app sends your deaths, catches, duels, bounty and gold bounties to the website. It runs quietly in the tray.
3. **Get the website's lists back.** The app also writes the website's WANTED list, duel lists and your own records into the game, as a small extra addon called **HeadHunter Data**. You see them after your next login or `/reload`.
4. **WoW Forever:** when your lists reset (see *Good to know*), the app brings your own deaths, duels and bounty back.
5. **Every realm keeps its own data:** PvP, Normal, Roleplay and Hardcore (and every Classic Era realm) each have their own lists, deaths, duels and bounty. A character on a Normal realm sees only Normal realm data. HeadHunter data saved before this update went to the WoW Forever PvP realm.

Good to know about the app:
- The app only reads HeadHunter's saved data and only talks to headhunterwow.com. Nothing else on your PC is touched.
- It updates itself.
- The first time, Windows may say "Windows protected your PC". Click **More info**, then **Run anyway**. On a Mac, right-click the app and choose **Open**.
- The addon works fine without the app. The app only adds the website.

## Commands

| Command | What it does |
|---|---|
| `/hh` | Open the HeadHunter window |
| `/hh help` | List all commands |
| `/hh options` | Open the options page |
| `/hh wanted` | WANTED list in chat |
| `/hh outlaw <name>` | Details about one enemy |
| `/hh deaths` | Your recent PvP deaths |
| `/hh posse` | Who is hunting which outlaw |
| `/hh bounty` | Your hunter rank and the bounty you collected |
| `/hh hotspots` | PvP activity per zone |
| `/hh duels` | Duels: the best duelists and your rank |
| `/hh map on/off` | PvP areas and skulls on the world map |
| `/hh tooltip on/off` | WANTED line on enemy tooltips |
| `/hh minimap` | Show or hide the minimap button |
| `/hh claim` | Announce your gold bounty claim to all HeadHunters (Classic Era) |
| `/hh catchup` | Ask other HeadHunters what you missed |
| `/hh online` | How many HeadHunters are online, per faction |

All settings are also on the options page: **Esc > Options > AddOns > HeadHunter**.

## Good to know

- **Classic Era:** reports go to your guild and group automatically. To reach every HeadHunter on the realm, click **Report** after a death (or type `/hh report`). The same goes for **Announce** after you bring down an outlaw (`/hh justice`). The game only allows these realm-wide messages after a click.
- **Classic Era** has no map waypoints, so HeadHunter tells you the coordinates in chat instead.
- **WoW: Forever** shares everything automatically.
- **WoW: Forever is in testing mode.** The Forever client does not load saved data back (a known client issue, not a HeadHunter bug), so your lists and settings reset on every reload or login. Catch-up handles it: when you log in, other HeadHunters send back what you missed, so your lists refill from the realm. The HeadHunter Sync app also brings your own records back from the website. HeadHunter tells you this in chat when you log in on Forever.
- HeadHunter is off in dungeons, raids and battlegrounds. Duels never count as PvP kills.
- Gold bounties are paid by mail between players of the same faction. HeadHunter never holds your gold.
- **Classic Era:** the other faction's Deadbeats reach you through the website, so use the HeadHunter Sync app. WoW Forever shares them directly.
- The more players use HeadHunter, the better it works. Tell your guild!
