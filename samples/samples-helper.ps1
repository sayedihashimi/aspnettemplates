
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

        Replace-TextInFolder -folder $rootPath -replacements $replacements -exclude .git
    }
}

function EnsureFileReplacerInstlled{
    [cmdletbinding()]
    param()
    begin{
        Import-NuGetPowershell
    }
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

function InternalEnsure-DirectoryExists{
    param([Parameter(Position=0)][System.IO.DirectoryInfo]$path)
    process{
        if($path -ne $null){
            if(-not (Test-Path $path.FullName)){
                New-Item -Path $path.FullName -ItemType Directory
            }
        }
    }
}

EnsureFileReplacerInstlled
Normalize-Guids