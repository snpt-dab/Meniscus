Meniscus 0.1.237 (alpha) - a clean, dark, minimal UI for WoW: Forever

INSTALL
1. Close the game.
2. Download https://github.com/snpt-dab/Meniscus/archive/refs/heads/main.zip
   and unzip it.
3. The unzipped folder is called "Meniscus-main". RENAME IT to "Meniscus"
   (exactly that), and move it here:
     World of Warcraft\_forever_\Interface\AddOns\Meniscus
4. Check there is no folder-inside-a-folder: Meniscus.toc must be directly
   inside AddOns\Meniscus, next to Core.lua. (Windows' "Extract All" often
   makes Meniscus-main\Meniscus-main: use the inner one.)
5. Start the game. On the character screen, click AddOns and make sure
   Meniscus is ticked. If it is greyed out as "out of date", tick
   "Load out of date AddOns".

GAME SETTINGS IT EXPECTS
Meniscus places things itself and doesn't need a special Edit Mode layout:
the default one is fine. Three game settings do matter:
1. UI scale 0.65. The first time you log in, Meniscus offers to set it
   for you (it never changes it without asking); /men scale offers again.
   By hand: Esc > Options > Graphics > tick "Use UI Scale", set 0.65.
2. Action bars: Esc > Options > Action Bars > tick Action Bar 2 and
   Action Bar 3. They become the two small blocks beside the orbs.
3. After changing either, type /reload.

USING IT
/men            open the settings panel (every part can be switched off)
/men errors     show any errors the addon has caught
/reload         reload the UI after changing a setting that asks for it

This is an early test build. Some windows are replaced with new ones
(character, bags, bank, mail, spellbook, quest log, professions, merchant,
trainer, loot). If something looks broken or a game window is missing a
feature, please note what you were doing and send a screenshot, plus the
output of /men errors.

UPDATING
Close the game, open the Meniscus folder and double-click "Update Meniscus".
It downloads the latest version and replaces the addon's files; your
settings are kept. In game, /men version shows your version, and the addon
tells you in chat when it meets a player running a newer one.

REPORTING A BUG
/men bug <what went wrong>   (or just /men bug for a box to type in)

TO REMOVE
Delete the Meniscus folder. Your settings are kept in
  WTF\Account\<account>\SavedVariables\Meniscus.lua
which you can delete as well.

Fonts: Inter and Manrope (SIL Open Font License), see Media\FONTS.txt.
