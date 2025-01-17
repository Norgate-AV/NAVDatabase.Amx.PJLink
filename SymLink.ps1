#!/usr/bin/env pwsh
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
    [ValidateNotNullOrEmpty()]
    [string]
    $ModulePath = "C:\Program Files (x86)\Common Files\AMXShare\Duet\module",

    [Parameter(Mandatory = $false)]
    [string]
    $IncludePath = "C:\Program Files (x86)\Common Files\AMXShare\AXIs",

    [Parameter(Mandatory = $false)]
    [switch]
    $Delete = $false
)

$prevPWD = $PWD
Set-Location $PSScriptRoot

try {
    $directories = Get-ChildItem -Directory -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch "(\.\w+|node_modules|dist)" }

    # Needed for scoop as all files with be in the root directory
    $directories += $PWD

    $moduleFiles = $directories | Get-ChildItem -Filter "*.axs"
    $includeFiles = $directories | Get-ChildItem -Filter "*.axi"

    if (!$moduleFiles) {
        Write-Host "No module files found"
        exit 1
    }

    # Ensure there is a compiled TKO file for each AXS file
    foreach ($file in $moduleFiles) {
        if (!(Test-Path $($file.FullName -replace ".axs", ".tko"))) {
            Write-Host "TKO file not found for $file" -ForegroundColor Yellow
            exit 1
        }
    }

    $ModulePath = Resolve-Path $ModulePath
    $IncludePath = Resolve-Path $IncludePath

    !$Delete ? (Write-Host "Creating symlinks...") : (Write-Host "Deleting symlinks...")

    # It's possible to have a module without any AXI files
    if ($includeFiles) {
        foreach ($file in $includeFiles) {
            $path = "$IncludePath\$($file.Name)"

            if ($Delete) {
                Write-Verbose "Deleting symlink: $path"
                Remove-Item -Path $path -Force | Out-Null
                continue
            }

            $target = $file.FullName

            Write-Verbose "Creating symlink: $path -> $target"
            New-Item -ItemType SymbolicLink -Path $path -Target $target -Force | Out-Null
        }
    }

    foreach ($file in $moduleFiles) {
        $axsPath = "$ModulePath\$($file.Name)"
        $tkoPath = "$ModulePath\$($file.Name -replace ".axs", ".tko")"

        $axsTarget = $file.FullName
        $tkoTarget = $file.FullName -replace ".axs", ".tko"

        if ($Delete) {
            Write-Verbose "Deleting symlink: $axsPath"
            Remove-Item -Path $axsPath -Force | Out-Null

            Write-Verbose "Deleting symlink: $tkoPath"
            Remove-Item -Path $tkoPath -Force | Out-Null

            continue
        }

        Write-Verbose "Creating symlink: $axsPath -> $axsTarget"
        New-Item -ItemType SymbolicLink -Path $axsPath -Target $axsTarget -Force | Out-Null

        Write-Verbose "Creating symlink: $tkoPath -> $tkoTarget"
        New-Item -ItemType SymbolicLink -Path $tkoPath -Target $tkoTarget -Force | Out-Null
    }
}
catch {
    Write-Host $_.Exception.GetBaseException().Message -ForegroundColor Red
    exit 1
}
finally {
    Set-Location $prevPWD
}
