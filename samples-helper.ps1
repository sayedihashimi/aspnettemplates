
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
        $result = @()

        Get-ChildItem $rootPath *.* -Recurse -File | select-string $pattern  | % {
            try{
                $mresult = [regex]::Match($_,$pattern).Captures.Groups[0].Value
                if(-not ([string]::IsNullOrEmpty($mresult))){
                    $fwlinks += $mresult
                }
            }
            catch{}

            # return unique results
            $fwlinks | Select-Object -Unique
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
        [string]$include = '*.*',
        [string]$exclude = '.git'
    )
    process{
        $fwlinks = Find-Fwlinks
        $replacements = @{}
        foreach($fwlink in $fwlinks){
            $replacements[$fwlink]='fwlink'
        }

        # todo improve by finding fwlink extension:Get-ChildItem .\samples\ *.* -Recurse -File | select-string $pattern | %{ (Get-Item $_.path).Exists}|Select-Object -Unique
        Replace-TextInFolder -folder $rootPath -replacements $replacements -include $include -exclude $exclude
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
#Normalize-Guids
#Normalize-DevServerPort
Remove-UniqueText -rootPath "$pwd\samples"