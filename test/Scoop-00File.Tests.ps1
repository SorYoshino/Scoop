param(
    [String] $TestPath = "$PSScriptRoot\.."
)

BeforeDiscovery {
    $project_file_exclusions = @(
        '[\\/]\.git[\\/]',
        '\.sublime-workspace$',
        '\.DS_Store$',
        'supporting(\\|/)validator(\\|/)packages(\\|/)*'
    )
    $repo_files = Get-ChildItem -Path $TestPath -Recurse -File | Foreach-Object -MemberName FullName |
        Where-Object -FilterScript { $_ -inotmatch $($project_file_exclusions -join '|') }
}

Describe 'Code Syntax' -ForEach @(, $repo_files) -Tag 'File' {
    BeforeAll {
        $files = @(
            $_ | Where-Object -FilterScript { $_ -imatch '\.(ps1|psm1)$' }
        )
        function Test-PowerShellSyntax {
            # ref: http://powershell.org/wp/forums/topic/how-to-check-syntax-of-scripts-automatically @@ https://archive.is/xtSv6
            # originally created by Alexander Petrovskiy & Dave Wyatt
            [CmdletBinding()]
            param (
                [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
                [string[]]
                $Path
            )

            process {
                foreach ($scriptPath in $Path) {
                    $contents = Get-Content -Path $scriptPath

                    if ($null -eq $contents) {
                        continue
                    }

                    $errors = $null
                    $null = [System.Management.Automation.PSParser]::Tokenize($contents, [ref]$errors)

                    New-Object psobject -Property @{
                        Path              = $scriptPath
                        SyntaxErrorsFound = ($errors.Count -gt 0)
                    }
                }
            }
        }

    }

    It 'PowerShell code files do not contain syntax errors' {
        $badFiles = @(
            foreach ($file in $files) {
                if ( (Test-PowerShellSyntax $file).SyntaxErrorsFound ) {
                    $file
                }
            }
        )

        if ($badFiles.Count -gt 0) {
            throw "The following files have syntax errors: `r`n`r`n$($badFiles -join "`r`n")"
        }
    }

}

Describe 'Style constraints for non-binary project files' -ForEach @(, $repo_files) -Tag 'File' {
    BeforeAll {
        $files = @(
            # gather all files except '*.exe', '*.zip', or any .git repository files
            $_ |
                Where-Object { $_ -inotmatch '\.(exe|zip|dll)$' } |
                Where-Object { $_ -inotmatch 'unformatted' }
        )
        $cached_files = @(
            foreach ($file in $files) {
                if (Test-Path -Path $file -PathType Leaf) {
                    [PSCustomObject]@{
                        Path    = $file
                        Content = [System.IO.File]::ReadAllText($file)
                        Lines   = [System.IO.File]::ReadAllLines($file)
                    }
                }
            }
        )
    }

    It 'files do not contain leading UTF-8 BOM' {
        # UTF-8 BOM == 0xEF 0xBB 0xBF
        # see http://www.powershellmagazine.com/2012/12/17/pscxtip-how-to-determine-the-byte-order-mark-of-a-text-file @@ https://archive.is/RgT42
        # ref: http://poshcode.org/2153 @@ https://archive.is/sGnnu
        $badFiles = @(
            foreach ($file_item in $cached_files) {
                if ((Get-Command Get-Content).parameters.ContainsKey('AsByteStream')) {
                    # PowerShell Core (6.0+) '-Encoding byte' is replaced by '-AsByteStream'
                    $bytes = ([char[]](Get-Content $file_item.Path -AsByteStream -TotalCount 3) -join '')
                } else {
                    $bytes = ([char[]](Get-Content $file_item.Path -Encoding byte -TotalCount 3) -join '')
                }
                if ([regex]::match($bytes, '(?ms)^\xEF\xBB\xBF').success) { $file_item.Path }
            }
        )

        if ($badFiles.Count -gt 0) {
            throw "The following files have utf-8 BOM: `r`n`r`n$($badFiles -join "`r`n")"
        }
    }

    It 'files end with a newline' {
        $badFiles = @(
            foreach ($file_item in $cached_files) {
                if ($file_item.Path -match 'TestResults\.xml') { continue }
                if ($file_item.Content.Length -gt 0 -and $file_item.Content[-1] -ne "`n") {
                    $file_item.Path
                }
            }
        )

        if ($badFiles.Count -gt 0) {
            throw "The following files do not end with a newline: `r`n`r`n$($badFiles -join "`r`n")"
        }
    }

    It 'file newlines are CRLF' {
        $badFiles = @(
            foreach ($file_item in $cached_files) {
                if ($file_item.Path -match '[\\/]\.github[\\/]') { continue }
                if ([String]::IsNullOrEmpty($fileItem.Content)) { continue }
                if ([regex]::IsMatch($file_item.Content, '(?<!\r)\n')) {
                    $file_item.Path
                }
            }
        )

        if ($badFiles.Count -gt 0) {
            throw "The following files have non-CRLF line endings: `r`n`r`n$($badFiles -join "`r`n")"
        }
    }

    It 'files have no lines containing trailing whitespace' {
        $badLines = @(
            foreach ($file_item in $cached_files) {
                if ($file_item.Path -match 'TestResults\.xml') { continue }
                for ($i = 0; $i -lt $file_item.Lines.Count; $i++) {
                    if ($file_item.Lines[$i] -match '\s+$') {
                        'File: {0}, Line: {1}' -f $file_item.Path, ($i + 1)
                    }
                }
            }
        )

        if ($badLines.Count -gt 0) {
            throw "The following $($badLines.Count) lines contain trailing whitespace: `r`n`r`n$($badLines -join "`r`n")"
        }
    }

    It 'any leading whitespace consists only of spaces (excepting makefiles)' {
        $badLines = @(
            foreach ($file_item in $cached_files) {
                if ($file_item.Path -inotmatch '(^|.)makefile$') {
                    for ($i = 0; $i -lt $file_item.Lines.Count; $i++) {
                        if ($file_item.Lines[$i] -notmatch '^[ ]*(\S|$)') {
                            'File: {0}, Line: {1}' -f $file_item.Path, ($i + 1)
                        }
                    }
                }
            }
        )

        if ($badLines.Count -gt 0) {
            throw "The following $($badLines.Count) lines contain TABs within leading whitespace: `r`n`r`n$($badLines -join "`r`n")"
        }
    }

}
