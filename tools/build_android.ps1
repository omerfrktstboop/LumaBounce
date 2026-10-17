param(
	[ValidateSet('Release', 'Debug')][string]$Configuration = 'Release',
	[string]$OutputPath,
	[string]$GodotPath,
	[string]$SecretsDirectory = 'D:\LumaBounceSecrets'
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path $PSScriptRoot -Parent

# Godotx Firebase, Gradle sablonunun build.gradle dosyasinda Google Services ve
# Crashlytics eklentilerini ister. Sablon (android/build) git'e girmez ve
# "Install Android Build Template" onu sifirlar; bu yuzden satirlar her
# derlemeden once denetlenir ve yoksa eklenir (idempotent).
function Ensure-FirebaseGradle([string]$GradlePath) {
	if (-not (Test-Path -LiteralPath $GradlePath)) {
		throw "Android build template missing: $GradlePath (Project > Install Android Build Template)."
	}
	$text = [IO.File]::ReadAllText($GradlePath)
	if ($text.Contains('com.google.gms:google-services')) { return }
	$header = @"
// Godotx Firebase - tools/build_android.ps1 ekler (buildscript dosyanin en basinda olmali).
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.google.gms:google-services:4.4.4'
        classpath 'com.google.firebase:firebase-crashlytics-gradle:3.0.6'
    }
}

"@
	$footer = @"

// Godotx Firebase - tools/build_android.ps1 ekler.
apply plugin: 'com.google.gms.google-services'
apply plugin: 'com.google.firebase.crashlytics'
"@
	[IO.File]::WriteAllText($GradlePath, $header + $text + $footer)
	Write-Output "Firebase Gradle lines added: $GradlePath"
}
if (-not $GodotPath) {
	$GodotPath = Join-Path (Split-Path $projectDirectory -Parent) 'Godot_v4.7.2-stable_win64_console.exe'
}
$credentialPath = Join-Path $SecretsDirectory 'signing-current-user.clixml'
$variables = @('JAVA_HOME', 'ANDROID_HOME', 'ANDROID_SDK_ROOT', 'GRADLE_USER_HOME', 'GRADLE_OPTS',
	'GODOT_ANDROID_KEYSTORE_RELEASE_PATH', 'GODOT_ANDROID_KEYSTORE_RELEASE_USER',
	'GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD')
$previous = @{}
foreach ($name in $variables) {
	$previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$password = $null
try {
	$jdk = Get-ChildItem 'D:\DevTools\jdk17' -Directory | Where-Object {
		Test-Path (Join-Path $_.FullName 'bin\java.exe')
	} | Select-Object -First 1
	if (-not $jdk) { throw 'JDK 17 is missing from D:\DevTools\jdk17.' }
	if (-not (Test-Path -LiteralPath $GodotPath)) { throw 'Godot executable is missing.' }
	if (-not (Test-Path -LiteralPath (Join-Path $projectDirectory 'google-services.json'))) {
		throw 'google-services.json is missing (Firebase console > Project settings > Android app).'
	}
	Ensure-FirebaseGradle (Join-Path $projectDirectory 'android\build\build.gradle')
	$env:JAVA_HOME = $jdk.FullName
	$env:ANDROID_HOME = 'D:\DevTools\android-sdk'
	$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
	$env:GRADLE_USER_HOME = 'D:\DevTools\gradle-home'
	# A persistent Gradle daemon inherits the Godot console pipes on Windows.
	# Let it exit after this build so the console wrapper also finishes.
	$env:GRADLE_OPTS = "$($previous['GRADLE_OPTS']) -Dorg.gradle.daemon=false".Trim()
	if ($Configuration -eq 'Release') {
		$credential = Import-Clixml -LiteralPath $credentialPath
		$password = $credential.GetNetworkCredential().Password
		$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = Join-Path $SecretsDirectory 'lumabounce-release.jks'
		$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $credential.UserName
		$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $password
		$exportMode = '--export-release'
		$extension = 'aab'
	} else {
		$exportMode = '--export-debug'
		$extension = 'apk'
	}
	if (-not $OutputPath) {
		$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
		$OutputPath = Join-Path $projectDirectory "builds\lumabounce-$($Configuration.ToLower())-$stamp.$extension"
	} elseif (-not [IO.Path]::IsPathRooted($OutputPath)) {
		$OutputPath = Join-Path $projectDirectory $OutputPath
	}
	if (Test-Path -LiteralPath $OutputPath) { throw "Output already exists: $OutputPath" }
	[void][IO.Directory]::CreateDirectory((Split-Path $OutputPath -Parent))
	# Capture stderr as text and redact the signing password before showing diagnostics.
	$ErrorActionPreference = 'Continue'
	& $GodotPath --headless --path $projectDirectory $exportMode "Android $Configuration" $OutputPath 2>&1 | ForEach-Object {
		$line = [string]$_
		if ($password) { $line = $line.Replace($password, '[REDACTED]') }
		Write-Output $line
	}
	$exitCode = $LASTEXITCODE
	$ErrorActionPreference = 'Stop'
	if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $OutputPath)) {
		throw "Android export failed (exit $exitCode)."
	}
	Write-Output "Build complete: $OutputPath"
} finally {
	foreach ($name in $variables) {
		[Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
	}
	$password = $null
	$credential = $null
}
