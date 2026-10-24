$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot 'Cardiovascular-Explorer'
$index = Join-Path $root 'Cardiovascular-Explorer.html'
if (!(Test-Path $index)) {
    Write-Host 'ERROR: Simulation files are missing.' -ForegroundColor Red
    Write-Host "Expected: $index"
    exit 1
}

$listener = $null
$port = 8765
for ($p = 8765; $p -le 8775; $p++) {
    try {
        $candidate = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $p)
        $candidate.Start()
        $listener = $candidate
        $port = $p
        break
    } catch {
        if ($candidate) { try { $candidate.Stop() } catch {} }
    }
}
if ($null -eq $listener) {
    Write-Host 'ERROR: Could not find a free local port between 8765 and 8775.' -ForegroundColor Red
    exit 1
}

$url = "http://127.0.0.1:$port/"
Write-Host ''
Write-Host ' Cardiovascular Explorer — OFFLINE MODE' -ForegroundColor Yellow
Write-Host ' No internet, Python, VS Code, or installation required.' -ForegroundColor Green
Write-Host " Address: $url" -ForegroundColor Cyan
Write-Host ' Keep this window open while using the simulation.'
Write-Host ' Close this window to stop the local server.'
Write-Host ''
Start-Sleep -Milliseconds 500
try { Start-Process $url } catch { Write-Host "Open this address manually: $url" }

$utf8 = New-Object System.Text.UTF8Encoding($false)
while ($true) {
    $client = $null
    $stream = $null
    try {
        $client = $listener.AcceptTcpClient()
        $client.ReceiveTimeout = 5000
        $client.SendTimeout = 5000
        $stream = $client.GetStream()
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
        $requestLine = $reader.ReadLine()
        if ([string]::IsNullOrWhiteSpace($requestLine)) { continue }
        # Consume request headers.
        while ($true) { $line = $reader.ReadLine(); if ([string]::IsNullOrEmpty($line)) { break } }
        $parts = $requestLine.Split(' ')
        if ($parts.Count -lt 2 -or $parts[0] -notin @('GET','HEAD')) {
            $body = [System.Text.Encoding]::UTF8.GetBytes('Only GET and HEAD are supported.')
            $status = '405 Method Not Allowed'
            $mime = 'text/plain; charset=utf-8'
        } else {
            $rawPath = [Uri]::UnescapeDataString(($parts[1] -split '\?')[0])
            if ($rawPath -eq '/') { $rawPath = '/Cardiovascular-Explorer.html' }
            $rawPath = $rawPath.TrimStart('/').Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            $full = [System.IO.Path]::GetFullPath((Join-Path $root $rawPath))
            $rootFull = [System.IO.Path]::GetFullPath($root) + [System.IO.Path]::DirectorySeparatorChar
            if (!$full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -and $full -ne (Join-Path $root 'Cardiovascular-Explorer.html')) {
                $status = '403 Forbidden'; $body = [System.Text.Encoding]::UTF8.GetBytes('Forbidden'); $mime = 'text/plain; charset=utf-8'
            } elseif (!(Test-Path -LiteralPath $full -PathType Leaf)) {
                $status = '404 Not Found'; $body = [System.Text.Encoding]::UTF8.GetBytes('File not found'); $mime = 'text/plain; charset=utf-8'
            } else {
                $status = '200 OK'
                $ext = [System.IO.Path]::GetExtension($full).ToLowerInvariant()
                $mime = switch ($ext) {
                    '.html' {'text/html; charset=utf-8'} '.js' {'text/javascript; charset=utf-8'} '.mjs' {'text/javascript; charset=utf-8'}
                    '.css' {'text/css; charset=utf-8'} '.json' {'application/json; charset=utf-8'} '.wasm' {'application/wasm'}
                    '.glb' {'model/gltf-binary'} '.gltf' {'model/gltf+json'} '.png' {'image/png'} '.jpg' {'image/jpeg'}
                    '.jpeg' {'image/jpeg'} '.svg' {'image/svg+xml'} '.woff2' {'font/woff2'} default {'application/octet-stream'}
                }
                $body = [System.IO.File]::ReadAllBytes($full)
            }
        }
        $head = "HTTP/1.1 $status`r`nContent-Type: $mime`r`nContent-Length: $($body.Length)`r`nCache-Control: no-cache`r`nConnection: close`r`nX-Content-Type-Options: nosniff`r`n`r`n"
        $headBytes = [System.Text.Encoding]::ASCII.GetBytes($head)
        $stream.Write($headBytes, 0, $headBytes.Length)
        if ($parts.Count -ge 1 -and $parts[0] -eq 'GET' -and $body.Length -gt 0) { $stream.Write($body, 0, $body.Length) }
        $stream.Flush()
    } catch {
        # Browser may close a connection early; continue serving other requests.
    } finally {
        if ($stream) { try { $stream.Dispose() } catch {} }
        if ($client) { try { $client.Close() } catch {} }
    }
}
