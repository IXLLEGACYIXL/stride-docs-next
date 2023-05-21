<#
.SYNOPSIS
    This script builds documentation (manuals, tutorials, release notes) in selected language(s) from the languages.json file and optionally includes API documentation.

.DESCRIPTION
    The script allows the user to build documentation in English or any other available language specified in the languages.json file. It provides options to build documentation in all available languages, run a local website for the documentation, or cancel the operation. If the user chooses to build the documentation, the script also prompts whether API documentation should be included.

.NOTES
    The documentation files are expected to be in Markdown format (.md). The script uses the DocFX tool to build the documentation and optionally includes API documentation. The script generates the API documentation from C# source files using DocFX metadata and can run a local website using the DocFX serve command. This script can also be run from GitHub Actions.

.LINK
    https://github.com/VaclavElias/stride-website-next
    https://github.com/VaclavElias/stride-docs-next/blob/main/languages.json
    https://dotnet.github.io/docfx/index.html

.PARAMETER BuildAll
    Switch parameter. If provided, the script will build documentation in all available languages and include API documentation.

.EXAMPLE
    .\BuildDocs.ps1 -BuildAll
    In this example, the script will build the documentation in all available languages and include API documentation. Use this in GitHub Actions.

.EXAMPLE
    .\BuildDocs.ps1
    In this example, the script will prompt the user to select an operation and an optional language. If the user chooses to build the documentation, the script will also ask if they want to include API documentation.
#>

param (
    [switch]$BuildAll
)

# Define constants
$Settings = [PSCustomObject]@{
    LanguageJsonPath = ".\languages.json"
    TempDirectory = "_tmp"
    SiteDirectory = "_site"
    HostUrl = "http://localhost:8080/en/index.html"
    IndexFileName = "index.md"
    ManualFolderName = "manual"
}

# To Do fix, GitHub references, fix sitemap links to latest/en/

function Read-LanguageConfigurations {
    return Get-Content $Settings.LanguageJsonPath -Encoding UTF8 | ConvertFrom-Json
}

function Get-UserInput {
    Write-Host ""
    Write-Host -ForegroundColor Cyan "Please select an option:"
    Write-Host ""
    Write-Host -ForegroundColor Yellow "  [en] Build English documentation"
    foreach ($lang in $languages) {
        if ($lang.Enabled -and -not $lang.IsPrimary) {
            Write-Host -ForegroundColor Yellow "  [$($lang.Language)] Build $($lang.Name) documentation"
        }
    }
    Write-Host -ForegroundColor Yellow "  [all] Build documentation in all available languages"
    Write-Host -ForegroundColor Yellow "  [r] Run local website"
    Write-Host -ForegroundColor Yellow "  [c] Cancel"
    Write-Host ""

    return Read-Host -Prompt "Your choice"
}

function Ask-IncludeAPI {
    Write-Host ""
    Write-Host -ForegroundColor Cyan "Do you want to include API?"
    Write-Host ""
    Write-Host -ForegroundColor Yellow "  [Y] Yes"
    Write-Host -ForegroundColor Yellow "  [N] No"
    Write-Host ""

    return (Read-Host -Prompt "Your choice (Y/N)").ToLower() -eq "y"
}

function Copy-ExtraItems {
    Copy-Item en/ReleaseNotes/ReleaseNotes.md "$($Settings.SiteDirectory)/en/ReleaseNotes/"
}

function Start-LocalWebsite {
    Write-Host -ForegroundColor Green "Running local website..."
    Write-Host -ForegroundColor Green "Navigate manually to non English website, if you didn't build English documentation."
    Stop-Transcript
    New-Item -ItemType Directory -Verbose -Force -Path $Settings.SiteDirectory | Out-Null
    Set-Location $Settings.SiteDirectory
    Start-Process -FilePath $Settings.HostUrl
    docfx serve
    Set-Location ..
    exit
}

function Generate-APIDoc {
    Write-Host -ForegroundColor Green "Generating API documentation..."

    # Build metadata from C# source, docfx runs dotnet restore
    docfx metadata en/docfx.json

    if ($LastExitCode -ne 0)
    {
        Write-Host -ForegroundColor Red "Failed to generate API metadata"
        exit $LastExitCode
    }
}

function Remove-APIDoc {
    if (Test-Path en/api/.manifest) {
        Write-Host -ForegroundColor Green "Erasing API documentation..."
        Remove-Item en/api/*yml -recurse -Verbose
        Remove-Item en/api/.manifest -Verbose
    }
}

function Build-EnglishDoc {
    Write-Host -ForegroundColor Yellow "Start building English documentation."

    # Output to both build.log and console
    docfx build en\docfx.json

    if ($LastExitCode -ne 0)
    {
        Write-Host -ForegroundColor Red "Failed to build English documentation"
        exit $LastExitCode
    }
}

function Build-NonEnglishDoc {
    param (
        $SelectedLanguage
    )

    if ($SelectedLanguage -and $SelectedLanguage.Language -ne 'en') {

        Write-Host -ForegroundColor Yellow "Start building $($SelectedLanguage.Name) documentation."

        $langFolder = "$($SelectedLanguage.Language)$($Settings.TempDirectory)"

        if(Test-Path $langFolder){
            Remove-Item $langFolder/* -recurse -Verbose
        }
        else{
            New-Item -Path $langFolder -ItemType Directory -Verbose
        }

        # Copy all files from en folder to the selected language folder, this way we can keep en files that are not translated
        Copy-Item en/* -Recurse $langFolder -Force

        # Get all translated files from the selected language folder
        $posts = Get-ChildItem "$langFolder/$($Settings.ManualFolderName)/*.md" -Recurse -Force

        Write-Host "Start write files:"

        # Mark files as not translated if they are not in the toc.md file
        foreach ($post in $posts)
        {
            if($post.ToString().Contains("toc.md")) {
                continue;
            }

            $data = Get-Content $post -Encoding UTF8
            for ($i = 0; $i -lt $data.Length; $i++)
            {
                $line = $data[$i];
                if ($line.length -le 0)
                {
                    Write-Host $post

                    $data[$i]="> [!WARNING]`r`n> " + $SelectedLanguage.NotTranslatedMessage + "`r`n"

                    $data | Out-File -Encoding UTF8 $post

                    break
                }
            }
        }

        Write-Host "End write files"
        $indexFile = $Settings.IndexFileName
        # overwrite en manual page with translated manual page
        if (Test-Path ($SelectedLanguage.Language + "/" + $indexFile)) {
            Copy-Item ($SelectedLanguage.Language + "/" + $indexFile) $langFolder -Force
        }
        else {
            Write-Host -ForegroundColor Yellow "Warning: $($SelectedLanguage.Language)/"+ $indexFile +" not found. English version will be used."
        }

        # overwrite en manual pages with translated manual pages
        if (Test-Path ($SelectedLanguage.Language + "/" + $Settings.ManualFolderName)) {
            Copy-Item ($SelectedLanguage.Language + "/" + $Settings.ManualFolderName) -Recurse -Destination $langFolder -Force
        }
        else {
            Write-Host -ForegroundColor Yellow "Warning: $($SelectedLanguage.Language)/$($Settings.ManualFolderName) not found."
        }

        # we copy the docfx.json file from en folder to the selected language folder, so we can keep the same settings and maitain just one docfx.json file
        Copy-Item en/docfx.json $langFolder -Force
        $SiteDir = $Settings.SiteDirectory
        (Get-Content $langFolder/docfx.json) -replace "$SiteDir/en","$SiteDir/$($SelectedLanguage.Language)" | Set-Content -Encoding UTF8 $langFolder/docfx.json


        docfx build $langFolder\docfx.json

        Remove-Item $langFolder -Recurse -Verbose

        PostProcessing-DocFxDocUrl -SelectedLanguage $SelectedLanguage

        if ($LastExitCode -ne 0)
        {
            Write-Host -ForegroundColor Red "Failed to build $($SelectedLanguage.Name) documentation"
            exit $LastExitCode
        }

        Write-Host -ForegroundColor Green "$($SelectedLanguage.Name) documentation built."
    }
}

function Build-AllLanguagesDocs {
    param (
        [array]$Languages
    )

    foreach ($lang in $Languages) {
        if ($lang.Enabled -and -not $lang.IsPrimary) {

            Build-NonEnglishDoc -SelectedLanguage $lang

        }
    }
}

# docfx generates GitHub link based on the temp _tmp folder, which we need to correct to correct
# GitHub links. This function does that.
function PostProcessing-DocFxDocUrl {
    param (
        $SelectedLanguage
    )

    $posts = Get-ChildItem "$($SelectedLanguage.Language)/*.md" -Recurse -Force

    # Get a list of all HTML files in the _site/<language> directory
    $htmlFiles = Get-ChildItem "$($Settings.SiteDirectory)/$($SelectedLanguage.Language)/*.html" -Recurse

    # Get the relative paths of the posts
    $relativePostPaths = $posts | ForEach-Object { $_.FullName.Replace((Resolve-Path $SelectedLanguage.Language).Path + '\', '') }

    Write-Host -ForegroundColor Yellow "Post-processing docfx:docurl in $($htmlFiles.Count) files..."

    for ($i = 0; $i -lt $htmlFiles.Count; $i++) {
        $htmlFile = $htmlFiles[$i]
        # Get the relative path of the HTML file
        $relativeHtmlPath = $htmlFile.FullName.Replace((Resolve-Path "$($Settings.SiteDirectory)/$($SelectedLanguage.Language)").Path + '\', '').Replace('.html', '.md')

        # Read the content of the HTML file
        $content = Get-Content $htmlFile

        # Define a regex pattern to match the meta tag with name="docfx:docurl"
        $pattern = '(<meta name="docfx:docurl" content=".*?)(/' + $SelectedLanguage.Language + $Settings.TempDirectory+ '/)(.*?">)'

        # Define a regex pattern to match the href attribute in the <a> tags
        $pattern2 = '(<a href=".*?)(/' + $SelectedLanguage.Language + $Settings.TempDirectory + '/)(.*?">)'

        # Check if the HTML file is from the $posts collection
        if ($relativePostPaths -contains $relativeHtmlPath) {
            # Replace /<language>_tmp/ with /<language>/ in the content
            $content = $content -replace $pattern, "`${1}/$($SelectedLanguage.Language)/`${3}"
            $content = $content -replace $pattern2, "`${1}/$($SelectedLanguage.Language)/`${3}"
        } else {
            # Replace /<language>_tmp/ with /en/ in the content
            $content = $content -replace $pattern, '${1}/en/${3}'
            $content = $content -replace $pattern2, '${1}/en/${3}'
        }

        # Write the updated content back to the HTML file
        $content | Set-Content -Encoding UTF8 $htmlFile

        # Check if the script is running in an interactive session before writing progress
        # We don't want to write progress when running in a non-interactive session, such as in a build pipeline
        if ($host.UI.RawUI) {
            Write-Progress -Activity "Processing files" -Status "$i of $($htmlFiles.Count) processed" -PercentComplete (($i / $htmlFiles.Count) * 100)
        }
    }

    Write-Host -ForegroundColor Green "Post-processing completed."
}

# Main script execution starts here

$languages = Read-LanguageConfigurations

Start-Transcript -Path ".\build.log"

if ($BuildAll)
{
    $isAllLanguages = $true
    $API = $true
}
else
{
    $userInput = Get-UserInput

    [bool]$isEnLanguage = $userInput -ieq "en"
    [bool]$isAllLanguages = $userInput -ieq "all"
    [bool]$shouldRunLocalWebsite = $userInput -ieq "r"
    [bool]$isCanceled = $userInput -ieq "c"

    # Check if user input matches any non-English language build
    $selectedLanguage = $languages | Where-Object { $_.Language -eq $userInput -and $_.Enabled -and -not $_.IsPrimary }

    if ($selectedLanguage)
    {
        [bool]$shouldBuildSelectedLanguage = $true
    }

    # Ask if the user wants to include API
    if ($isEnLanguage -or $isAllLanguages -or $shouldBuildSelectedLanguage) {
        $API = Ask-IncludeAPI
    }
}

if ($isCanceled)
{
    Write-Host -ForegroundColor Red "Operation canceled by user."
    Stop-Transcript
    Read-Host -Prompt "Press ENTER key to exit..."
    return
}

if ($shouldRunLocalWebsite)
{
    Start-LocalWebsite
}

# Generate API doc
if ($API)
{
    Generate-APIDoc
}
else
{
    Remove-APIDoc
}

Write-Host -ForegroundColor Green "Generating documentation..."
Write-Host ""
Write-Warning "Note that when building docs without API, you will get UidNotFound warnings and invalid references warnings"
Write-Host ""

if ($isEnLanguage -or $isAllLanguages)
{
   Build-EnglishDoc
}

# Do we need this?
# Copy-ExtraItems

# Build non-English language if selected or build all languages if selected
if ($isAllLanguages) {
    Build-AllLanguagesDocs -Languages $languages
} elseif ($selectedLanguage) {
    Build-NonEnglishDoc -SelectedLanguage $selectedLanguage
}

Stop-Transcript

Read-Host -Prompt "Press any ENTER to exit..."