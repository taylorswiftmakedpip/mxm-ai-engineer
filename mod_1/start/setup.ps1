# Запуск через setup.cmd. Достаточно встроенного в Windows PowerShell 5.1.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
$PythonVersion = '3.14.10'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LogPath = Join-Path $PSScriptRoot 'setup.log'

function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments, [int[]]$SuccessCodes = @(0))
    & $Command @Arguments | Out-Host
    $code = $LASTEXITCODE
    if ($code -notin $SuccessCodes) {
        throw "Команда $Command завершилась с кодом ошибки $code."
    }
}

function Update-ProcessPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
        [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + $env:Path
}

function Find-Tool {
    param([string]$Name, [string[]]$Candidates)
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) { return $command.Source }
    foreach ($candidate in $Candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Find-CoursePython {
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Python\Python314\python.exe",
        "$env:ProgramFiles\Python314\python.exe"
    )
    foreach ($key in @(
        'HKCU:\Software\Python\PythonCore\3.14\InstallPath',
        'HKLM:\Software\Python\PythonCore\3.14\InstallPath',
        'HKLM:\Software\WOW6432Node\Python\PythonCore\3.14\InstallPath'
    )) {
        if (Test-Path -LiteralPath $key) {
            $installPath = (Get-Item -LiteralPath $key).GetValue('')
            if ($installPath) { $candidates += Join-Path $installPath 'python.exe' }
        }
    }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $version = & $candidate -I -X utf8 -c 'import platform; print(platform.python_version())'
            if ($LASTEXITCODE -eq 0 -and $version -eq $PythonVersion) { return $candidate }
        }
    }
    return $null
}

function Install-Package {
    param([string]$Id, [string[]]$Extra = @())
    # Отсутствие обновления допустимо: после установки проверяем сам инструмент.
    # Остальные ненулевые коды, включая отрицательные, считаем ошибками.
    Invoke-Checked -Command $script:Winget -Arguments (@(
        'install', '--id', $Id, '--exact', '--source', 'winget', '--silent',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
    ) + $Extra) -SuccessCodes @(0, -1978335189)
    Update-ProcessPath
}

$transcribing = $false
try {
    Start-Transcript -LiteralPath $LogPath -Force | Out-Null
    $transcribing = $true
    Set-Location -LiteralPath $ProjectRoot

    Write-Host '[1/6] Проверяем наличие WinGet...'
    $script:Winget = Find-Tool -Name 'winget.exe' -Candidates @(
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
    )
    if (-not $script:Winget) {
        throw 'WinGet не найден. Откройте Microsoft Store, найдите «Установщик приложений» от Microsoft и установите или обновите его. Затем снова запустите setup.cmd.'
    }
    Invoke-Checked -Command $script:Winget -Arguments @('--version')

    Write-Host "[2/6] Проверяем и устанавливаем Python $PythonVersion..."
    $python = Find-CoursePython
    if (-not $python) {
        Install-Package -Id 'Python.Python.3.14' -Extra @(
            '--version', $PythonVersion, '--scope', 'user',
            '--custom', 'InstallAllUsers=0 PrependPath=1 Include_pip=1 Include_launcher=1 InstallLauncherAllUsers=0'
        )
        $python = Find-CoursePython
    }
    if (-not $python) {
        throw "После установки не найден Python $PythonVersion. Подробности — в start/setup.log. Проверьте, не установлен ли уже более новый выпуск Python 3.14."
    }

    Write-Host '[3/6] Проверяем и устанавливаем Git и VS Code...'
    $gitCandidates = @("$env:ProgramFiles\Git\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")
    $git = Find-Tool -Name 'git.exe' -Candidates $gitCandidates
    if (-not $git) {
        Install-Package -Id 'Git.Git' -Extra @('--no-upgrade')
        $git = Find-Tool -Name 'git.exe' -Candidates $gitCandidates
    }
    if (-not $git) { throw 'После установки не найден Git.' }
    Invoke-Checked -Command $git -Arguments @('--version')
    $gitDirectory = Split-Path -Parent $git
    $bashCandidates = @(
        (Join-Path (Split-Path -Parent $gitDirectory) 'bin\bash.exe'),
        (Join-Path (Split-Path -Parent (Split-Path -Parent $gitDirectory)) 'bin\bash.exe'),
        "$env:ProgramFiles\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    $gitBash = $bashCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $gitBash) { throw 'Git найден, но Git Bash отсутствует. Переустановите Git с компонентом Git Bash и повторите запуск.' }
    Invoke-Checked -Command $gitBash -Arguments @('--version')

    $codeCandidates = @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
        "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd"
    )
    $vscode = Find-Tool -Name 'code.cmd' -Candidates $codeCandidates
    if (-not $vscode) {
        Install-Package -Id 'Microsoft.VisualStudioCode' -Extra @('--scope', 'user', '--no-upgrade')
        $vscode = Find-Tool -Name 'code.cmd' -Candidates $codeCandidates
    }
    if (-not $vscode) { throw 'После установки не найден VS Code.' }
    Invoke-Checked -Command $vscode -Arguments @('--version')

    Write-Host '[4/6] Создаём окружение проекта и устанавливаем библиотеки...'
    $venv = Join-Path $ProjectRoot '.venv'
    $venvPython = Join-Path $venv 'Scripts\python.exe'
    $reuse = $false
    if (Test-Path -LiteralPath $venvPython -PathType Leaf) {
        $version = & $venvPython -I -X utf8 -c "import platform, sys; print(platform.python_version() if sys.prefix != sys.base_prefix else 'invalid')"
        $reuse = $LASTEXITCODE -eq 0 -and $version -eq $PythonVersion
    }
    if (-not $reuse) {
        if (Test-Path -LiteralPath $venv) {
            # Сохраняем старое или неисправное окружение перед созданием нового.
            $resolved = (Resolve-Path -LiteralPath $venv).Path
            $expected = [IO.Path]::GetFullPath((Join-Path $ProjectRoot '.venv'))
            if ($resolved -ne $expected -or ((Get-Item -Force -LiteralPath $venv).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw 'Папка .venv является ссылкой или находится вне проекта. Переместите её вручную перед установкой.'
            }
            $backup = Join-Path $ProjectRoot ('.venv.backup-' + [Guid]::NewGuid().ToString('N'))
            Write-Host "Сохраняем старое окружение: $backup"
            Move-Item -LiteralPath $venv -Destination $backup
        }
        Invoke-Checked -Command $python -Arguments @('-I', '-X', 'utf8', '-m', 'venv', $venv)
    }
    Invoke-Checked -Command $venvPython -Arguments @('-I', '-X', 'utf8', '-m', 'pip', '--isolated', '--disable-pip-version-check', 'install', '--index-url', 'https://pypi.org/simple', '--only-binary=:all:', '-r', (Join-Path $PSScriptRoot 'requirements.txt'))

    Write-Host '[5/6] Настраиваем ядро maximum-venv и расширения Python и Jupyter...'
    Invoke-Checked -Command $venvPython -Arguments @('-I', '-X', 'utf8', '-m', 'ipykernel', 'install', '--user', '--name', 'maximum-venv', '--display-name', 'maximum-venv')
    Invoke-Checked -Command $venvPython -Arguments @('-I', '-X', 'utf8', (Join-Path $PSScriptRoot 'configure_notebooks.py'))
    foreach ($extension in @('ms-python.python', 'ms-toolsai.jupyter')) {
        Invoke-Checked -Command $vscode -Arguments @('--install-extension', $extension)
    }
    $extensions = @(& $vscode --list-extensions)
    if ($LASTEXITCODE -ne 0 -or 'ms-python.python' -notin $extensions -or 'ms-toolsai.jupyter' -notin $extensions) {
        throw 'Не удалось подтвердить установку расширений Python и Jupyter для VS Code.'
    }

    Write-Host '[6/6] Проверяем версии, библиотеки и построение графика...'
    Invoke-Checked -Command $venvPython -Arguments @('-I', '-X', 'utf8', '-m', 'pip', '--isolated', 'check')
    Invoke-Checked -Command $venvPython -Arguments @('-I', '-X', 'utf8', (Join-Path $PSScriptRoot 'verify_environment.py'))
    Write-Host ''
    Write-Host 'Установка завершена! Окружение .venv и ядро maximum-venv настроены; ядро указано в метаданных ноутбуков.'
    Write-Host 'ВАЖНО: VS Code запоминает ранее выбранное ядро. Сетап и перезапуск редактора не сбрасывают этот выбор.' -ForegroundColor Yellow
    Write-Host 'Если вверху ноутбука показан Python 3.13.2 или другое старое ядро, нажмите на него и выберите:'
    Write-Host 'Select Another Kernel -> Jupyter Kernels -> maximum-venv'
    Write-Host 'или Python Environments -> .venv (3.14.10) из папки mod_1.'
    Write-Host 'Открываем mod_1 в VS Code.'
    Invoke-Checked -Command $vscode -Arguments @('--new-window', $ProjectRoot)
} catch {
    Write-Host "ОШИБКА: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Журнал установки: $LogPath"
    if ($transcribing) { Stop-Transcript | Out-Null }
    exit 1
}
if ($transcribing) { Stop-Transcript | Out-Null }
exit 0
