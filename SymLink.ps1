#Requires -RunAsAdministrator

<#
 _   _                       _          ___     __
| \ | | ___  _ __ __ _  __ _| |_ ___   / \ \   / /
|  \| |/ _ \| '__/ _` |/ _` | __/ _ \ / _ \ \ / /
| |\  | (_) | | | (_| | (_| | ||  __// ___ \ V /
|_| \_|\___/|_|  \__, |\__,_|\__\___/_/   \_\_/
                 |___/

MIT License

Copyright (c) 2023 Norgate AV Services Limited

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#>

[CmdletBinding()]

param (
    [Parameter(Mandatory = $false)]
    [string]
    $Path = ".",

    [Parameter(Mandatory = $false)]
    [string]
    $ModulePath = "C:\Program Files (x86)\Common Files\AMXShare\Duet\module",

    [Parameter(Mandatory = $false)]
    [string]
    $IncludePath = "C:\Program Files (x86)\Common Files\AMXShare\AXIs"
)

try {
    $Path = Resolve-Path $Path

    $directories = Get-ChildItem -Path $Path -Directory -Recurse | Where-Object { $_.FullName -notmatch "(.git|.history|node_modules)" }

    $moduleFiles = $directories | Get-ChildItem -File -Include *.axs -ErrorAction SilentlyContinue
    $includeFiles = $directories | Get-ChildItem -File -Include *.axi -ErrorAction SilentlyContinue

    if (!$moduleFiles -and !$includeFiles) {
        Write-Host "No files found in $Path" -ForegroundColor Yellow
        exit
    }

    foreach ($file in $includeFiles) {
        $path = Join-Path -Path $IncludePath -ChildPath $file.Name
        $target = $file.FullName

        Write-Host "Creating symlink: $path -> $target" -ForegroundColor Green
        New-Item -ItemType SymbolicLink -Path $path -Target $target -Force | Out-Null
    }

    foreach ($file in $moduleFiles) {
        if (!(Test-Path $($file.FullName -replace ".axs", ".tko"))) {
            Write-Host "TKO file not found for $file" -ForegroundColor Yellow
            continue
        }

        $path = Join-Path -Path $ModulePath -ChildPath $file.Name
        $target = $file.FullName

        Write-Host "Creating symlink: $path -> $target" -ForegroundColor Green
        New-Item -ItemType SymbolicLink -Path $path -Target $target -Force | Out-Null

        $path = Join-Path -Path $ModulePath -ChildPath $($file.Name -replace ".axs", ".tko")
        $target = $file.FullName -replace ".axs", ".tko"

        Write-Host "Creating symlink: $path -> $target" -ForegroundColor Green
        New-Item -ItemType SymbolicLink -Path $path -Target $target -Force | Out-Null
    }
}
catch {
    Write-Host $_.Exception.GetBaseException().Message -ForegroundColor Red
    exit 1
}

Write-Host
Read-Host -Prompt "Press any key to exit..."
