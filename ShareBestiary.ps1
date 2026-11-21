# Lifts your bestiary export out of the game's saved file so you can send it
# in for the shared bestiary. Run it by double-clicking "Share Bestiary.bat".
#
# First, in game:  /men bestiary export   then  /reload  (or log out).
#
# The file it makes holds only creature records (names, levels, health,
# attacks, what they say, loot counts) and a made-up sender id. It does not
# hold your account, your characters, your kills or anything else from your
# settings. Nothing is sent anywhere: the file is put on your desktop.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
try {
    $saved = Join-Path $here '..\..\..\WTF\Account\*\SavedVariables\Meniscus.lua'
    $files = @(Get-ChildItem -Path $saved -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($files.Count -eq 0) {
        Write-Host 'No saved Meniscus settings were found. Run this from inside the Meniscus addon folder.'
        exit 1
    }
    $found = $null
    foreach ($f in $files) {
        $text = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
        $start = $text.IndexOf("`n[""bestiaryOut""] = {")
        if ($start -lt 0) { continue }
        # walk to the matching brace, minding quoted text
        $i = $text.IndexOf('{', $start)
        $open = $i; $depth = 0; $inText = $false; $end = -1
        while ($i -lt $text.Length) {
            $c = $text[$i]
            if ($inText) {
                if ($c -eq '\') { $i++ }
                elseif ($c -eq '"') { $inText = $false }
            }
            elseif ($c -eq '"') { $inText = $true }
            elseif ($c -eq '{') { $depth++ }
            elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { $end = $i; break } }
            $i++
        }
        if ($end -gt 0) { $found = $text.Substring($open, $end - $open + 1); break }
    }
    if (-not $found) {
        Write-Host 'No export was found in your saved settings.'
        Write-Host 'In game, type:  /men bestiary export   then  /reload  and run this again.'
        exit 1
    }
    $who = 'player'
    $m = [regex]::Match($found, '\["who"\] = "([0-9a-f]+)"')
    if ($m.Success) { $who = $m.Groups[1].Value.Substring(0, [Math]::Min(8, $m.Groups[1].Value.Length)) }
    $out = Join-Path ([Environment]::GetFolderPath('Desktop')) "Meniscus-bestiary-$who.txt"
    [IO.File]::WriteAllText($out, $found, (New-Object Text.UTF8Encoding($false)))
    $count = ([regex]::Matches($found, '\["n"\] = ')).Count
    Write-Host "Done: $count creatures written to"
    Write-Host "  $out"
    Write-Host 'Send that file to whoever keeps your copy of Meniscus up to date.'
}
catch {
    Write-Host "Something went wrong: $($_.Exception.Message)"
    exit 1
}
