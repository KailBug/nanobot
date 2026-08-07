[CmdletBinding()]
param(
    [string]$MainBranch = "main",
    [string]$StudyBranch = "study/message-flow",
    [string]$UpstreamRemote = "upstream",
    [string]$OriginRemote = "origin"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$GitArgs
    )

    Write-Host "> git $($GitArgs -join ' ')" -ForegroundColor Cyan
    & git @GitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed with exit code ${LASTEXITCODE}: git $($GitArgs -join ' ')"
    }
}

function Invoke-GitCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$GitArgs
    )

    $Output = & git @GitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed with exit code ${LASTEXITCODE}: git $($GitArgs -join ' ')"
    }
    return ($Output | Out-String).Trim()
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git was not found in PATH."
}

$OriginalLocation = (Get-Location).Path

try {
    $RepoRoot = Invoke-GitCapture -GitArgs @("rev-parse", "--show-toplevel")
    Set-Location -LiteralPath $RepoRoot

    # Untracked helper files are safe to leave in place; Git itself will stop a
    # branch switch if one would be overwritten. Tracked changes must be clean.
    $DirtyFiles = Invoke-GitCapture -GitArgs @(
        "status",
        "--porcelain",
        "--untracked-files=no"
    )
    if ($DirtyFiles) {
        throw @"
The working tree has uncommitted changes. Commit or stash them before syncing:
$DirtyFiles
"@
    }

    # Fail before changing branches if the expected repository layout is absent.
    Invoke-Git -GitArgs @("show-ref", "--verify", "--quiet", "refs/heads/$MainBranch")
    Invoke-Git -GitArgs @("show-ref", "--verify", "--quiet", "refs/heads/$StudyBranch")
    Invoke-Git -GitArgs @("remote", "get-url", $UpstreamRemote)
    Invoke-Git -GitArgs @("remote", "get-url", $OriginRemote)

    Invoke-Git -GitArgs @("switch", $MainBranch)
    Invoke-Git -GitArgs @("fetch", $UpstreamRemote)
    Invoke-Git -GitArgs @("merge", "$UpstreamRemote/$MainBranch")
    Invoke-Git -GitArgs @("push", $OriginRemote, $MainBranch)

    Invoke-Git -GitArgs @("switch", $StudyBranch)
    Invoke-Git -GitArgs @("rebase", $MainBranch)
    Invoke-Git -GitArgs @(
        "push",
        "--force-with-lease",
        $OriginRemote,
        $StudyBranch
    )

    Write-Host "Repository update completed successfully." -ForegroundColor Green
    Write-Host "Current branch: $StudyBranch"
}
finally {
    Set-Location -LiteralPath $OriginalLocation
}
