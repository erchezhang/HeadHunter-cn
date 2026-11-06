# Changelog

## 1.0.4

- **Sharing works again on WoW Forever.** Since the launch, the server silently refuses addon messages on the HeadHunter channel, so deaths, WANTED, duels and alerts only reached your group. HeadHunter now shares them by whisper with the other HeadHunters in the channel, who pass them on. Everyone on 1.0.4 shares with everyone else on 1.0.4, so please update.
- `/hh sync` says when the server refuses the channel, and shows the new sharing with its counters.
- The online count and the Gang tab's online status come from the channel's member list.
- HeadHunter now tells you in chat when a newer version is out, once it hears it from two other players. From this version on, every update announces itself.

## 1.0.3

- **Gang waiting time:** coming back to the gang you left or were kicked from needs no wait (a kick by mistake, or a re-invite to fix gang chat). Joining or making another gang waits **1 hour** (it was 24 hours).

## 1.0.2

- **Gang tab in the Social window.** WoW Forever's Social window now has a **Gang** tab under Raid, with your gang's members, their class, level and online status, and Invite, Leave or Create gang. It works in the new side-tab window and in the older one, and it is on for everyone (turn it off with `/hh gang socialtab off`).

## 1.0.1

- **Gang chat works on WoW Forever.** The game refused the gang channels of 1.0.0 ("Invalid channel name"), so nobody got into gang chat. Gangs now get valid channels: a new gang has its chat at once, and a gang made with 1.0.0 gets its chat after one HeadHunter Sync and a reload.
- Gang chat goes into the main chat window once the game has joined it, and a refused join now says why in chat.

## 1.0.0

HeadHunter 1.0 for the WoW Forever release. Everything since 0.5.0:

### Gangs

- Friends can play under one **gang** name, up to 20 members, with one leader. Create one with **Create gang** or `/hh gang create <name>`, invite with **Invite target**, and accept the popup. A gang works at once, with its chat, and no reload; the website checks and keeps it, so every member needs **HeadHunter Sync**, and it shows "not on the website yet" until the next sync. A name someone took first gets a number, and the leader may rename it.
- The new **Gang** tab in the HeadHunter window lists your gang with class, level and online status. Right-click a member to whisper, invite to group, or as the leader hand over the lead or kick.
- **Gang chat**: `/gang <text>`, or `/gang` and a space to switch the chat box to it, like guild chat. Its lines show as [Gang] and can go into any chat window or tab.
- Tooltips show "Gang: <name>", and the website has a Gangs ranking and a page for each gang.
- Gang rules: a name is unique on your world, and after leaving a gang you wait 24 hours before joining another.
- The kill made by 3 or more attackers is now called **Pack** (it was Gang).

### WANTED and justice

- A WANTED player now needs kills on **at least 2 different players**, and one player's deaths count at most 3 times an hour. Nobody can make someone WANTED alone. Kills, totals and badges still count every death.
- **Punished:** Bullies and Deadbeats brought down while not WANTED are recorded, shared and shown next to Busted, with a PUNISHED popup, and they take glasses too.
- Joining a posse needs the outlaw's level window, from the popup and from the poster. A player far below cannot join or earn the +1.

### One world for every HeadHunter

- HeadHunters of every home server share one world through group bridges and nameplate links. A group always shares over party or raid, and a blocked channel is said only once.
- The website's lists are shared in game, and duel spots from one HeadHunter reach everyone and stay for 5 minutes.
- Each home keeps its own region, so a player on two regions is never filed in the other.

### Map

- Our map marks sit above other addons' marks. Shift-click to use them; a plain click goes through to the map.
- An invite whisper from the map is opened for you to send, at most once an hour per HeadHunter, and duel invites only from their zone.
- A war says whether you were in its zone. Group members far away are not counted in the fight, and Underdog is a 1 vs 1 win only.

### Classic Era

- HeadHunter runs on **Classic Era** again, in game only: the website and HeadHunter Sync are for WoW Forever.
- On Classic Era your death report goes to every HeadHunter on the realm with your Release Spirit, Reincarnation, resurrection or corpse click. The Report popup only asks once you are alive.
- A hunter's Feign Death is never busted, and a hunter and their pet count as one attacker.

### Releases

- Every release is uploaded to Wago, and to CurseForge.

## 0.5.0

This update covers everything since 0.3.6. Big fights now have a beginning and an end, duelers can find each other across layers, the Bounty board has new tabs, and HeadHunter runs smoothly even in the busiest dueling spots.

### Wars and PvP areas

- When a zone starts burning on the map, HeadHunter follows the fight as a **war** until it has been quiet for 10 minutes. It keeps who fought on both sides, the layers they were on, and your honorable kills and deaths. The HeadHunter website shows each war with both sides.
- Your honorable kills are kept by zone and time, so the website can show how a fight went. `/hh hk` shows yours from the last 24 hours.
- A PvP area of 2 or more fires can be clicked on the map: you get the way there, and if the fight is on another layer, a whisper to a HeadHunter there asking for an invite.
- PvP areas show crossed swords, leave the map 10 minutes after the fight, and only count enemy players who fight your side.

### Duels

- **Duel spots:** where at least 5 players have dueled 10 times in 20 minutes, the map shows a duel mark with every layer. Click it for an invite whisper to a HeadHunter on that layer.
- The Duels list shows the best **300 duelists of each faction**, with an All, Alliance and Horde switch. Every duel still goes to the website, which ranks everyone.
- Search finds any duelist, also past the top 300. They show without a place, and so does their title in tooltips, for example "Quickdraw (+2)".

### Bounty board and Busted

- **Bullies** and **Deadbeats** have their own tabs on the Bounty board, and every tab has a search box and race, class and faction icons.
- The new **Busted** tab lists every catch, with who made it and where, including the website's catches.
- **Raise a glass** to a catch in the Busted list. The hunter gets a chat line and a poster under the minimap, and the **Barflies** view shows who raised the most.
- Players' gold bounties from the website show in game and can be claimed. A claim only makes someone a Deadbeat when another player saw it, and everyone can see who saw each claim.
- A WANTED player now needs **5 kills in 20 minutes** (was 4), and Ganker starts at 5.

### Screenshots

- With HeadHunter Sync installed, HeadHunter takes a screenshot of each PvP death and catch for the HeadHunter admins, as proof. It is on by default and can be turned off in the options. Only the middle of the screen is sent.

### Fairness

- Deaths shared live that arrive more than an hour late no longer count.
- Data from the login catch-up only counts once a second player has it too.
- A HeadHunter who sees a hunted player die tells the others where and when, and sightings of outlaws move the map skull and the posse waypoint.
- HeadHunter stops listening in battlegrounds and other instances.

### Window and speed

- Dueling zones no longer freeze the game. The duel lists are only counted when the Duels tab or a tooltip needs them, and a little at a time.
- The window opens quickly and lists everyone on every tab, not just the first 300.
- Resize the window from its bottom right corner.
- List tooltips open at the mouse, and clickable names in alerts are in the whisper color.

### Fixes

- A hunter and her pet count as one attacker in a WoW Forever death report.
- A player's race, class and level are kept when a report names them twice.
- Our own sighting of a player beats what reports say about them.
- PvP scan and sync messages go to the log only, never to chat.

## 0.3.6

This is a big update. Tournaments now come to the game from the HeadHunter website, and organizers can run matches right in the addon. Catches are also fairer when you fight in a group.

### Events

- The window is better organized. There are four sections now: **Bounty board**, **Duels**, **Events** and **Me**, each with its own small tabs.
- **Events** lists the tournaments on your realm, sorted into **Ongoing** and **Upcoming**.
- Click an event to see its rounds: who plays who, the scores and the winners. It opens on the round being played now.
- **Copy link** gives you the event's page on the website. Press Ctrl+C and paste it in your browser.
- Players show their race and class icons, and their names are in class colors.
- Events are made on the website. The Events list has a **Create an event** button with the link to copy.
- The match for 3rd place and matches where a player did not come are now easy to read. Move your mouse over a match to see all the details.

### Running a match (for organizers)

- The host and co-organizers can **Call** a match. Both players get an alert and a whisper, and they have 3 minutes to get ready. Players without the addon get the whisper too, and they can answer "ready".
- Players click **Ready**, then **Duel**. Each duel between them counts as a game of the match (Best of 1, 3 or 5).
- When the match is decided, the organizer checks the score and clicks **Confirm**. Every HeadHunter nearby sees the bracket move on at once.
- If a player is not ready after 3 minutes, the organizer can give the match as a no-show or call it again.
- The organizer can also set or change a result by hand.
- **Sync to website** sends your confirmed results to the website. It reloads your interface quickly, then HeadHunter Sync uploads them a few seconds later. You need HeadHunter Sync 0.2.1 or newer for this.

### Marks above the head

- WANTED players show the HeadHunter mark above their head.
- Players in the Hall of Shame show a white feather.
- Tournament hosts and co-organizers show a sheriff star, also in tooltips and chat.
- You can turn each mark on or off in the settings.
- `/hh organizers` lists the organizers the addon knows.

### Catches and alerts

- You no longer need the last hit. If you, your pet or your group hit a WANTED player in the last minute and someone else kills them, it still counts as your catch.
- On WoW Forever, a group kill now counts through the game's "honorable kill" message, even if the WANTED player was not your target.
- When you spot an outlaw, HeadHunters nearby are told too. It is limited, so nobody gets spammed.
- Click a fighter's name in the skirmish line in chat to whisper them.

### Fixes

- Each character now sees only its own deaths and has its own bounty.
- Duel witnesses find the level of both players more often.
- The result menu in the event view now shows its choices.
