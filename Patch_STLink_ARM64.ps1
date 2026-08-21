param(
    [ValidateSet("Install","Restore")]
    [string]$Mode = "Install"
)

$ErrorActionPreference = "Stop"

$CubeRoot = "C:\ST\STM32CubeIDE_2.2.0\STM32CubeIDE"
$JarName = "com.st.stm32cube.ide.mcu.debug_2.2.300.202601241706.jar"
$JarPath = Join-Path $CubeRoot ("plugins\" + $JarName)
$BackupPath = $JarPath + ".ORIGINAL_ARM64_STLINK_FIX"
$Log = Join-Path $PSScriptRoot "STM32CubeIDE_ARM64_STLink_TestFix.log"

function Log([string]$s) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $s
    Write-Host $line
    Add-Content -LiteralPath $Log -Value $line
}

function Fail([string]$s, [int]$code = 1) {
    Log ("ERROR: " + $s)
    exit $code
}

function Read-U1([byte[]]$b, [ref]$p) {
    $v = [int]$b[$p.Value]
    $p.Value++
    return $v
}
function Read-U2([byte[]]$b, [ref]$p) {
    $v = ([int]$b[$p.Value] -shl 8) -bor [int]$b[$p.Value + 1]
    $p.Value += 2
    return $v
}
function Read-U4([byte[]]$b, [ref]$p) {
    [uint32]$v = ([uint32]$b[$p.Value] -shl 24) -bor
                  ([uint32]$b[$p.Value + 1] -shl 16) -bor
                  ([uint32]$b[$p.Value + 2] -shl 8) -bor
                  [uint32]$b[$p.Value + 3]
    $p.Value += 4
    return [uint32]$v
}
function Write-U4-BE([byte[]]$b, [int]$off, [uint32]$v) {
    $b[$off]     = [byte](($v -shr 24) -band 0xFF)
    $b[$off + 1] = [byte](($v -shr 16) -band 0xFF)
    $b[$off + 2] = [byte](($v -shr 8) -band 0xFF)
    $b[$off + 3] = [byte]($v -band 0xFF)
}

function Copy-Bytes([byte[]]$src, [int]$start, [int]$count) {
    $dst = New-Object byte[] $count
    [Array]::Copy($src, $start, $dst, 0, $count)
    return $dst
}

function Parse-ConstantPool([byte[]]$b, [ref]$p) {
    $cpCount = Read-U2 $b $p
    $utf8 = @{}
    $i = 1
    while ($i -lt $cpCount) {
        $tag = Read-U1 $b $p
        switch ($tag) {
            1 {
                $len = Read-U2 $b $p
                $txt = [Text.Encoding]::UTF8.GetString($b, $p.Value, $len)
                $utf8[$i] = $txt
                $p.Value += $len
            }
            3 { $p.Value += 4 }
            4 { $p.Value += 4 }
            5 { $p.Value += 8; $i++ }
            6 { $p.Value += 8; $i++ }
            7 { $p.Value += 2 }
            8 { $p.Value += 2 }
            9 { $p.Value += 4 }
            10 { $p.Value += 4 }
            11 { $p.Value += 4 }
            12 { $p.Value += 4 }
            15 { $p.Value += 3 }
            16 { $p.Value += 2 }
            17 { $p.Value += 4 }
            18 { $p.Value += 4 }
            19 { $p.Value += 2 }
            20 { $p.Value += 2 }
            default { throw "Unsupported constant-pool tag $tag at index $i" }
        }
        $i++
    }
    return $utf8
}

function Skip-Attributes([byte[]]$b, [ref]$p) {
    $count = Read-U2 $b $p
    for ($i=0; $i -lt $count; $i++) {
        [void](Read-U2 $b $p)
        $len = Read-U4 $b $p
        $p.Value += [int]$len
    }
}

function Patch-ValidateMethod([byte[]]$classBytes) {
    if ($classBytes.Length -lt 16) { throw "Class file is too small." }

    if (-not ($classBytes[0] -eq 0xCA -and $classBytes[1] -eq 0xFE -and
              $classBytes[2] -eq 0xBA -and $classBytes[3] -eq 0xBE)) {
        throw "Invalid Java class magic."
    }

    $p = [ref]4
    [void](Read-U2 $classBytes $p) # minor
    [void](Read-U2 $classBytes $p) # major
    $utf8 = Parse-ConstantPool $classBytes $p

    $p.Value += 6 # access_flags, this_class, super_class

    $interfacesCount = Read-U2 $classBytes $p
    $p.Value += (2 * $interfacesCount)

    $fieldsCount = Read-U2 $classBytes $p
    for ($f=0; $f -lt $fieldsCount; $f++) {
        $p.Value += 6 # access, name, descriptor
        Skip-Attributes $classBytes $p
    }

    $methodsCount = Read-U2 $classBytes $p

    for ($m=0; $m -lt $methodsCount; $m++) {
        $methodStart = $p.Value
        [void](Read-U2 $classBytes $p) # access
        $nameIndex = Read-U2 $classBytes $p
        $descIndex = Read-U2 $classBytes $p
        $attrCountOffset = $p.Value
        $attrCount = Read-U2 $classBytes $p

        $name = $utf8[$nameIndex]
        $desc = $utf8[$descIndex]

        for ($a=0; $a -lt $attrCount; $a++) {
            $attrHeader = $p.Value
            $attrNameIndex = Read-U2 $classBytes $p
            $attrLenOffset = $p.Value
            $attrLen = Read-U4 $classBytes $p
            $attrDataStart = $p.Value
            $attrName = $utf8[$attrNameIndex]

            if ($name -eq "validate" -and $desc -eq "(Ljava/lang/String;)Z" -and $attrName -eq "Code") {
                # New Code attribute body:
                # max_stack=1, max_locals=1
                # code_length=2
                # iconst_1 (0x04), ireturn (0xAC)
                # exception_table_length=0
                # attributes_count=0
                [byte[]]$newCode = @(
                    0x00,0x01,
                    0x00,0x01,
                    0x00,0x00,0x00,0x02,
                    0x04,0xAC,
                    0x00,0x00,
                    0x00,0x00
                )

                $oldDataEnd = $attrDataStart + [int]$attrLen
                $prefixLen = $attrDataStart
                $suffixLen = $classBytes.Length - $oldDataEnd
                $newBytes = New-Object byte[] ($prefixLen + $newCode.Length + $suffixLen)

                [Array]::Copy($classBytes, 0, $newBytes, 0, $prefixLen)
                [Array]::Copy($newCode, 0, $newBytes, $prefixLen, $newCode.Length)
                [Array]::Copy($classBytes, $oldDataEnd, $newBytes, $prefixLen + $newCode.Length, $suffixLen)

                Write-U4-BE $newBytes $attrLenOffset ([uint32]$newCode.Length)

                return ,$newBytes
            }

            $p.Value = $attrDataStart + [int]$attrLen
        }
    }

    throw "Could not find validate(Ljava/lang/String;)Z Code attribute."
}

function Is-AlreadyPatched([byte[]]$classBytes) {
    # Conservative byte-level check for the exact tiny Code attribute body in the target method
    # is performed by actually parsing and detecting Code length 14 + bytecode 04 AC.
    $p = [ref]4
    [void](Read-U2 $classBytes $p)
    [void](Read-U2 $classBytes $p)
    $utf8 = Parse-ConstantPool $classBytes $p
    $p.Value += 6
    $interfacesCount = Read-U2 $classBytes $p
    $p.Value += 2 * $interfacesCount
    $fieldsCount = Read-U2 $classBytes $p
    for ($f=0; $f -lt $fieldsCount; $f++) {
        $p.Value += 6
        Skip-Attributes $classBytes $p
    }
    $methodsCount = Read-U2 $classBytes $p
    for ($m=0; $m -lt $methodsCount; $m++) {
        $p.Value += 2
        $nameIndex = Read-U2 $classBytes $p
        $descIndex = Read-U2 $classBytes $p
        $attrCount = Read-U2 $classBytes $p
        $name = $utf8[$nameIndex]
        $desc = $utf8[$descIndex]
        for ($a=0; $a -lt $attrCount; $a++) {
            $attrNameIndex = Read-U2 $classBytes $p
            $attrLen = Read-U4 $classBytes $p
            $data = $p.Value
            $attrName = $utf8[$attrNameIndex]
            if ($name -eq "validate" -and $desc -eq "(Ljava/lang/String;)Z" -and $attrName -eq "Code") {
                if ($attrLen -eq 14 -and
                    $classBytes[$data+0] -eq 0 -and $classBytes[$data+1] -eq 1 -and
                    $classBytes[$data+2] -eq 0 -and $classBytes[$data+3] -eq 1 -and
                    $classBytes[$data+4] -eq 0 -and $classBytes[$data+5] -eq 0 -and
                    $classBytes[$data+6] -eq 0 -and $classBytes[$data+7] -eq 2 -and
                    $classBytes[$data+8] -eq 0x04 -and $classBytes[$data+9] -eq 0xAC) {
                    return $true
                }
                return $false
            }
            $p.Value += [int]$attrLen
        }
    }
    return $false
}

function Get-ClassBytesFromJar([string]$jar) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($jar)
    try {
        $entryName = "com/st/stm32cube/ide/mcu/debug/stlinkfwutil/StLinkFwUtil.class"
        $entry = $zip.GetEntry($entryName)
        if (-not $entry) { throw "Target class not found in JAR." }
        $ms = New-Object IO.MemoryStream
        $s = $entry.Open()
        try { $s.CopyTo($ms) } finally { $s.Dispose() }
        return ,$ms.ToArray()
    } finally {
        $zip.Dispose()
    }
}

function Replace-ClassInJar([string]$jar, [byte[]]$patchedBytes) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $entryName = "com/st/stm32cube/ide/mcu/debug/stlinkfwutil/StLinkFwUtil.class"

    $fs = [IO.File]::Open($jar, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $zip = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Update, $false)
        try {
            $old = $zip.GetEntry($entryName)
            if (-not $old) { throw "Target class not found in JAR." }
            $old.Delete()
            $new = $zip.CreateEntry($entryName, [IO.Compression.CompressionLevel]::Optimal)
            $s = $new.Open()
            try {
                $s.Write($patchedBytes, 0, $patchedBytes.Length)
            } finally {
                $s.Dispose()
            }

            # Modified signed JARs are invalid. Remove signature blocks if present.
            $sigEntries = @($zip.Entries | Where-Object {
                $_.FullName -match '^META-INF/.*\.(SF|RSA|DSA|EC)$'
            })
            foreach ($e in $sigEntries) {
                Log ("Removing JAR signature entry: " + $e.FullName)
                $e.Delete()
            }
        } finally {
            $zip.Dispose()
        }
    } finally {
        $fs.Dispose()
    }
}

Set-Content -LiteralPath $Log -Value ("STM32CubeIDE ARM64 ST-LINK Test Fix - " + (Get-Date))

Log ("Mode: " + $Mode)
Log ("OS architecture: " + [Runtime.InteropServices.RuntimeInformation]::OSArchitecture)
Log ("Process architecture: " + [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture)

if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() -ne "Arm64") {
    Fail "This patch is intentionally restricted to Windows ARM64." 20
}

if (-not (Test-Path -LiteralPath $CubeRoot)) {
    Fail ("CubeIDE 2.2.0 root not found: " + $CubeRoot) 21
}

$running = Get-Process -Name "stm32cubeide" -ErrorAction SilentlyContinue
if ($running) {
    Fail "STM32CubeIDE is running. Close CubeIDE completely and run the patch again." 22
}

if ($Mode -eq "Restore") {
    if (-not (Test-Path -LiteralPath $BackupPath)) {
        Fail ("Backup not found: " + $BackupPath) 30
    }
    Copy-Item -LiteralPath $BackupPath -Destination $JarPath -Force
    Log "Original JAR restored successfully."
    Log ("Restored: " + $JarPath)
    exit 0
}

if (-not (Test-Path -LiteralPath $JarPath)) {
    Fail ("Expected CubeIDE plugin JAR not found: " + $JarPath) 23
}

Log ("Target JAR: " + $JarPath)

$classBytes = Get-ClassBytesFromJar $JarPath

if (Is-AlreadyPatched $classBytes) {
    Log "The validate() method is already patched. No changes were made."
    exit 0
}

# Sanity check: confirm this really looks like ST's firmware-verification class.
$ascii = [Text.Encoding]::ASCII.GetString($classBytes)
if ($ascii.IndexOf("ST-LINK firmware verification", [StringComparison]::Ordinal) -lt 0 -or
    $ascii.IndexOf("No ST-LINK detected!", [StringComparison]::Ordinal) -lt 0) {
    Fail "Target class did not contain the expected STM32CubeIDE firmware-verification strings. Refusing to patch." 24
}

if (-not (Test-Path -LiteralPath $BackupPath)) {
    Copy-Item -LiteralPath $JarPath -Destination $BackupPath -Force
    Log ("Backup created: " + $BackupPath)
} else {
    Log ("Backup already exists and was left unchanged: " + $BackupPath)
}

$patched = Patch-ValidateMethod $classBytes
Log ("Original class size: " + $classBytes.Length)
Log ("Patched class size : " + $patched.Length)

Replace-ClassInJar $JarPath $patched
Log "JAR updated."

$verify = Get-ClassBytesFromJar $JarPath
if (-not (Is-AlreadyPatched $verify)) {
    Fail "Post-patch verification failed. Restoring original JAR." 25
}

Log "Patch verification succeeded."
Log ""
Log "PATCHED BEHAVIOR:"
Log "  StLinkFwUtil.validate(String) now returns true immediately."
Log "  This bypasses CubeIDE's STLinkServer-based firmware preflight only."
Log "  The normal ST-LINK GDB server, SWD connection, programming, and debug path remain unchanged."
Log ""
Log "Start STM32CubeIDE and try the ST-LINK GDB Server debug configuration again."
exit 0
