param(
    [Parameter(Mandatory=$true)][string]$TargetDir,
    [Parameter(Mandatory=$true)][string]$Task,
    [int]$MaxRounds = 8
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$stateDir  = Join-Path $TargetDir ".agent-loop\task-$timestamp"
New-Item -ItemType Directory -Force -Path "$stateDir\log" | Out-Null
$Task | Out-File -Encoding utf8 "$stateDir\current-task.md"
$activityLog = "$stateDir\activity.log"

function Write-Status {
    param([string]$Agent, [string]$Action, [string]$Color = "White")
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] [$Agent] $Action"
    Write-Host $line -ForegroundColor $Color
    $line | Out-File -Append -Encoding utf8 $activityLog
}

# ใช้ stdin pipe แทน argument -- แก้ปัญหา Claude error
function Invoke-ClaudeCli {
    param([string]$Prompt, [string]$LogFile)
    Write-Status -Agent "CLAUDE" -Action "STARTED" -Color Yellow
    $prevPref = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    $Prompt | & claude -p `
        --allowedTools "Read,Write" `
        --permission-mode acceptEdits 2>&1 | 
        Out-File -Encoding utf8 $LogFile

    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevPref
    Write-Status -Agent "CLAUDE" -Action "FINISHED (exit code $exitCode)" -Color Yellow
    return $exitCode
}


# AGY: ปิด streaming ผ่าน ForEach-Object ชั่วคราว ใช้ redirect ธรรมดาแทน กัน TTY-detection bug
function Invoke-AgyCli {
    param([string]$Prompt, [string]$LogFile)
    Write-Status -Agent "AGY" -Action "STARTED" -Color Green
    $prevPref = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    # เขียน output ตรงไปไฟล์ (redirect) แทนการ pipe ผ่าน ForEach-Object
    # เพื่อลดโอกาสที่ agy จะ detect ผิดว่าเป็น interactive TTY
    & agy --print $Prompt --dangerously-skip-permissions --print-timeout 10m *> $LogFile

    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevPref
    Write-Status -Agent "AGY" -Action "FINISHED (exit code $exitCode)" -Color Green
    return $exitCode
}

function Invoke-CodexCli {
    param([string]$Prompt, [string]$LogFile)
    Write-Status -Agent "CODEX" -Action "STARTED" -Color Magenta
    $prevPref = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    & codex exec --sandbox workspace-write $Prompt *> $LogFile

    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevPref
    Write-Status -Agent "CODEX" -Action "FINISHED (exit code $exitCode)" -Color Magenta
    return $exitCode
}

Write-Status -Agent "LOOP" -Action "Task: $Task | TargetDir: $TargetDir | MaxRounds: $MaxRounds" -Color Cyan

Push-Location $TargetDir
try {
    for ($round = 1; $round -le $MaxRounds; $round++) {
        Write-Status -Agent "LOOP" -Action "=== Round $round START ===" -Color Cyan

        git diff | Out-File -Encoding utf8 "$stateDir\current-diff.txt"

        $claudePrompt = "Task: $Task. Review only. Read $stateDir\current-diff.txt and $stateDir\qa-report.md if present. Write findings with severity to $stateDir\review.md. Do not edit source files."
        Invoke-ClaudeCli -Prompt $claudePrompt -LogFile "$stateDir\log\claude-round-$round.log" | Out-Null

        $agyPrompt = "Read $stateDir\review.md and fix issues in source code, staying in scope of task: $Task. Do not run git commit."
        Invoke-AgyCli -Prompt $agyPrompt -LogFile "$stateDir\log\agy-round-$round.log" | Out-Null

        $codexPrompt = "QA/pentest the latest code changes against task: $Task. Write $stateDir\qa-report.md starting with 'STATUS: PASS' or 'STATUS: FAIL'."
        $codexExit = Invoke-CodexCli -Prompt $codexPrompt -LogFile "$stateDir\log\codex-round-$round.log"

        if ($codexExit -ne 0) {
            Write-Status -Agent "LOOP" -Action "codex exit code $codexExit - checking qa-report.md anyway" -Color Yellow
        }

        $status = Get-Content "$stateDir\qa-report.md" -TotalCount 1 -Encoding utf8 -ErrorAction SilentlyContinue
        Write-Status -Agent "LOOP" -Action "Round $round result: $status" -Color Cyan

        if ($status -like "STATUS: PASS*") {
            git add -A
            git commit -m "feat: $Task (passed in $round rounds)"
            Write-Status -Agent "LOOP" -Action "DONE - passed in $round rounds (committed final changes)" -Color Green
            exit 0
        }
    }
    Write-Status -Agent "LOOP" -Action "MAX ROUNDS REACHED ($MaxRounds) - needs human review" -Color Yellow
    exit 1
}
finally {
    Pop-Location
}