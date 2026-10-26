param([string]$Name, [int]$WaitSec = 20, [string]$Since, [string]$Dir = "$env:USERPROFILE\Hajime\ai-gen")
# Move the newest Gemini image (newer than $Since, default 3 min ago) from Downloads to the gen folder.
# Extra recent copies (from a double click) go to gen\dup so Downloads stays as it was.
$dir = $Dir
New-Item -ItemType Directory -Force "$dir\dup" | Out-Null
$limit = if ($Since) { Get-Date $Since } else { (Get-Date).AddMinutes(-3) }
for ($i = 0; $i -lt $WaitSec; $i++) {
    $fs = @(Get-ChildItem "$env:USERPROFILE\Downloads\Gemini_Generated_Image_*" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $limit } | Sort-Object LastWriteTime)
    if ($fs.Count -gt 0) {
        Start-Sleep 3
        $fs = @(Get-ChildItem "$env:USERPROFILE\Downloads\Gemini_Generated_Image_*" | Where-Object { $_.LastWriteTime -gt $limit } | Sort-Object LastWriteTime)
        Move-Item $fs[-1].FullName "$dir\$Name.jpg"; "moved $($fs[-1].Name) -> $Name.jpg"
        for ($k = 0; $k -lt $fs.Count - 1; $k++) { Move-Item $fs[$k].FullName "$dir\dup\$Name-$k.jpg"; "dup $($fs[$k].Name)" }
        exit 0
    }
    Start-Sleep 1
}
"not found: $Name"
