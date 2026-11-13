# Updates this Meniscus addon folder to the latest version on GitHub.
# Run it by double-clicking "Update Meniscus.bat" (game closed is best).
# Your settings are not touched: they live in WTF\Account\...\SavedVariables.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$url  = 'https://github.com/snpt-dab/Meniscus/archive/refs/heads/main.zip'

function Get-TocVersion($folder) {
    $toc = Join-Path $folder 'Meniscus.toc'
    if (-not (Test-Path $toc)) { return $null }
    $m = Select-String -Path $toc -Pattern '^## Version:\s*(\S+)' | Select-Object -First 1
    if ($m) { return $m.Matches[0].Groups[1].Value }
    return $null
}

try {
    if (Test-Path (Join-Path $here '.git')) {
        Write-Host 'This is the development copy of Meniscus (it has a .git folder). Nothing to do here.'
        exit 0
    }
    if (-not (Test-Path (Join-Path $here 'Meniscus.toc'))) {
        Write-Host 'Meniscus.toc is not next to this file. Run the updater from inside the Meniscus addon folder.'
        exit 1
    }
    $old = Get-TocVersion $here
    Write-Host "Installed version: $old"
    Write-Host 'Downloading the latest version...'

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $tmp = Join-Path $env:TEMP 'Meniscus-update'
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    New-Item -ItemType Directory -Path $tmp | Out-Null
    $zip = Join-Path $tmp 'main.zip'
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $tmp -Force

    $src = Join-Path $tmp 'Meniscus-main'
    $new = Get-TocVersion $src
    if (-not $new) { throw 'The download does not look like Meniscus (no Meniscus.toc in it).' }
    Write-Host "Latest version:    $new"

    if ($new -eq $old) {
        Write-Host ''
        Write-Host 'You are already up to date.'
    } else {
        # Mirror the download into this folder: new and changed files are
        # copied, files that no longer exist are removed. Development-only
        # files are left out.
        robocopy $src $here /MIR /XD .git dist .claude /XF CLAUDE.md .gitignore .gitattributes /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) {
            throw "Copying the files failed (robocopy code $LASTEXITCODE). Close the game and try again; if the game is installed under Program Files, right-click 'Update Meniscus.bat' and choose 'Run as administrator'."
        }
        Write-Host ''
        Write-Host "Updated: $old -> $new"
        if (Get-Process -Name 'Wow*' -ErrorAction SilentlyContinue) {
            Write-Host 'The game is running: close it completely and start it again to load the new version.'
        } else {
            Write-Host 'Start the game to use the new version.'
        }
    }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    exit 0
} catch {
    Write-Host ''
    Write-Host "Update failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
