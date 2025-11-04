# Production Benchmarking Quick Start
# Run this script to execute all benchmark tests and generate reports

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Production Benchmarking Quick Start" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if Flutter is available
$flutterVersion = flutter --version 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Flutter not found. Please install Flutter first." -ForegroundColor Red
    exit 1
}

Write-Host "✅ Flutter detected" -ForegroundColor Green
Write-Host ""

# Navigate to project directory
$projectDir = "C:\Users\Acer\Documents\gps-tracker-version-translation\my_app_gps_version2"
if (-not (Test-Path $projectDir)) {
    Write-Host "❌ Project directory not found: $projectDir" -ForegroundColor Red
    exit 1
}

Set-Location $projectDir
Write-Host "📂 Working directory: $projectDir" -ForegroundColor Cyan
Write-Host ""

# Menu
Write-Host "Select benchmarking mode:" -ForegroundColor Yellow
Write-Host "1. Run all benchmark tests (automated)" -ForegroundColor White
Write-Host "2. Build profile APK for manual testing" -ForegroundColor White
Write-Host "3. Run in profile mode with DevTools" -ForegroundColor White
Write-Host "4. View last benchmark report" -ForegroundColor White
Write-Host "5. Enable Firebase debug logging (Android)" -ForegroundColor White
Write-Host "6. Exit" -ForegroundColor White
Write-Host ""

$choice = Read-Host "Enter choice (1-6)"

switch ($choice) {
    "1" {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Running Benchmark Tests" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "⚠️  Note: Device streaming test takes ~2 minutes" -ForegroundColor Yellow
        Write-Host ""
        
        # Run benchmark tests
        flutter test test/benchmark_performance_test.dart --reporter expanded
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "✅ All benchmark tests completed!" -ForegroundColor Green
            Write-Host ""
            Write-Host "📊 Report saved to: <app_documents>/benchmarks/last_run.json" -ForegroundColor Cyan
            Write-Host "   (Check device storage after running on device)" -ForegroundColor Gray
        } else {
            Write-Host ""
            Write-Host "❌ Some tests failed. Review output above." -ForegroundColor Red
        }
    }
    
    "2" {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Building Profile APK" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        
        flutter build apk --profile
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "✅ Profile APK built successfully!" -ForegroundColor Green
            Write-Host ""
            Write-Host "📦 APK location:" -ForegroundColor Cyan
            Write-Host "   build\app\outputs\flutter-apk\app-profile.apk" -ForegroundColor White
            Write-Host ""
            Write-Host "📲 Install with:" -ForegroundColor Cyan
            Write-Host "   adb install build\app\outputs\flutter-apk\app-profile.apk" -ForegroundColor White
        } else {
            Write-Host ""
            Write-Host "❌ Build failed. Review output above." -ForegroundColor Red
        }
    }
    
    "3" {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Running in Profile Mode" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "🚀 Starting app in profile mode..." -ForegroundColor Yellow
        Write-Host "📊 DevTools will open automatically" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Tabs to check:" -ForegroundColor Cyan
        Write-Host "  • Performance: Frame timeline, jank detection" -ForegroundColor White
        Write-Host "  • Memory: Heap usage, allocation tracking" -ForegroundColor White
        Write-Host "  • Network: HTTP request timeline" -ForegroundColor White
        Write-Host ""
        
        flutter run --profile --observatory-port=9100
    }
    
    "4" {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "View Last Benchmark Report" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        
        $reportPath = "$env:USERPROFILE\Documents\benchmarks\last_run.json"
        
        if (Test-Path $reportPath) {
            Write-Host "📊 Report location: $reportPath" -ForegroundColor Cyan
            Write-Host ""
            
            $report = Get-Content $reportPath -Raw | ConvertFrom-Json
            
            Write-Host "Test: $($report.test_name)" -ForegroundColor Yellow
            Write-Host "Duration: $($report.duration_ms)ms" -ForegroundColor White
            Write-Host "Timestamp: $($report.timestamp)" -ForegroundColor Gray
            Write-Host ""
            
            Write-Host "Frame Metrics:" -ForegroundColor Cyan
            Write-Host "  • Total Frames: $($report.frame_metrics.total_frames)" -ForegroundColor White
            Write-Host "  • Avg Frame Time: $($report.frame_metrics.avg_frame_time_ms)ms" -ForegroundColor White
            Write-Host "  • Dropped Frames: $($report.frame_metrics.dropped_percent)%" -ForegroundColor White
            
            $frameStatus = if ($report.frame_metrics.avg_frame_time_ms -lt 16 -and $report.frame_metrics.dropped_percent -lt 1) { "✅ PASS" } else { "❌ FAIL" }
            Write-Host "  • Status: $frameStatus" -ForegroundColor $(if ($frameStatus -match "PASS") { "Green" } else { "Red" })
            Write-Host ""
            
            if ($report.network_metrics.total_requests -gt 0) {
                Write-Host "Network Metrics:" -ForegroundColor Cyan
                Write-Host "  • Total Requests: $($report.network_metrics.total_requests)" -ForegroundColor White
                Write-Host "  • Avg Latency: $($report.network_metrics.avg_latency_ms)ms" -ForegroundColor White
                Write-Host "  • Retries: $($report.network_metrics.retry_count)" -ForegroundColor White
                
                $networkStatus = if ($report.network_metrics.avg_latency_ms -lt 200 -and $report.network_metrics.retry_count -le 3) { "✅ PASS" } else { "❌ FAIL" }
                Write-Host "  • Status: $networkStatus" -ForegroundColor $(if ($networkStatus -match "PASS") { "Green" } else { "Red" })
                Write-Host ""
            }
            
            Write-Host "📄 Full report: notepad $reportPath" -ForegroundColor Gray
        } else {
            Write-Host "⚠️  No benchmark report found at: $reportPath" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Run benchmark tests first (option 1)" -ForegroundColor Gray
        }
    }
    
    "5" {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Enable Firebase Debug Logging" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        
        Write-Host "Setting Firebase log level..." -ForegroundColor Yellow
        adb shell setprop log.tag.FirebasePerformance DEBUG
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Firebase debug logging enabled" -ForegroundColor Green
            Write-Host ""
            Write-Host "📊 View logs with:" -ForegroundColor Cyan
            Write-Host "   adb logcat -s FirebasePerformance:D PERF_TRACE:D FRAME_MONITOR:D" -ForegroundColor White
            Write-Host ""
            Write-Host "Expected logs:" -ForegroundColor Cyan
            Write-Host "   D/FirebasePerformance: Performance collection enabled" -ForegroundColor Gray
            Write-Host "   D/PERF_TRACE: [load_trips] Started (device_count: 10)" -ForegroundColor Gray
            Write-Host "   D/PERF_TRACE: [load_trips] Stopped (duration_ms: 234)" -ForegroundColor Gray
            Write-Host ""
            Write-Host "⚠️  Disable after testing:" -ForegroundColor Yellow
            Write-Host '   adb shell setprop log.tag.FirebasePerformance ""' -ForegroundColor White
        } else {
            Write-Host "❌ Failed to enable logging. Is device connected?" -ForegroundColor Red
            Write-Host ""
            Write-Host "Check device connection:" -ForegroundColor Gray
            Write-Host "   adb devices" -ForegroundColor White
        }
    }
    
    "6" {
        Write-Host ""
        Write-Host "👋 Goodbye!" -ForegroundColor Cyan
        exit 0
    }
    
    default {
        Write-Host ""
        Write-Host "❌ Invalid choice. Please run again and select 1-6." -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📚 Documentation: docs\PRODUCTION_BENCHMARKING_COMPLETE.md" -ForegroundColor Gray
Write-Host ""

# Pause to read output
Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
