<#
.SYNOPSIS
	Fetch HTB machine OS, difficulty, and icon. Update markdown frontmatter.
.DESCRIPTION
	Takes three arguments: the HTB machine name, the absolute path of the markdown note,
	and the output directory for the machine icon.
	If _os, _difficulty, or _image are already filled, they are left unchanged.
	The icon is only downloaded if no existing file is present and _image is empty.
	Edit $EnableDebug to enable debug output.
#>

[CmdletBinding()]
param(
	[Parameter(Mandatory = $true, Position = 0)]
	[string]$MachineName,

	[Parameter(Mandatory = $true, Position = 1)]
	[string]$MarkdownPath,

	[Parameter(Mandatory = $true, Position = 2)]
	[string]$OutputPath
)

$ErrorActionPreference = "Stop"
$EnableDebug = $false

function Get-HtbSlug {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Name
	)

	# Match prior icon script behavior: lowercase, alphanumeric only.
	return ($Name.ToLower() -replace '[^a-z0-9]', '')
}

function Get-HtbValue {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Html,

		[Parameter(Mandatory = $true)]
		[string]$SectionClass
	)

	# (?s) = Singleline mode (. matches newlines), (?i) = case-insensitive
	$pattern = '(?si)<div[^>]*class="' + [regex]::Escape($SectionClass) + '[^"]*"[^>]*>.*?<span[^>]*>(?<value>[^<]+)</span>'
	$match = [regex]::Match($Html, $pattern)

	if (-not $match.Success) {
		return $null
	}

	return ($match.Groups["value"].Value).Trim()
}

function Get-FrontmatterValue {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Frontmatter,

		[Parameter(Mandatory = $true)]
		[string]$Field
	)

	$pattern = '(?m)^[ \t]*' + [regex]::Escape($Field) + '[ \t]*:[ \t]*([^\r\n]*)$'
	$match = [regex]::Match($Frontmatter, $pattern)
	if ($match.Success) {
		return $match.Groups[1].Value.Trim()
	}

	return $null
}

function Test-FrontmatterValueBlank {
	param(
		[string]$Value
	)

	if ($null -eq $Value) {
		return $true
	}

	$trimmed = $Value.Trim()
	if ($trimmed -eq '') {
		return $true
	}

	if ($trimmed -match '^(?:""|'''')$') {
		return $true
	}

	return $false
}

function Set-FrontmatterValue {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Frontmatter,

		[Parameter(Mandatory = $true)]
		[string]$Field,

		[Parameter(Mandatory = $true)]
		[string]$Value,

		[Parameter(Mandatory = $true)]
		[string]$Newline
	)

	$pattern = '(?m)^[ \t]*' + [regex]::Escape($Field) + '[ \t]*:[ \t]*.*$'
	if ([regex]::IsMatch($Frontmatter, $pattern)) {
		return [regex]::Replace($Frontmatter, $pattern, "${Field}: $Value", 1)
	}

	$trimmed = $Frontmatter.TrimEnd("`r", "`n")
	if ($trimmed -eq '') {
		return "${Field}: $Value"
	}

	return $trimmed + $Newline + "${Field}: $Value"
}

if (-not (Test-Path $MarkdownPath)) {
	Write-Host "[-] Markdown file not found: $MarkdownPath"
	exit 1
}

if (-not (Test-Path $OutputPath -PathType Container)) {
	Write-Host "[-] Output directory not found: $OutputPath"
	exit 1
}

$slug = Get-HtbSlug -Name $MachineName
$url = "https://www.hackthebox.com/machines/$slug"
$imageFileName = "htb_$slug.png"
$imagePath = Join-Path $OutputPath $imageFileName

$content = Get-Content -Path $MarkdownPath -Raw
$newline = if ($content -match "`r`n") { "`r`n" } else { "`n" }

$frontmatterMatch = [regex]::Match($content, '(?s)\A(?:\uFEFF)?---\s*[\r\n]+(.*?)[\r\n]+---')
$frontmatterFound = $frontmatterMatch.Success

$frontmatter = $null
$osValue = $null
$difficultyValue = $null
$imageValue = $null

if ($frontmatterFound) {
	$frontmatter = $frontmatterMatch.Groups[1].Value
	$osValue = Get-FrontmatterValue -Frontmatter $frontmatter -Field "_os"
	$difficultyValue = Get-FrontmatterValue -Frontmatter $frontmatter -Field "_difficulty"
	$imageValue = Get-FrontmatterValue -Frontmatter $frontmatter -Field "_image"
} else {
	Write-Host "[!] No YAML frontmatter found in $MarkdownPath"
}

$needsOs = $frontmatterFound -and (Test-FrontmatterValueBlank -Value $osValue)
$needsDifficulty = $frontmatterFound -and (Test-FrontmatterValueBlank -Value $difficultyValue)
$hasImageValue = -not (Test-FrontmatterValueBlank -Value $imageValue)
$imageExists = Test-Path $imagePath

if ($EnableDebug) {
	Write-Host "[dbg] frontmatterFound=$frontmatterFound"
	Write-Host "[dbg] _os='$osValue' needsOs=$needsOs"
	Write-Host "[dbg] _difficulty='$difficultyValue' needsDifficulty=$needsDifficulty"
	Write-Host "[dbg] _image='$imageValue' hasImageValue=$hasImageValue imageExists=$imageExists"
}

$shouldDownloadImage = (-not $imageExists) -and (-not $hasImageValue)
$needsFetch = $needsOs -or $needsDifficulty -or $shouldDownloadImage

$html = $null
if ($needsFetch) {
	Write-Host "[*] Fetching HTB page: $url" -NoNewline
	try {
		$response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
		$html = $response.Content
		Write-Host " OK"
	} catch {
		Write-Host ""
		Write-Host "[-] Page fetch failed: $url"
		exit 1
	}
} else {
	Write-Host "[=] No fetch required; fields already filled and/or image already present."
}

$os = $null
$difficulty = $null
if ($needsOs) {
	$os = Get-HtbValue -Html $html -SectionClass "machine-os"
	if ([string]::IsNullOrWhiteSpace($os)) {
		Write-Host "[-] Could not parse machine OS from $url."
		exit 1
	}
	$os = $os.ToLowerInvariant()
}

if ($needsDifficulty) {
	$difficulty = Get-HtbValue -Html $html -SectionClass "machine-difficulty"
	if ([string]::IsNullOrWhiteSpace($difficulty)) {
		Write-Host "[-] Could not parse machine difficulty from $url."
		exit 1
	}
	$difficulty = $difficulty.ToLowerInvariant()
}

$imageUrl = $null
$imageDownloaded = $false
if ($shouldDownloadImage) {
	$pattern = 'https://htb-mp-prod-public-storage\.s3\.eu-central-1\.amazonaws\.com/avatars/[A-Za-z0-9]+\.png'
	$imageUrl = if ($html -match $pattern) { $matches[0] } else { $null }

	if (-not $imageUrl) {
		Write-Host "[!] No icon URL found on page."
	} else {
		Write-Host "    [*] Downloading icon..." -NoNewline
		try {
			Invoke-WebRequest -Uri $imageUrl -OutFile $imagePath -UseBasicParsing -ErrorAction Stop
			Write-Host " OK"
			Write-Host "    [+] Saved $imagePath"
			$imageDownloaded = $true
		} catch {
			Write-Host ""
			Write-Host "[-] Download failed for $imageUrl"
			exit 1
		}
	}
}

if ($frontmatterFound) {
	$updatedFrontmatter = $frontmatter
	$changes = @()

	if ($needsOs) {
		$updatedFrontmatter = Set-FrontmatterValue -Frontmatter $updatedFrontmatter -Field "_os" -Value $os -Newline $newline
		$changes += "_os"
	}

	if ($needsDifficulty) {
		$updatedFrontmatter = Set-FrontmatterValue -Frontmatter $updatedFrontmatter -Field "_difficulty" -Value $difficulty -Newline $newline
		$changes += "_difficulty"
	}

	if (-not $hasImageValue) {
		if (Test-Path $imagePath) {
			$imageLink = "`"[[$imageFileName]]`""
			$updatedFrontmatter = Set-FrontmatterValue -Frontmatter $updatedFrontmatter -Field "_image" -Value $imageLink -Newline $newline
			$changes += "_image"
		}
	}

	if ($changes.Count -gt 0) {
		$newFrontmatterBlock = "---$newline$updatedFrontmatter$newline---"
		$prefix = $content.Substring(0, $frontmatterMatch.Index)
		$suffix = $content.Substring($frontmatterMatch.Index + $frontmatterMatch.Length)
		$updatedContent = $prefix + $newFrontmatterBlock + $suffix

		if ($updatedContent -ne $content) {
			Set-Content -Path $MarkdownPath -Value $updatedContent -NoNewline
			Write-Host "[+] Updated frontmatter fields: $($changes -join ', ')"
		} else {
			Write-Host "[=] Frontmatter already up to date."
		}
	} else {
		Write-Host "[=] No frontmatter changes needed."
	}
} else {
	if ($needsOs -or $needsDifficulty) {
		Write-Host "[!] OS/Difficulty parsed but frontmatter missing; not updating note."
	}
	if ($imageDownloaded) {
		Write-Host "[!] Image downloaded but frontmatter missing; not updating note."
	}
}

Write-Host "[=] Done."
