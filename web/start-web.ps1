param(
    [int]$Port = 8080
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$prefix = "http://localhost:{0}/" -f $Port

function Get-ContentType {
    param([string]$Path)

    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        ".html" { "text/html; charset=utf-8" }
        ".js" { "application/javascript; charset=utf-8" }
        ".css" { "text/css; charset=utf-8" }
        ".json" { "application/json; charset=utf-8" }
        ".svg" { "image/svg+xml" }
        ".png" { "image/png" }
        ".jpg" { "image/jpeg" }
        ".jpeg" { "image/jpeg" }
        ".ico" { "image/x-icon" }
        default { "application/octet-stream" }
    }
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
$listener.Start()

Write-Host ("Serving static files from: {0}" -f $root)
Write-Host ("Open: {0}" -f $prefix)
Write-Host "Press Ctrl+C to stop."

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $requestPath = [System.Uri]::UnescapeDataString($context.Request.Url.AbsolutePath)
        if ([string]::IsNullOrWhiteSpace($requestPath) -or $requestPath -eq "/") {
            $requestPath = "/index.html"
        }

        $relativePath = $requestPath.TrimStart("/") -replace "/", "\"
        if ($relativePath.Contains("..")) {
            $context.Response.StatusCode = 400
            $context.Response.Close()
            continue
        }

        $fullPath = Join-Path $root $relativePath
        if (-not (Test-Path -Path $fullPath -PathType Leaf)) {
            $context.Response.StatusCode = 404
            $context.Response.Close()
            continue
        }

        $bytes = [System.IO.File]::ReadAllBytes($fullPath)
        $context.Response.ContentType = Get-ContentType -Path $fullPath
        $context.Response.ContentLength64 = $bytes.Length
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $context.Response.Close()
    }
}
finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
}
