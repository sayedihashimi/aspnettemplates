$env:IsDeveloperMachine=$true
function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}
$scriptdir = (Get-ScriptDirectory)

$config = New-Object -TypeName psobject -Property @{
    RootPath = (Join-Path $scriptdir 'samples')
    TargetPath = ('C:\temp\templates-temp\samples')
    Basebranch = 'master'
    InitialCommitId = 'cf2cb2d2cfe02a44c5af1303d939b87b444a2c3f'
}

<#
.SYNOPSIS
    This will download and import nuget-powershell (https://github.com/ligershark/nuget-powershell),
    which is a PowerShell utility that can be used to easily download nuget packages.

    If nuget-powershell is already loaded then the download/import will be skipped.

.PARAMETER nugetPsMinModVersion
    The minimum version to import
#>
function InternalImport-NuGetPowershell{
    [cmdletbinding()]
    param(
        $nugetPsMinModVersion = '0.2.1.1'
    )
    process{
        # see if nuget-powershell is available and load if not
        $nugetpsloaded = $false
        if((get-command Get-NuGetPackage -ErrorAction SilentlyContinue)){
            # check the module to ensure we have the correct version

            $currentversion = (Get-Module -Name nuget-powershell).Version
            if( ($currentversion -ne $null) -and ($currentversion.CompareTo([version]::Parse($nugetPsMinModVersion)) -ge 0 )){
                $nugetpsloaded = $true
            }
        }

        if(!$nugetpsloaded){
            (new-object Net.WebClient).DownloadString("https://raw.githubusercontent.com/ligershark/nuget-powershell/master/get-nugetps.ps1") | iex
        }

        # check to see that it was loaded
        if((get-command Get-NuGetPackage -ErrorAction SilentlyContinue)){
            $nugetpsloaded = $true
        }

        if(-not $nugetpsloaded){
            throw ('Unable to load nuget-powershell, unknown error')
        }
    }
}

function Find-Guids{
    [cmdletbinding()]
    param(
        [string]$rootPath = ($pwd)
    )
    process{
        Get-ChildItem $rootPath *.*proj -Recurse -File|
            Select-Object -ExpandProperty fullname -Unique | 
            ForEach-Object { 
                ([xml](Get-Content $_)).Project.PropertyGroup.ProjectGuid | 
                    Select-Object -Unique | 
                    ForEach-Object { 
                        $_.Replace('{','').Replace('}','') 
                    }
            }
    }
}

function Find-Fwlinks{
    [cmdletbinding()]
    param(
        [string]$rootPath = ($pwd)
    )
    process{
        $pattern='http\:\/\/go.microsoft.com\/fwlink.*=[0-9]*'

        $fwlinks = @()
        $paths = @()
        $result = @()

        Get-ChildItem $rootPath *.* -Recurse -File | select-string $pattern  | % {
            try{
                $mresult = [regex]::Match($_,$pattern).Captures.Groups[0].Value
                if(-not ([string]::IsNullOrEmpty($mresult))){
                    $fwlinks += $mresult
                    $paths += $_.Path
                }
            }
            catch{}

            # return unique results
            # $fwlinks | Select-Object -Unique
        }

        $paths = ($paths | Select-Object -Unique)
        $extensions = ($paths|%{ (Get-Item $_).Extension}) | Select-Object -Unique

        New-Object -TypeName psobject -Property @{
            FWLinks = ($fwlinks | Select-Object -Unique)
            FileExtensions = $extensions 
        }
    }
}

function Normalize-Guids{
    [cmdletbinding()]
    param(
        $newGuid = [guid]::Empty,

        $rootPath = ($pwd)
    )
    process{
        $allguids = Find-Guids -rootPath $rootPath
        $replacements = @{}
        foreach($guid in $allguids){
            $replacements[$guid]=$newGuid
        }

        Replace-TextInFolder -folder $rootPath -replacements $replacements -exclude .git -include *.*proj
    }
}

function Normalize-DevServerPort{
    [cmdletbinding()]
    param(
        [string]$newport = 1000,
        [string]$rootPath = ($pwd)
    )
    process{
        $replacements = @{}
        Get-ChildItem $rootPath *.*proj -Recurse -File |
            Select-Object -ExpandProperty fullname -Unique | 
            ForEach-Object { 
                [string]$port = $null
                try{
                    $port = ([xml](Get-Content $_)).Project.ProjectExtensions.VisualStudio.FlavorProperties.WebProjectProperties.DevelopmentServerPort
                }
                catch{}
                if(-not ([string]::IsNullOrEmpty($port))){
                    $replacements[$port] = $newport
                }
            }

        Replace-TextInFolder -folder $rootPath -replacements $replacements -exclude .git -include *.*proj        
    }
}

function Remove-UniqueText{
    [cmdletbinding()]
    param(
        [string]$rootPath = ($pwd),
        [string]$exclude = '.git'
    )
    process{
        $fwlinkresult = Find-Fwlinks

        if( ($fwlinkresult -eq $null ) -or
            ($fwlinkresult.FWLinks -eq $null) -or
            ($fwlinkresult.FWLinks.Length -le 0) ){

            return
        } 

        $fwlinks = ($fwlinkresult.FWLinks)
        [string]$include = ''
        $fwlinkresult.FileExtensions | % { $include += ('*{0};' -f $_) }

        $include = $include.TrimEnd(';')

        $replacements = @{}
        foreach($fwlink in $fwlinks){
            $replacements[$fwlink]='fwlink'
        }

        # todo improve by finding fwlink extension:Get-ChildItem .\samples\ *.* -Recurse -File | select-string $pattern | %{ (Get-Item $_.path).Extension}|Select-Object -Unique
        Replace-TextInFolder -folder $rootPath -replacements $replacements -include $include -exclude $exclude
    }
}

function EnsureFileReplacerInstlled{
    [cmdletbinding()]
    param()
    process{
        if(-not (Get-Command -Module file-replacer -Name Replace-TextInFolder -errorAction SilentlyContinue)){
            $fpinstallpath = (Get-NuGetPackage -name file-replacer -version '0.4.0-beta' -binpath)
            if(-not (Test-Path $fpinstallpath)){ throw ('file-replacer folder not found at [{0}]' -f $fpinstallpath) }
            Import-Module (Join-Path $fpinstallpath 'file-replacer.psm1') -DisableNameChecking
        }

        # make sure it's loaded and throw if not
        if(-not (Get-Command -Module file-replacer -Name Replace-TextInFolder -errorAction SilentlyContinue)){
            throw ('Unable to install/load file-replacer')
        }
    }
}
function EnsurePecanWaffleLoaded{
    [cmdletbinding()]
    param(
        [string]$pkgname = 'pecan-waffle',
        [string]$pkgversion = '0.0.22-beta'
    )
    process{
        $binpath = (Get-NuGetPackage -name $pkgname -version $pkgversion -binpath)
        $modpath = (Join-Path $binpath 'pecan-waffle.psm1')
        if(-not (Test-Path $modpath)){
            throw ('pecan-waffle module not found at {0}' -f $modpath)
        }
        Import-Module $modpath -Global -DisableNameChecking
    }
}

# this will clean it of guids/fwlinks/etc
function Prepare-SourceDirectory{
    [cmdletbinding()]
    param()
    process{
    }
}

function CopyFiles{
    [cmdletbinding()]
    param(
        [string]$sourcePath,
        [string]$destPath
    )
    process{
        Copy-ItemRobocopy -sourcePath $sourcePath -destPath $destPath
    }
}

InternalImport-NuGetPowershell
EnsurePecanWaffleLoaded

try{
    Push-Location
    Set-Location ($config.TargetPath) -ErrorAction Stop

    Prepare-SourceDirectory

    # switch to the correct branch
    git checkout ($config.Basebranch) | Write-Output
    # remove any untracked files
    git clean -f
    
    # delete the noauth local branch
    git branch -D noauth
    git checkout -b noauth
    CopyFiles -sourcePath 'C:\data\mycode\aspnettemplates-all\samples\MvcNoAuth' -destPath ($config.TargetPath)
    git add . --all
    git commit -m 'noauth initial'
    
    [string]$noauthcommitid = (git log -1 --format="%H")
    
    CopyFiles -sourcePath 'C:\data\mycode\aspnettemplates-all\samples\MvcIndAuth' -destPath ($config.TargetPath)
    git add . --all
    git commit -m 'indauth'
}
finally{
    Pop-Location
}

#### mvcnoauth branch
# switch to master branch
# checkout initial commit
# create base commit of no auth
# delete files in target dir
# copy files from ind auth on top
# create a new commit
#
# go back to no auth commit
# delete files in target dir
# copy files from win auth on top of no auth
# 1.1 no auth
# 1.2 ind auth
# 2.1 no auth
# 2.2 ind auth
# 3.1 no auth
# 3.2 win auth

#EnsureFileReplacerInstlled
#Normalize-Guids -rootPath "$pwd\samples"
#Normalize-DevServerPort -rootPath "$pwd\samples"
#Remove-UniqueText -rootPath "$pwd\samples"