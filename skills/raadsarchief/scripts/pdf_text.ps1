<#
.SYNOPSIS
  Text extraction for the raadsarchief index: PDF, Markdown, text, HTML and DOCX.

.DESCRIPTION
  Dot-source this file and call Get-DocumentText -Path <file>.
  Returns an object with Text (pages separated by a form feed, `f), Pages and Extractor.

  PDF:
  - If `pdftotext` (Poppler, Xpdf or Git for Windows) is on PATH it is used: best quality.
  - Otherwise a built-in extractor in plain PowerShell is used. It handles what council
    documents from Word and LibreOffice contain: FlateDecode streams, object streams
    (PDF 1.5), Type0/Identity-H fonts with ToUnicode CMaps, simple fonts (WinAnsi),
    Tj/TJ/'/" text operators and form XObjects. It does NOT do OCR: a scanned PDF
    without a text layer yields no text (Extractor reports 'no text layer').
    Encrypted PDFs are skipped.
  Works with Windows PowerShell 5.1 and PowerShell 7.
#>

$script:Latin1 = [Text.Encoding]::GetEncoding(28591)
$script:WinAnsi = $null
try { $script:WinAnsi = [Text.Encoding]::GetEncoding(1252) } catch {
    try {
        [Text.Encoding]::RegisterProvider([Text.CodePagesEncodingProvider]::Instance)
        $script:WinAnsi = [Text.Encoding]::GetEncoding(1252)
    } catch { $script:WinAnsi = $script:Latin1 }
}
$script:BigEndianUnicode = New-Object System.Text.UnicodeEncoding($true, $false)

function ConvertFrom-PdfFlate([byte[]]$Data) {
    if ($null -eq $Data -or $Data.Length -lt 2) { return , ([byte[]]@()) }
    $offset = 0
    if (($Data[0] -band 0x0F) -eq 8 -and ((([int]$Data[0] * 256) + [int]$Data[1]) % 31) -eq 0) { $offset = 2 }
    $ms = New-Object IO.MemoryStream(, $Data)
    [void]$ms.Seek($offset, [IO.SeekOrigin]::Begin)
    $ds = New-Object IO.Compression.DeflateStream($ms, [IO.Compression.CompressionMode]::Decompress)
    $out = New-Object IO.MemoryStream
    $buf = New-Object byte[] 65536
    try {
        while ($true) {
            $n = $ds.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            $out.Write($buf, 0, $n)
        }
    } catch { }   # damaged or truncated stream: keep what was decoded
    finally { $ds.Dispose(); $ms.Dispose() }
    return , $out.ToArray()
}

# Balanced << >> starting at index $start (which points at '<<'); returns the substring
function Get-PdfBalancedDict([string]$s, [int]$start) {
    $depth = 0; $i = $start
    while ($i -lt $s.Length - 1) {
        if ($s[$i] -eq '<' -and $s[$i + 1] -eq '<') { $depth++; $i += 2; continue }
        if ($s[$i] -eq '>' -and $s[$i + 1] -eq '>') { $depth--; $i += 2; if ($depth -eq 0) { return $s.Substring($start, $i - $start) }; continue }
        $i++
    }
    return $s.Substring($start)
}

# Value of /Key in a dictionary text: returns @{ Ref = n } or @{ Dict = '<<...>>' } or $null
function Get-PdfEntry([string]$dict, [string]$key) {
    if (-not $dict) { return $null }
    $m = [regex]::Match($dict, '/' + $key + '\s*(\d+)\s+\d+\s+R')
    $d = [regex]::Match($dict, '/' + $key + '\s*<<')
    if ($d.Success -and (-not $m.Success -or $d.Index -lt $m.Index)) {
        return @{ Dict = (Get-PdfBalancedDict $dict ($d.Index + $d.Length - 2)) }
    }
    if ($m.Success) { return @{ Ref = [int]$m.Groups[1].Value } }
    return $null
}

function Get-PdfDictOf($doc, $entry) {
    if ($null -eq $entry) { return $null }
    if ($entry.Dict) { return $entry.Dict }
    $o = $doc.Objects[$entry.Ref]
    if ($o) { return $o.Dict }
    return $null
}

function ConvertFrom-PdfAscii85([byte[]]$Data) {
    $s = $script:Latin1.GetString($Data)
    $end = $s.IndexOf('~>'); if ($end -ge 0) { $s = $s.Substring(0, $end) }
    if ($s.StartsWith('<~')) { $s = $s.Substring(2) }
    $s = $s -replace '\s', ''
    $out = New-Object System.Collections.Generic.List[byte]
    $group = New-Object System.Collections.Generic.List[int]
    foreach ($ch in $s.ToCharArray()) {
        if ($ch -ceq 'z' -and $group.Count -eq 0) { 1..4 | ForEach-Object { $out.Add(0) }; continue }
        $v = [int]$ch - 33
        if ($v -lt 0 -or $v -gt 84) { continue }
        $group.Add($v)
        if ($group.Count -eq 5) {
            [long]$n = 0; foreach ($g in $group) { $n = $n * 85 + $g }
            $out.Add([byte](($n -shr 24) -band 255)); $out.Add([byte](($n -shr 16) -band 255)); $out.Add([byte](($n -shr 8) -band 255)); $out.Add([byte]($n -band 255))
            $group.Clear()
        }
    }
    if ($group.Count -gt 1) {
        $cnt = $group.Count
        while ($group.Count -lt 5) { $group.Add(84) }
        [long]$n = 0; foreach ($g in $group) { $n = $n * 85 + $g }
        $bytes = @([byte](($n -shr 24) -band 255), [byte](($n -shr 16) -band 255), [byte](($n -shr 8) -band 255), [byte]($n -band 255))
        for ($i = 0; $i -lt $cnt - 1; $i++) { $out.Add($bytes[$i]) }
    }
    return , $out.ToArray()
}

function Get-PdfStreamBytes($obj) {
    if ($null -eq $obj -or $null -eq $obj.Data) { return $null }
    $dict = $obj.Dict
    $filters = @()
    $fm = [regex]::Match($dict, '/Filter\s*(\[[^\]]*\]|/[A-Za-z0-9]+)')
    if ($fm.Success) { $filters = @([regex]::Matches($fm.Groups[1].Value, '/([A-Za-z0-9]+)') | ForEach-Object { $_.Groups[1].Value }) }
    $data = $obj.Data
    foreach ($f in $filters) {
        switch ($f) {
            { $_ -in @('FlateDecode', 'Fl') } { $data = ConvertFrom-PdfFlate $data }
            { $_ -in @('ASCII85Decode', 'A85') } { $data = ConvertFrom-PdfAscii85 $data }
            { $_ -in @('ASCIIHexDecode', 'AHx') } { $data = ConvertFrom-PdfHex ($script:Latin1.GetString($data).TrimEnd('>')) }
            default { return $null }   # images (DCT, JPX, CCITT) and LZW: no text here
        }
    }
    return , $data
}

function Read-PdfObjects([byte[]]$Bytes) {
    $s = $script:Latin1.GetString($Bytes)
    $objects = @{}
    $headers = [regex]::Matches($s, '(?<![0-9])(\d+)\s+(\d+)\s+obj\b')
    for ($h = 0; $h -lt $headers.Count; $h++) {
        $hm = $headers[$h]
        $num = [int]$hm.Groups[1].Value
        $bodyStart = $hm.Index + $hm.Length
        $endObj = $s.IndexOf('endobj', $bodyStart)
        if ($endObj -lt 0) { $endObj = $s.Length }
        $streamPos = $s.IndexOf('stream', $bodyStart)
        $data = $null
        if ($streamPos -ge 0 -and $streamPos -lt $endObj -and $s.Substring($bodyStart, $streamPos - $bodyStart) -match '>>\s*$') {
            $dict = $s.Substring($bodyStart, $streamPos - $bodyStart)
            $dataStart = $streamPos + 6
            if ($dataStart -lt $s.Length -and $s[$dataStart] -eq "`r") { $dataStart++ }
            if ($dataStart -lt $s.Length -and $s[$dataStart] -eq "`n") { $dataStart++ }
            $len = -1
            $lm = [regex]::Match($dict, '/Length\s+(\d+)(?!\s+\d+\s+R)')
            if ($lm.Success) { $len = [int]$lm.Groups[1].Value }
            if ($len -lt 0 -or $dataStart + $len -gt $s.Length -or $s.IndexOf('endstream', $dataStart + $len) -gt $dataStart + $len + 20) {
                $es = $s.IndexOf('endstream', $dataStart)
                if ($es -lt 0) { $es = $s.Length }
                $len = $es - $dataStart
                while ($len -gt 0 -and ($s[$dataStart + $len - 1] -eq "`n" -or $s[$dataStart + $len - 1] -eq "`r")) { $len-- }
            }
            $data = New-Object byte[] $len
            [Array]::Copy($Bytes, $dataStart, $data, 0, $len)
            $endObj = $s.IndexOf('endobj', $dataStart + $len)
            if ($endObj -lt 0) { $endObj = $s.Length }
        } else {
            $dict = $s.Substring($bodyStart, $endObj - $bodyStart)
        }
        $objects[$num] = [pscustomobject]@{ Dict = $dict; Data = $data }
    }
    # Object streams (PDF 1.5+): objects packed in a compressed stream
    foreach ($key in @($objects.Keys)) {
        $o = $objects[$key]
        if ($o.Data -and $o.Dict -match '/Type\s*/ObjStm') {
            $raw = Get-PdfStreamBytes $o
            if (-not $raw) { continue }
            $txt = $script:Latin1.GetString($raw)
            $n = 0; $first = 0
            if ($o.Dict -match '/N\s+(\d+)') { $n = [int]$Matches[1] }
            if ($o.Dict -match '/First\s+(\d+)') { $first = [int]$Matches[1] }
            $nums = [regex]::Matches($txt.Substring(0, [Math]::Min($first, $txt.Length)), '\d+')
            for ($k = 0; $k -lt $n -and (2 * $k + 1) -lt $nums.Count; $k++) {
                $objNum = [int]$nums[2 * $k].Value
                $start = $first + [int]$nums[2 * $k + 1].Value
                $end = if ((2 * $k + 3) -lt $nums.Count) { $first + [int]$nums[2 * $k + 3].Value } else { $txt.Length }
                if ($start -ge $txt.Length) { continue }
                if (-not $objects.ContainsKey($objNum)) {
                    $objects[$objNum] = [pscustomobject]@{ Dict = $txt.Substring($start, [Math]::Max(0, $end - $start)); Data = $null }
                }
            }
        }
    }
    $root = $null
    $rm = [regex]::Matches($s, '/Root\s+(\d+)\s+\d+\s+R')
    if ($rm.Count -gt 0) { $root = [int]$rm[$rm.Count - 1].Groups[1].Value }
    return [pscustomobject]@{ Objects = $objects; Root = $root; Encrypted = ($s -match '/Encrypt\s+(\d+\s+\d+\s+R|<<)') }
}

function ConvertFrom-PdfHex([string]$hex) {
    $hex = $hex -replace '[^0-9A-Fa-f]', ''
    if ($hex.Length % 2) { $hex += '0' }
    $b = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $b.Length; $i++) { $b[$i] = [Convert]::ToByte($hex.Substring(2 * $i, 2), 16) }
    return , $b
}

function Read-PdfCMap([string]$text) {
    $map = @{}
    $ranges = New-Object System.Collections.ArrayList
    $width = 1
    $cs = [regex]::Match($text, 'begincodespacerange\s*<([0-9A-Fa-f]+)>')
    if ($cs.Success) { $width = [Math]::Max(1, [int]($cs.Groups[1].Value.Length / 2)) }
    foreach ($blk in [regex]::Matches($text, '(?s)beginbfchar(.*?)endbfchar')) {
        foreach ($m in [regex]::Matches($blk.Groups[1].Value, '<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]*)>')) {
            $src = [Convert]::ToInt32($m.Groups[1].Value, 16)
            $map[$src] = $script:BigEndianUnicode.GetString((ConvertFrom-PdfHex $m.Groups[2].Value))
        }
    }
    foreach ($blk in [regex]::Matches($text, '(?s)beginbfrange(.*?)endbfrange')) {
        foreach ($m in [regex]::Matches($blk.Groups[1].Value, '<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(<[0-9A-Fa-f]*>|\[[^\]]*\])')) {
            $lo = [Convert]::ToInt32($m.Groups[1].Value, 16)
            $hi = [Convert]::ToInt32($m.Groups[2].Value, 16)
            $dst = $m.Groups[3].Value
            if ($dst.StartsWith('[')) {
                $k = 0
                foreach ($e in [regex]::Matches($dst, '<([0-9A-Fa-f]*)>')) {
                    if ($lo + $k -gt $hi) { break }
                    $map[$lo + $k] = $script:BigEndianUnicode.GetString((ConvertFrom-PdfHex $e.Groups[1].Value)); $k++
                }
            } elseif ($hi - $lo -le 256) {
                $base = ConvertFrom-PdfHex $dst.Trim('<', '>')
                for ($c = $lo; $c -le $hi; $c++) {
                    $b = [byte[]]$base.Clone()
                    $carry = $c - $lo; $p = $b.Length - 1
                    while ($carry -gt 0 -and $p -ge 0) { $v = [int]$b[$p] + $carry; $b[$p] = [byte]($v % 256); $carry = [Math]::Floor($v / 256); $p-- }
                    $map[$c] = $script:BigEndianUnicode.GetString($b)
                }
            } else {
                $base = ConvertFrom-PdfHex $dst.Trim('<', '>')
                [void]$ranges.Add(@($lo, $hi, $base))
            }
        }
    }
    return [pscustomobject]@{ Map = $map; Ranges = $ranges; Width = $width }
}

function Get-PdfFont($doc, [int]$ref) {
    if ($doc.FontCache.ContainsKey($ref)) { return $doc.FontCache[$ref] }
    $font = [pscustomobject]@{ CMap = $null; Width = 1 }
    $fd = $doc.Objects[$ref]
    if ($fd) {
        if ($fd.Dict -match '/Subtype\s*/Type0') { $font.Width = 2 }
        $tu = Get-PdfEntry $fd.Dict 'ToUnicode'
        if ($tu -and $tu.Ref) {
            $raw = Get-PdfStreamBytes $doc.Objects[$tu.Ref]
            if ($raw) { $font.CMap = Read-PdfCMap ($script:Latin1.GetString($raw)); $font.Width = $font.CMap.Width }
        }
    }
    $doc.FontCache[$ref] = $font
    return $font
}

function Get-PdfFontsOf($doc, [string]$resources) {
    $fonts = @{}
    $fdict = Get-PdfDictOf $doc (Get-PdfEntry $resources 'Font')
    if ($fdict) {
        foreach ($m in [regex]::Matches($fdict, '/([^\s/<>\[\]()]+)\s*(\d+)\s+\d+\s+R')) {
            $fonts[$m.Groups[1].Value] = Get-PdfFont $doc ([int]$m.Groups[2].Value)
        }
    }
    return $fonts
}

function ConvertFrom-PdfLiteral([string]$t) {
    # $t without the outer parentheses; returns bytes (chars are Latin1 = bytes)
    $out = New-Object System.Collections.Generic.List[byte]
    $i = 0
    while ($i -lt $t.Length) {
        $ch = $t[$i]
        if ($ch -ne '\') { $out.Add([byte][int]$ch); $i++; continue }
        $i++
        if ($i -ge $t.Length) { break }
        $e = $t[$i]
        switch -CaseSensitive ($e) {
            'n' { $out.Add(10); $i++ }
            'r' { $out.Add(13); $i++ }
            't' { $out.Add(9); $i++ }
            'b' { $out.Add(8); $i++ }
            'f' { $out.Add(12); $i++ }
            "`r" { $i++; if ($i -lt $t.Length -and $t[$i] -eq "`n") { $i++ } }
            "`n" { $i++ }
            default {
                if ($e -ge '0' -and $e -le '7') {
                    $oct = ''
                    while ($oct.Length -lt 3 -and $i -lt $t.Length -and $t[$i] -ge '0' -and $t[$i] -le '7') { $oct += $t[$i]; $i++ }
                    $out.Add([byte]([Convert]::ToInt32($oct, 8) % 256))
                } else { $out.Add([byte][int]$e); $i++ }
            }
        }
    }
    return , $out.ToArray()
}

function ConvertFrom-PdfString($font, [byte[]]$b) {
    if ($null -eq $font -or $null -eq $font.CMap) {
        if ($font -and $font.Width -eq 2) { return '' }   # Identity-H without ToUnicode: no reliable text
        return $script:WinAnsi.GetString($b)
    }
    $cm = $font.CMap; $w = $cm.Width
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i + $w -le $b.Length; $i += $w) {
        $code = 0
        for ($k = 0; $k -lt $w; $k++) { $code = $code * 256 + $b[$i + $k] }
        if ($cm.Map.ContainsKey($code)) { [void]$sb.Append($cm.Map[$code]); continue }
        $hit = $false
        foreach ($r in $cm.Ranges) {
            if ($code -ge $r[0] -and $code -le $r[1]) {
                $base = [byte[]]$r[2].Clone(); $carry = $code - $r[0]; $p = $base.Length - 1
                while ($carry -gt 0 -and $p -ge 0) { $v = [int]$base[$p] + $carry; $base[$p] = [byte]($v % 256); $carry = [Math]::Floor($v / 256); $p-- }
                [void]$sb.Append($script:BigEndianUnicode.GetString($base)); $hit = $true; break
            }
        }
        if (-not $hit -and $w -eq 1) { [void]$sb.Append($script:WinAnsi.GetString(@($b[$i]))) }
    }
    return $sb.ToString()
}

$script:PdfTokenRegex = New-Object regex ('\((?:\\[\s\S]|[^\\()]|\((?:\\[\s\S]|[^\\()]|\((?:\\[\s\S]|[^\\()])*\))*\))*\)|<<|>>|<[0-9A-Fa-f\s]*>|\[|\]|/[^\s/\[\]()<>{}%]*|[-+]?(?:\d+\.?\d*|\.\d+)|[A-Za-z][A-Za-z0-9*]*|[''"]|%[^\r\n]*'), ([Text.RegularExpressions.RegexOptions]::Compiled)

function Read-PdfContent($doc, [string]$content, [string]$resources, $sb, [int]$depth) {
    $fonts = Get-PdfFontsOf $doc $resources
    $xobjects = Get-PdfDictOf $doc (Get-PdfEntry $resources 'XObject')
    $content = [regex]::Replace($content, '(?s)\bBI\b.*?\bID\b.*?\bEI\b', ' ')
    $font = $null
    $stack = New-Object System.Collections.ArrayList
    $arr = $null
    $lastY = $null
    foreach ($m in $script:PdfTokenRegex.Matches($content)) {
        $t = $m.Value
        $c = $t[0]
        if ($c -eq '(') { $tok = @{ S = (ConvertFrom-PdfLiteral $t.Substring(1, $t.Length - 2)) } }
        elseif ($c -eq '<' -and $t -ne '<<') { $tok = @{ S = (ConvertFrom-PdfHex $t) } }
        elseif ($c -eq '%') { continue }
        elseif ($t -eq '[') { $arr = New-Object System.Collections.ArrayList; continue }
        elseif ($t -eq ']') { $tok = @{ A = $arr }; $arr = $null }
        elseif ($c -eq '/' -or ($c -match '[-+.0-9]') -or $t -eq '<<' -or $t -eq '>>') { $tok = $t }
        else {
            # operator
            switch -CaseSensitive ($t) {
                'Tf' { if ($stack.Count -ge 2) { $fn = [string]$stack[$stack.Count - 2]; $font = $fonts[$fn.TrimStart('/')] } }
                'Tj' { if ($stack.Count -ge 1 -and $stack[$stack.Count - 1] -is [hashtable] -and $stack[$stack.Count - 1].S) { [void]$sb.Append((ConvertFrom-PdfString $font $stack[$stack.Count - 1].S)) } }
                "'" { [void]$sb.Append("`n"); if ($stack.Count -ge 1 -and $stack[$stack.Count - 1] -is [hashtable] -and $stack[$stack.Count - 1].S) { [void]$sb.Append((ConvertFrom-PdfString $font $stack[$stack.Count - 1].S)) } }
                '"' { [void]$sb.Append("`n"); if ($stack.Count -ge 1 -and $stack[$stack.Count - 1] -is [hashtable] -and $stack[$stack.Count - 1].S) { [void]$sb.Append((ConvertFrom-PdfString $font $stack[$stack.Count - 1].S)) } }
                'TJ' {
                    if ($stack.Count -ge 1 -and $stack[$stack.Count - 1] -is [hashtable] -and $stack[$stack.Count - 1].A) {
                        foreach ($e in $stack[$stack.Count - 1].A) {
                            if ($e -is [hashtable] -and $e.S) { [void]$sb.Append((ConvertFrom-PdfString $font $e.S)) }
                            elseif ($e -isnot [hashtable]) { $num = 0.0; if ([double]::TryParse([string]$e, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$num) -and $num -lt -180) { [void]$sb.Append(' ') } }
                        }
                    }
                }
                'T*' { [void]$sb.Append("`n") }
                'Td' { Add-PdfMove $sb $stack 1 }
                'TD' { Add-PdfMove $sb $stack 1 }
                'Tm' {
                    if ($stack.Count -ge 6) {
                        $y = 0.0; [void][double]::TryParse([string]$stack[$stack.Count - 1], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$y)
                        if ($null -ne $lastY -and [Math]::Abs($y - $lastY) -gt 1) { [void]$sb.Append("`n") } elseif ($null -ne $lastY) { Add-PdfSpace $sb }
                        $lastY = $y
                    }
                }
                'ET' { Add-PdfSpace $sb }
                'Do' {
                    if ($depth -lt 3 -and $xobjects -and $stack.Count -ge 1) {
                        $xn = ([string]$stack[$stack.Count - 1]).TrimStart('/')
                        $xm = [regex]::Match($xobjects, '/' + [regex]::Escape($xn) + '\s*(\d+)\s+\d+\s+R')
                        if ($xm.Success) {
                            $xo = $doc.Objects[[int]$xm.Groups[1].Value]
                            if ($xo -and $xo.Dict -match '/Subtype\s*/Form') {
                                $raw = Get-PdfStreamBytes $xo
                                if ($raw) {
                                    $xres = Get-PdfDictOf $doc (Get-PdfEntry $xo.Dict 'Resources')
                                    if (-not $xres) { $xres = $resources }
                                    Read-PdfContent $doc ($script:Latin1.GetString($raw)) $xres $sb ($depth + 1)
                                }
                            }
                        }
                    }
                }
            }
            $stack.Clear()
            continue
        }
        if ($null -ne $arr -and -not ($tok -is [hashtable] -and $tok.A)) { [void]$arr.Add($tok) } else { [void]$stack.Add($tok) }
    }
}

function Add-PdfSpace($sb) {
    if ($sb.Length -gt 0) { $last = $sb[$sb.Length - 1]; if ($last -ne ' ' -and $last -ne "`n") { [void]$sb.Append(' ') } }
}

function Add-PdfMove($sb, $stack, $dummy) {
    if ($stack.Count -lt 2) { return }
    $ty = 0.0
    [void][double]::TryParse([string]$stack[$stack.Count - 1], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$ty)
    if ([Math]::Abs($ty) -gt 0.5) { [void]$sb.Append("`n") } else { Add-PdfSpace $sb }
}

function Get-PdfPages($doc) {
    $pages = New-Object System.Collections.ArrayList
    $visited = @{}
    function Walk($ref, $inheritedRes) {
        if ($visited.ContainsKey($ref) -or $pages.Count -gt 5000) { return }
        $visited[$ref] = $true
        $o = $doc.Objects[$ref]
        if (-not $o) { return }
        $res = Get-PdfDictOf $doc (Get-PdfEntry $o.Dict 'Resources')
        if (-not $res) { $res = $inheritedRes }
        if ($o.Dict -match '/Type\s*/Pages\b') {
            $km = [regex]::Match($o.Dict, '/Kids\s*\[([^\]]*)\]')
            foreach ($k in [regex]::Matches($km.Groups[1].Value, '(\d+)\s+\d+\s+R')) { Walk ([int]$k.Groups[1].Value) $res }
        } elseif ($o.Dict -match '/Type\s*/Page\b') {
            [void]$pages.Add([pscustomobject]@{ Ref = $ref; Dict = $o.Dict; Resources = $res })
        }
    }
    if ($doc.Root -and $doc.Objects[$doc.Root]) {
        $pe = Get-PdfEntry $doc.Objects[$doc.Root].Dict 'Pages'
        if ($pe -and $pe.Ref) { Walk $pe.Ref $null }
    }
    if ($pages.Count -eq 0) {
        foreach ($k in ($doc.Objects.Keys | Sort-Object)) {
            $o = $doc.Objects[$k]
            if ($o.Dict -match '/Type\s*/Page\b') {
                [void]$pages.Add([pscustomobject]@{ Ref = $k; Dict = $o.Dict; Resources = (Get-PdfDictOf $doc (Get-PdfEntry $o.Dict 'Resources')) })
            }
        }
    }
    return , $pages
}

function Get-PdfTextBuiltIn([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $doc = Read-PdfObjects $bytes
    if ($doc.Encrypted) { return [pscustomobject]@{ Text = ''; Pages = 0; Extractor = 'built-in (encrypted, skipped)' } }
    $doc | Add-Member -NotePropertyName FontCache -NotePropertyValue @{}
    $pages = Get-PdfPages $doc
    $parts = New-Object System.Collections.ArrayList
    foreach ($p in $pages) {
        $content = New-Object System.Text.StringBuilder
        $refs = @()
        $cm = [regex]::Match($p.Dict, '/Contents\s*(\d+)\s+\d+\s+R')
        $ca = [regex]::Match($p.Dict, '/Contents\s*\[([^\]]*)\]')
        if ($ca.Success) { $refs = @([regex]::Matches($ca.Groups[1].Value, '(\d+)\s+\d+\s+R') | ForEach-Object { [int]$_.Groups[1].Value }) }
        elseif ($cm.Success) {
            $r = [int]$cm.Groups[1].Value
            $o = $doc.Objects[$r]
            if ($o -and -not $o.Data -and $o.Dict -match '^\s*\[') { $refs = @([regex]::Matches($o.Dict, '(\d+)\s+\d+\s+R') | ForEach-Object { [int]$_.Groups[1].Value }) }
            else { $refs = @($r) }
        }
        foreach ($r in $refs) {
            $raw = Get-PdfStreamBytes $doc.Objects[$r]
            if ($raw) { [void]$content.Append($script:Latin1.GetString($raw)); [void]$content.Append("`n") }
        }
        $sb = New-Object System.Text.StringBuilder
        Read-PdfContent $doc $content.ToString() $p.Resources $sb 0
        [void]$parts.Add($sb.ToString())
    }
    $clean = @($parts | ForEach-Object {
        $lines = ($_ -replace "`r", '') -split "`n" | ForEach-Object { ($_ -replace '[ \t\u00A0]+', ' ').Trim() } | Where-Object { $_ }
        ($lines -join "`n")
    })
    $text = $clean -join "`f"
    $label = if ($text.Trim()) { 'built-in' } else { 'built-in (no text layer)' }
    return [pscustomobject]@{ Text = $text; Pages = $pages.Count; Extractor = $label }
}

function Get-PdfTextPoppler([string]$Path, [string]$Exe) {
    $tmp = [IO.Path]::GetTempFileName()
    try {
        & $Exe -q -enc UTF-8 $Path $tmp 2>$null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tmp)) { return $null }
        $text = [IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8)
        $text = $text.TrimEnd("`f", "`n", "`r", ' ')
        $pages = ($text.Split("`f")).Count
        $text = (($text -replace "`r", '') -split "`f" | ForEach-Object {
            (($_ -split "`n" | ForEach-Object { ($_ -replace '[ \t\u00A0]+', ' ').Trim() } | Where-Object { $_ }) -join "`n")
        }) -join "`f"
        $label = if ($text.Trim()) { 'pdftotext' } else { 'pdftotext (no text layer)' }
        return [pscustomobject]@{ Text = $text; Pages = $pages; Extractor = $label }
    } finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
}

function Get-DocxText([string]$Path) {
    try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue } catch { }
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.GetEntry('word/document.xml')
        if (-not $entry) { return '' }
        $reader = New-Object IO.StreamReader($entry.Open(), [Text.Encoding]::UTF8)
        $xml = $reader.ReadToEnd(); $reader.Dispose()
        $xml = $xml -replace '</w:p>', "`n" -replace '<w:tab/>', ' ' -replace '<[^>]+>', ''
        return [Net.WebUtility]::HtmlDecode($xml)
    } finally { $zip.Dispose() }
}

function Get-DocumentText([string]$Path, [switch]$BuiltInOnly) {
    $ext = [IO.Path]::GetExtension($Path).ToLower()
    switch ($ext) {
        '.pdf' {
            if (-not $BuiltInOnly) {
                $exe = Get-Command pdftotext -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($exe) { $r = Get-PdfTextPoppler $Path $exe.Source; if ($r) { return $r } }
            }
            return Get-PdfTextBuiltIn $Path
        }
        { $_ -in @('.md', '.txt', '.csv') } {
            return [pscustomobject]@{ Text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8); Pages = 1; Extractor = 'text' }
        }
        { $_ -in @('.html', '.htm') } {
            $h = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
            $h = $h -replace '(?is)<(script|style)[^>]*>.*?</\1>', ' ' -replace '(?i)<br\s*/?>|</p>|</div>|</li>|</h\d>', "`n" -replace '<[^>]+>', ' '
            return [pscustomobject]@{ Text = [Net.WebUtility]::HtmlDecode($h); Pages = 1; Extractor = 'html' }
        }
        '.docx' { return [pscustomobject]@{ Text = (Get-DocxText $Path); Pages = 1; Extractor = 'docx' } }
        default { return $null }
    }
}
