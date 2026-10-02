using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Management;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyVersion("1.8.0.0")]
[assembly: AssemblyFileVersion("1.8.0.0")]

internal static class SetupProgram
{
    internal const string Version = "1.8.0";
    internal const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\ClaudeAccountSwitcher";
    internal static readonly string AppDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ClaudeAccountSwitcher", "app");
    internal static readonly string[] AppFiles = { "AccountCore.ps1", "TokenCore.ps1", "TokenUI.ps1", "PreferenceCore.ps1", "TraySupport.ps1", "TrayUI.ps1", "TrayRuntime.ps1", "VisualControls.dll", "UsageCore.ps1", "Usage-Collector.ps1", "Claude-Hesap.ps1", "Claude-Hesap.bat", "Claude-Tray.ps1", "Claude-Tray.vbs", "Claude-Switch.ico", "README.md", "LICENSE" };
    [DllImport("user32.dll", SetLastError = true)] private static extern bool PostThreadMessage(uint id, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();

    [STAThread]
    private static int Main(string[] args)
    {
        SetProcessDPIAware(); Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
        Mutex operation = null; bool acquired = false;
        bool quiet = args.Contains("/quiet") || args.Contains("/install");
        try
        {
            if (args.Length > 0 && args[0] == "/test") { SelfTest(); return 0; }
            if (args.Length > 0 && args[0] == "/preview") { using (var wizard = new SetupWizard()) wizard.Render(args[1], args.Contains("/completed")); return 0; }
            if (args.Length > 0 && args[0] == "/cleanup")
            {
                if (args.Length != 3) throw new InvalidOperationException("Geçersiz kaldırma isteği.");
                int parent = int.Parse(args[1]); try { if (!Process.GetProcessById(parent).WaitForExit(15000)) throw new InvalidOperationException("Önceki kaldırma işlemi kapanmadı."); } catch (ArgumentException) { }
                operation = new Mutex(false, @"Local\ClaudeAccountSwitcherSetup-" + WindowsIdentity.GetCurrent().User.Value);
                try { acquired = operation.WaitOne(0); } catch (AbandonedMutexException) { acquired = true; }
                if (!acquired) throw new InvalidOperationException("Başka bir kurulum işlemi devam ediyor.");
                if (!CleanupGenerationMatches(UninstallKey, args[2])) throw new InvalidOperationException("Daha yeni bir kurulum bulundu. Kaldırma iptal edildi.");
                RemoveFiles(AppDir); Registry.CurrentUser.DeleteSubKeyTree(UninstallKey, false); MessageBox.Show("Uygulama kaldırıldı. Kayıtlı hesapların korundu.", "Claude Hesap Seçici"); return 0;
            }
            var installFlags = new HashSet<string>(new[] { "/install", "/quiet", "/startup", "/no-startup", "/desktop", "/no-desktop", "/no-launch" });
            if (quiet && args.Any(arg => !installFlags.Contains(arg))) throw new InvalidOperationException("Geçersiz kurulum seçeneği.");
            if (args.Contains("/startup") && args.Contains("/no-startup") || args.Contains("/desktop") && args.Contains("/no-desktop")) throw new InvalidOperationException("Çelişen kurulum seçenekleri.");
            operation = new Mutex(false, @"Local\ClaudeAccountSwitcherSetup-" + WindowsIdentity.GetCurrent().User.Value);
            try { acquired = operation.WaitOne(0); } catch (AbandonedMutexException) { acquired = true; }
            if (!acquired) throw new InvalidOperationException("Başka bir kurulum işlemi devam ediyor.");
            if (args.Length > 0 && args[0] == "/uninstall") { Uninstall(); return 0; }
            if (quiet)
            {
                bool auto = args.Contains("/startup") || (!args.Contains("/no-startup") && StartupEnabled);
                bool desk = args.Contains("/desktop") || (!args.Contains("/no-desktop") && DesktopEnabled);
                bool ready = Install(AppDir, auto ? Environment.GetFolderPath(Environment.SpecialFolder.Startup) : null, desk ? Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory) : null, UninstallKey, !args.Contains("/no-launch"), true);
                if (!ready) { Console.Error.WriteLine("Installed, but tray readiness was not confirmed. Launch the installed Claude-Tray.ps1 with PowerShell -STA."); return 2; }
                return 0;
            }
            Application.Run(new SetupWizard()); return 0;
        }
        catch (Exception ex) { if (quiet) { Console.Error.WriteLine("Setup failed: " + ex.Message); } else if (args.Length > 0 && args[0] == "/test") { Console.Error.WriteLine(ex); } else if (args.Length > 1 && args[0] == "/preview") { File.WriteAllText(args[1] + ".error.txt", ex.ToString()); } else MessageBox.Show(ex.Message, "Claude Hesap Seçici", MessageBoxButtons.OK, MessageBoxIcon.Error); return 1; }
        finally { if (acquired) operation.ReleaseMutex(); if (operation != null) operation.Dispose(); }
    }

    internal static bool StopOwnedTray()
    {
        string sid = WindowsIdentity.GetCurrent().User.Value;
        var hosts = new List<Process>();
        using (var search = new ManagementObjectSearcher("SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name='powershell.exe'"))
        using (var results = search.Get()) foreach (ManagementObject item in results)
        {
            string command = item["CommandLine"] as string;
            string marker = "-File \"" + Path.Combine(AppDir, "Claude-Tray.ps1") + "\"";
            if (command == null || command.IndexOf(marker, StringComparison.OrdinalIgnoreCase) < 0) continue;
            try { hosts.Add(Process.GetProcessById(Convert.ToInt32(item["ProcessId"]))); } catch (ArgumentException) { }
        }
        bool wasRunning = hosts.Count != 0;
        try {
        try { using (var request = EventWaitHandle.OpenExisting(@"Local\ClaudeAccountSwitcherTrayShutdown-" + sid)) request.Set(); }
        catch (WaitHandleCannotBeOpenedException)
        {
            // Legacy tray versions predate the cooperative event. Send WM_QUIT only
            // to the verified installed tray host; never terminate a process.
            string marker = "-File \"" + Path.Combine(AppDir, "Claude-Tray.ps1") + "\"";
            using (var search = new ManagementObjectSearcher("SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name='powershell.exe'"))
            using (var results = search.Get())
                foreach (ManagementObject item in results)
                {
                    string command = item["CommandLine"] as string;
                    if (command == null || command.IndexOf(marker, StringComparison.OrdinalIgnoreCase) < 0) continue;
                    try { using (var process = Process.GetProcessById(Convert.ToInt32(item["ProcessId"]))) foreach (ProcessThread thread in process.Threads) PostThreadMessage((uint)thread.Id, 0x0012, IntPtr.Zero, IntPtr.Zero); }
                    catch (ArgumentException) { }
                }
        }
        var deadline = DateTime.UtcNow.AddSeconds(8);
        while (DateTime.UtcNow < deadline)
        {
            Mutex existing = null;
            try { existing = Mutex.OpenExisting(@"Local\ClaudeAccountSwitcherTray-" + sid); }
            catch (WaitHandleCannotBeOpenedException) { if (hosts.All(p => p.HasExited)) return wasRunning; Thread.Sleep(100); continue; }
            using (existing)
            {
                bool acquired = false;
                try { acquired = existing.WaitOne(0); } catch (AbandonedMutexException) { acquired = true; }
                if (acquired) { existing.ReleaseMutex(); if (hosts.All(p => p.HasExited)) return wasRunning; }
            }
            Thread.Sleep(100);
        }
        throw new InvalidOperationException("Hesap seçici güncelleme için kapanamadı. Bildirim alanındaki uygulamadan Çıkış seçip tekrar deneyin. Claude oturumlarına dokunulmadı.");
        } finally { foreach (Process host in hosts) host.Dispose(); }
    }

    private static void Extract(string destination)
    {
        Directory.CreateDirectory(destination);
        var expected = new HashSet<string>(AppFiles, StringComparer.Ordinal);
        using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("AppPayload.zip"))
        using (var archive = new ZipArchive(stream, ZipArchiveMode.Read))
        {
            if (archive.Entries.Count != AppFiles.Length) throw new InvalidDataException("Kurulum paketi eksik.");
            foreach (var entry in archive.Entries)
            {
                if (!expected.Remove(entry.FullName)) throw new InvalidDataException("Kurulumda beklenmeyen dosya.");
                string target = Path.GetFullPath(Path.Combine(destination, entry.FullName));
                string root = Path.GetFullPath(destination).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
                if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Geçersiz dosya yolu.");
                string temporary = target + ".install-" + Guid.NewGuid().ToString("N");
                try
                {
                    using (Stream input = entry.Open()) using (Stream output = File.Create(temporary)) input.CopyTo(output);
                    if (File.Exists(target)) File.Replace(temporary, target, null); else File.Move(temporary, target);
                }
                finally { if (File.Exists(temporary)) File.Delete(temporary); }
            }
        }
    }

    private static void Shortcut(string directory, string app)
    {
        Directory.CreateDirectory(directory);
        dynamic shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
        dynamic shortcut = shell.CreateShortcut(Path.Combine(directory, "Claude Hesap Secici.lnk"));
        try
        {
            shortcut.TargetPath = PowerShellPath;
            shortcut.Arguments = TrayArguments(app);
            shortcut.WindowStyle = 7;
            shortcut.WorkingDirectory = app; shortcut.IconLocation = Path.Combine(app, "Claude-Switch.ico") + ",0"; shortcut.Save();
        }
        finally { Marshal.FinalReleaseComObject(shortcut); Marshal.FinalReleaseComObject(shell); }
    }

    private static bool OwnedShortcut(string path, string app)
    {
        if (!File.Exists(path)) return false;
        dynamic shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell")); dynamic link = shell.CreateShortcut(path);
        try {
            string target = link.TargetPath, arguments = link.Arguments;
            return (target.Equals(PowerShellPath, StringComparison.OrdinalIgnoreCase) && arguments.Equals(TrayArguments(app), StringComparison.OrdinalIgnoreCase)) || (target.Equals(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "wscript.exe"), StringComparison.OrdinalIgnoreCase) && arguments == "\"" + Path.Combine(app, "Claude-Tray.vbs") + "\"");
        }
        finally { Marshal.FinalReleaseComObject(link); Marshal.FinalReleaseComObject(shell); }
    }
    internal static bool StartupEnabled { get { string path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup), "Claude Hesap Secici.lnk"); return Directory.Exists(AppDir) ? OwnedShortcut(path, AppDir) : true; } }
    internal static bool DesktopEnabled { get { return OwnedShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "Claude Hesap Secici.lnk"), AppDir); } }
    private static void ReplaceFile(string source, string target)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(target));
        string temporary = target + ".install-" + Guid.NewGuid().ToString("N");
        try
        {
            File.Copy(source, temporary, true);
            var deadline = DateTime.UtcNow.AddSeconds(4);
            while (true)
            {
                try { if (File.Exists(target)) File.Replace(temporary, target, null, true); else File.Move(temporary, target); return; }
                catch (IOException) { if (DateTime.UtcNow >= deadline) throw; Thread.Sleep(100); }
            }
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    private static void Fault(string point, string injected) { if (point == injected) throw new IOException("Isolated setup test failure: " + point); }
    private static void Log(string phase)
    { try { string folder = Path.GetDirectoryName(AppDir); Directory.CreateDirectory(folder); File.AppendAllText(Path.Combine(folder, "setup.log"), DateTime.UtcNow.ToString("o") + " " + Version + " " + phase + Environment.NewLine); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
    internal static bool Install(string destination, string startup, string desktop, string registryKey, bool launch, bool stopTray, string injectedFailure = null, Action<string> progress = null)
    {
        Mutex accountOperation = stopTray ? new Mutex(false, @"Local\ClaudeAccountSwitcher-" + WindowsIdentity.GetCurrent().User.Value) : null;
        bool ownsAccountOperation = false;
        try {
        if (accountOperation != null) { try { ownsAccountOperation = accountOperation.WaitOne(0); } catch (AbandonedMutexException) { ownsAccountOperation = true; } if (!ownsAccountOperation) throw new InvalidOperationException("Bir hesap işlemi devam ediyor. Kurulumu işlem tamamlanınca tekrar çalıştırın."); }
        if (stopTray) Log("begin");
        string stage = Path.Combine(Path.GetDirectoryName(destination), ".setup-" + Guid.NewGuid().ToString("N"));
        string backup = Path.Combine(stage, "backup");
        var previousFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var links = new Dictionary<string, byte[]>(StringComparer.OrdinalIgnoreCase);
        var oldRegistry = new Dictionary<string, Tuple<object, RegistryValueKind>>();
        bool hadRegistry = false, changed = false, trayStopped = false;
        string uninstaller = Path.Combine(destination, "Uninstall.exe");
        string[] owned = AppFiles.Concat(new[] { "Uninstall.exe" }).ToArray();
        string startupFolder = startup ?? (stopTray ? Environment.GetFolderPath(Environment.SpecialFolder.Startup) : null);
        string desktopFolder = desktop ?? (stopTray ? Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory) : null);
        try
        {
            if (progress != null) progress("Paket doğrulanıyor. Önce sağlam bir sahne.");
            Extract(stage); File.Copy(Application.ExecutablePath, Path.Combine(stage, "Uninstall.exe")); Fault("stage", injectedFailure);
            Directory.CreateDirectory(backup);
            foreach (string name in owned) { string path = Path.Combine(destination, name); if (File.Exists(path)) { File.Copy(path, Path.Combine(backup, name)); previousFiles.Add(name); } }
            foreach (string folder in new[] { startupFolder, desktopFolder }.Where(x => x != null).Distinct(StringComparer.OrdinalIgnoreCase))
            {
                string path = Path.Combine(folder, "Claude Hesap Secici.lnk");
                if (File.Exists(path) && !OwnedShortcut(path, destination)) throw new IOException("Aynı isimde başka bir uygulamanın kısayolu var. Kısayol değiştirilmedi.");
                links[path] = File.Exists(path) ? File.ReadAllBytes(path) : null;
            }
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(registryKey))
            { if (key != null) { hadRegistry = true; foreach (string name in key.GetValueNames()) oldRegistry[name] = Tuple.Create(key.GetValue(name, null, RegistryValueOptions.DoNotExpandEnvironmentNames), key.GetValueKind(name)); } }
            if (progress != null) progress("Önceki uygulama yedekleniyor. Hesap kayıtların korunuyor.");
            if (stopTray) { trayStopped = StopOwnedTray(); }
            changed = true;
            if (progress != null) progress("Uygulama dosyaları yerleşiyor. Birazdan hazır.");
            foreach (string name in owned) ReplaceFile(Path.Combine(stage, name), Path.Combine(destination, name)); Fault("files", injectedFailure);
            if (startup != null) Shortcut(startup, destination); else if (startupFolder != null) { string path = Path.Combine(startupFolder, "Claude Hesap Secici.lnk"); if (OwnedShortcut(path, destination)) File.Delete(path); }
            if (desktop != null) Shortcut(desktop, destination); else if (desktopFolder != null) { string path = Path.Combine(desktopFolder, "Claude Hesap Secici.lnk"); if (OwnedShortcut(path, destination)) File.Delete(path); }
            Fault("shortcuts", injectedFailure);
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(registryKey))
            {
                key.SetValue("DisplayName", "Claude Hesap Seçici"); key.SetValue("DisplayVersion", Version); key.SetValue("InstallGeneration", Guid.NewGuid().ToString("N"));
                key.SetValue("Publisher", "Claude Account Switcher"); key.SetValue("InstallLocation", destination);
                key.SetValue("DisplayIcon", Path.Combine(destination, "Claude-Switch.ico")); key.SetValue("UninstallString", "\"" + uninstaller + "\" /uninstall");
                key.SetValue("NoModify", 1, RegistryValueKind.DWord); key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
            }
            Fault("registry", injectedFailure); if (progress != null) progress("Kısayollar ve Windows kaydı tamam. Son kontrol geliyor.");
        }
        catch (Exception failure)
        {
            if (changed)
            {
                try
                {
                    foreach (string name in owned) { string path = Path.Combine(destination, name); if (previousFiles.Contains(name)) ReplaceFile(Path.Combine(backup, name), path); else if (File.Exists(path)) File.Delete(path); }
                    foreach (var link in links) { if (link.Value == null) { if (File.Exists(link.Key)) File.Delete(link.Key); } else File.WriteAllBytes(link.Key, link.Value); }
                    Registry.CurrentUser.DeleteSubKeyTree(registryKey, false);
                    if (hadRegistry) using (RegistryKey key = Registry.CurrentUser.CreateSubKey(registryKey)) foreach (var value in oldRegistry) key.SetValue(value.Key, value.Value.Item1, value.Value.Item2);
                    if (trayStopped && previousFiles.Contains("Claude-Tray.ps1")) Launch(destination);
                }
                catch (Exception rollback) { if (stopTray) Log("rollback-failed"); throw new IOException("Kurulum geri alınamadı. Yedek dosyalar burada korundu: " + backup, new AggregateException(failure, rollback)); }
            }
            if (Directory.Exists(stage)) Directory.Delete(stage, true);
            if (stopTray) Log(changed ? "failed-rolled-back" : "failed-before-commit");
            throw;
        }
        if (Directory.Exists(stage)) Directory.Delete(stage, true);
        bool ready = !launch || Launch(destination);
        if (stopTray) Log(ready ? "committed" : "committed-launch-not-ready");
        return ready;
        } finally { if (ownsAccountOperation) accountOperation.ReleaseMutex(); if (accountOperation != null) accountOperation.Dispose(); }
    }

    internal static bool Launch(string app)
    {
        string name = @"Local\ClaudeAccountSwitcherTrayReady-" + WindowsIdentity.GetCurrent().User.Value;
        using (var ready = new EventWaitHandle(false, EventResetMode.ManualReset, name))
        {
            ready.Reset();
            var info = new ProcessStartInfo(PowerShellPath, "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + Path.Combine(app, "Claude-Tray.ps1") + "\" -QuietStartup");
            info.WindowStyle = ProcessWindowStyle.Hidden; info.UseShellExecute = false; info.CreateNoWindow = true;
            try { using (var process = Process.Start(info)) { return ready.WaitOne(15000) && !process.HasExited; } }
            catch (Win32Exception) { return false; }
        }
    }
    internal static string PowerShellPath { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), @"System32\WindowsPowerShell\v1.0\powershell.exe"); } }
    internal static string TrayArguments(string app) { return "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + Path.Combine(app, "Claude-Tray.ps1") + "\" -QuietStartup"; }

    private static void RemoveFiles(string directory)
    {
        // Only known application files are removed; accounts and extra user files stay.
        foreach (string name in AppFiles.Concat(new[] { "Uninstall.exe" }))
        {
            string path = Path.Combine(directory, name); if (File.Exists(path)) File.Delete(path);
        }
        if (Directory.Exists(directory) && !Directory.EnumerateFileSystemEntries(directory).Any()) Directory.Delete(directory);
    }

    private static void Uninstall()
    {
        if (MessageBox.Show("Hesap seçici kaldırılsın mı? Kayıtlı hesapların ve Claude oturumun korunacak.", "Claude Hesap Seçici", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
        StopOwnedTray();
        string generation;
        using (RegistryKey key = Registry.CurrentUser.OpenSubKey(UninstallKey)) { generation = key == null ? null : key.GetValue("InstallGeneration") as string; }
        if (string.IsNullOrEmpty(generation)) throw new InvalidOperationException("Kurulum kaydı bulunamadı. Önce güncel sürümü yeniden kurun.");
        using (Process helper = StartCleanup(AppDir, UninstallKey, generation, Process.GetCurrentProcess().Id, true)) { }
    }
    private static string PSQuote(string value) { return "'" + value.Replace("'", "''") + "'"; }
    private static Process StartCleanup(string app, string registry, string generation, int parent, bool showUi)
    {
        // Use the installed Windows host: some policies deny executing binaries from TEMP.
        var script = new System.Text.StringBuilder();
        script.AppendLine("$ErrorActionPreference='Stop';$held=$false;$authHeld=$false;$mutex=$null;$auth=$null");
        script.AppendLine("$app=[IO.Path]::GetFullPath(" + PSQuote(app) + ");$reg=" + PSQuote(registry) + ";$generation=" + PSQuote(generation));
        script.AppendLine("try {");
        if (parent > 0) script.AppendLine("try{$parentProcess=[Diagnostics.Process]::GetProcessById(" + parent + ");try{if(-not $parentProcess.WaitForExit(15000)){throw 'Previous uninstaller is still running'}}finally{$parentProcess.Dispose()}}catch [ArgumentException]{}");
        script.AppendLine("$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;$mutex=[Threading.Mutex]::new($false,('Local\\ClaudeAccountSwitcherSetup-'+$sid));try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true};if(-not $held){throw 'Another setup is running'}");
        script.AppendLine("$key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($reg);try{if(-not $key -or [string]$key.GetValue('InstallGeneration') -cne $generation){throw 'Install generation changed; uninstall stopped'}}finally{if($key){$key.Dispose()}}");
        script.AppendLine("$auth=[Threading.Mutex]::new($false,('Local\\ClaudeAccountSwitcher-'+$sid));try{$authHeld=$auth.WaitOne(0)}catch [Threading.AbandonedMutexException]{$authHeld=$true};if(-not $authHeld){throw 'An account operation is running'}");
        script.AppendLine("$files=@(" + string.Join(",", AppFiles.Concat(new[] { "Uninstall.exe" }).Select(PSQuote)) + ")");
        script.AppendLine("foreach($name in $files){$path=[IO.Path]::GetFullPath([IO.Path]::Combine($app,$name));if(-not $path.StartsWith($app.TrimEnd([char]92)+[char]92,[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid owned path'};if([IO.File]::Exists($path)){[IO.File]::Delete($path)}}");
        script.AppendLine("if([IO.Directory]::Exists($app) -and -not [IO.Directory]::EnumerateFileSystemEntries($app).GetEnumerator().MoveNext()){[IO.Directory]::Delete($app)}");
        script.AppendLine("$shell=$null;try{$shell=New-Object -ComObject WScript.Shell;foreach($folder in @([Environment]::GetFolderPath('Startup'),[Environment]::GetFolderPath('DesktopDirectory'))){$path=Join-Path $folder 'Claude Hesap Secici.lnk';if(-not [IO.File]::Exists($path)){continue};$link=$null;try{$link=$shell.CreateShortcut($path);$owned=($link.TargetPath -ieq " + PSQuote(PowerShellPath) + " -and $link.Arguments -ceq " + PSQuote(TrayArguments(app)) + ") -or ($link.TargetPath -ieq " + PSQuote(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "wscript.exe")) + " -and $link.Arguments -ceq " + PSQuote("\"" + Path.Combine(app, "Claude-Tray.vbs") + "\"") + ");if($owned){[IO.File]::Delete($path)}}finally{if($link){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)}}}}finally{if($shell){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}}");
        script.AppendLine("[Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($reg,$false)");
        if (showUi) script.AppendLine("Add-Type -AssemblyName System.Windows.Forms;[void][Windows.Forms.MessageBox]::Show('Uygulama kaldırıldı. Kayıtlı hesapların korundu.','Claude Hesap Seçici')");
        script.AppendLine("} catch {");
        if (showUi) script.AppendLine("Add-Type -AssemblyName System.Windows.Forms;[void][Windows.Forms.MessageBox]::Show('Kaldırma tamamlanamadı. Kayıtlı hesapların korundu; kurulumu yeniden açıp tekrar deneyin.','Claude Hesap Seçici')");
        script.AppendLine("exit 1 } finally {if($authHeld){$auth.ReleaseMutex()};if($auth){$auth.Dispose()};if($held){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()}};exit 0");
        string encoded = Convert.ToBase64String(System.Text.Encoding.Unicode.GetBytes(script.ToString()));
        return Process.Start(new ProcessStartInfo(PowerShellPath, "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand " + encoded) { UseShellExecute = false, WindowStyle = ProcessWindowStyle.Hidden, CreateNoWindow = true });
    }
    private static bool CleanupGenerationMatches(string registry, string generation)
    { using (RegistryKey key = Registry.CurrentUser.OpenSubKey(registry)) { return key != null && (string)key.GetValue("InstallGeneration") == generation; } }

    private static void SelfTest()
    {
        string root = Path.Combine(Path.GetTempPath(), "ClaudeSetupTest-" + Guid.NewGuid().ToString("N"));
        string registry = @"Software\ClaudeAccountSwitcher\SetupTests\" + Guid.NewGuid().ToString("N");
        try
        {
            string app = Path.Combine(root, "app space \u00dc"), accounts = Path.Combine(root, "accounts"), startup = Path.Combine(root, "startup");
            Directory.CreateDirectory(accounts); File.WriteAllText(Path.Combine(accounts, "sentinel"), "preserve");
            string preferences = Path.Combine(root, "preferences.json"); File.WriteAllText(preferences, "{\"Favorites\":[\"fixture\"],\"AlertsEnabled\":false}");
            byte[] preferenceBaseline = File.ReadAllBytes(preferences);
            Install(app, startup, null, registry, false, false);
            if (AppFiles.Any(name => !File.Exists(Path.Combine(app, name)))) throw new Exception("Missing installed asset");
            if (!File.Exists(Path.Combine(startup, "Claude Hesap Secici.lnk"))) throw new Exception("Missing shortcut");
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(registry)) if ((string)key.GetValue("UninstallString") != "\"" + Path.Combine(app, "Uninstall.exe") + "\" /uninstall") throw new Exception("Uninstall quoting wrong");
            File.WriteAllText(Path.Combine(app, "README.md"), "old-install-sentinel");
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(registry, true)) { key.SetValue("DisplayVersion", "old-version"); key.SetValue("InstallGeneration", "old-generation"); }
            var baseline = AppFiles.Concat(new[] { "Uninstall.exe" }).ToDictionary(name => name, name => File.ReadAllBytes(Path.Combine(app, name)));
            byte[] oldLink = File.ReadAllBytes(Path.Combine(startup, "Claude Hesap Secici.lnk"));
            foreach (string point in new[] { "stage", "files", "shortcuts", "registry" })
            {
                bool failed = false;
                try { Install(app, startup, null, registry, false, false, point); } catch (IOException) { failed = true; }
                if (!failed) throw new Exception("Fault injection did not fail: " + point);
                foreach (var file in baseline) if (!File.ReadAllBytes(Path.Combine(app, file.Key)).SequenceEqual(file.Value)) throw new Exception("Rollback changed owned file: " + point);
                if (!File.ReadAllBytes(Path.Combine(startup, "Claude Hesap Secici.lnk")).SequenceEqual(oldLink)) throw new Exception("Rollback changed shortcut");
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(registry)) if ((string)key.GetValue("DisplayVersion") != "old-version" || (string)key.GetValue("InstallGeneration") != "old-generation") throw new Exception("Rollback changed registry");
                if (!File.ReadAllBytes(preferences).SequenceEqual(preferenceBaseline)) throw new Exception("Rollback changed preferences");
            }
            if (!CleanupGenerationMatches(registry, "old-generation") || CleanupGenerationMatches(registry, "new-generation") || CleanupGenerationMatches(registry + "-missing", "old-generation")) throw new Exception("Cleanup generation race protection failed");
            Install(app, startup, null, registry, false, false);
            if (File.ReadAllText(Path.Combine(app, "README.md")) == "old-install-sentinel") throw new Exception("Successful upgrade did not commit");
            if (!File.ReadAllBytes(preferences).SequenceEqual(preferenceBaseline)) throw new Exception("Upgrade changed preferences");
            if (CleanupGenerationMatches(registry, "old-generation")) throw new Exception("Old cleanup accepted newer install");
            foreach (string flag in new[] { "/unknown", "/startup /no-startup" })
            {
                using (var process = Process.Start(new ProcessStartInfo(Application.ExecutablePath, "/quiet " + flag) { UseShellExecute = false, WindowStyle = ProcessWindowStyle.Hidden }))
                { if (!process.WaitForExit(10000) || process.ExitCode != 1) throw new Exception("Quiet invalid-options test did not exit without a dialog"); }
            }
            using (var lockTest = new Mutex(false, @"Local\ClaudeAccountSwitcherSetup-" + WindowsIdentity.GetCurrent().User.Value))
            {
                bool locked = false; try { locked = lockTest.WaitOne(0); } catch (AbandonedMutexException) { locked = true; }
                if (!locked) throw new Exception("Another setup is active; concurrency test skipped safely");
                try {
                    using (var process = Process.Start(new ProcessStartInfo(Application.ExecutablePath, "/quiet /no-launch") { UseShellExecute = false, WindowStyle = ProcessWindowStyle.Hidden }))
                    { if (!process.WaitForExit(10000) || process.ExitCode != 1) throw new Exception("Concurrent quiet setup did not reject operation"); }
                } finally { lockTest.ReleaseMutex(); }
            }
            File.WriteAllText(Path.Combine(app, "user-note.txt"), "preserve");
            using (var cleanup = StartCleanup(app, registry, "old-generation", 0, false))
            { if (!cleanup.WaitForExit(15000) || cleanup.ExitCode != 1 || !File.Exists(Path.Combine(app, "README.md"))) throw new Exception("Stale native cleanup did not preserve newer installation"); }
            string currentGeneration; using (RegistryKey key = Registry.CurrentUser.OpenSubKey(registry)) currentGeneration = (string)key.GetValue("InstallGeneration");
            using (var cleanup = StartCleanup(app, registry, currentGeneration, 0, false))
            { if (!cleanup.WaitForExit(15000) || cleanup.ExitCode != 0 || File.Exists(Path.Combine(app, "README.md"))) throw new Exception("Native PowerShell cleanup failed"); }
            if (!File.Exists(Path.Combine(accounts, "sentinel")) || !File.Exists(Path.Combine(app, "user-note.txt"))) throw new Exception("User data removed");
            if (!File.ReadAllBytes(preferences).SequenceEqual(preferenceBaseline)) throw new Exception("Uninstall changed preferences");
            Console.WriteLine("PASS: clean/upgrade, Unicode paths, owned assets, stage/files/shortcut/registry rollback, cleanup generation race, user data preservation.");
        }
        finally { Registry.CurrentUser.DeleteSubKeyTree(registry, false); if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
}

internal sealed class SetupWizard : Form
{
    private readonly Color teal = Color.FromArgb(217, 119, 87), ink = Color.FromArgb(61, 58, 54), paper = Color.FromArgb(250, 249, 245);
    private readonly List<Font> ownedFonts = new List<Font>();
    private Bitmap ownedLogo;
    private readonly Label title, subtitle, detail;
    private readonly CheckBox startup, desktop, launch;
    private readonly WarmRoundedButton next, cancel;
    private readonly ProgressBar progress;
    private bool done;
    private bool installing;
    internal SetupWizard()
    {
        SuspendLayout();
        Text = "Claude Hesap Seçici · Kurulum"; ClientSize = new Size(600, 480); StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog; MaximizeBox = false; MinimizeBox = false; BackColor = paper;
        AutoScaleDimensions = new SizeF(96, 96); AutoScaleMode = AutoScaleMode.Dpi; Font = OwnedFont("Segoe UI", 10, FontStyle.Regular);
        using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("AppIcon.ico")) Icon = new Icon(stream);
        Bitmap logo;
        using (Stream image = Assembly.GetExecutingAssembly().GetManifestResourceStream("AppLogo.png")) using (var bitmap = new Bitmap(image)) logo = (Bitmap)bitmap.Clone();
        ownedLogo = logo;
        var picture = new PictureBox { Location = new Point(28, 30), Size = new Size(64, 64), Image = logo, SizeMode = PictureBoxSizeMode.Zoom }; Controls.Add(picture);
        title = Label("Direksiyon sende.", 112, 27, 448, 82, 23, true);
        var version = Label("v" + SetupProgram.Version, 488, 10, 80, 20, 8, false); version.ForeColor = Color.FromArgb(129,119,110); version.TextAlign = ContentAlignment.TopRight;
        subtitle = Label("Sahne senin. Claude hesaplarını tek tıkla değiştir.", 28, 133, 540, 28, 12, false);
        detail = Label("Bildirim alanında küçük bir yardımcı.\nKayıtlı hesapların ve Claude geçmişin korunur.\nYalnızca senin Windows kullanıcına kurulur; yönetici gerekmez.", 28, 176, 540, 89, 10, false);
        startup = new CheckBox { Text = "Windows açılınca hazır olsun", Checked = SetupProgram.StartupEnabled, Location = new Point(28, 276), Size = new Size(490, 28), ForeColor = ink };
        desktop = new CheckBox { Text = "Masaüstüne bir kısayol ekle", Checked = SetupProgram.DesktopEnabled, Location = new Point(28, 312), Size = new Size(490, 28), ForeColor = ink };
        launch = new CheckBox { Text = "Kurulum bitince sahneye çıksın", Checked = true, Location = new Point(28, 348), Size = new Size(490, 28), ForeColor = ink }; Controls.Add(startup); Controls.Add(desktop); Controls.Add(launch);
        progress = new ProgressBar { Location = new Point(28, 389), Size = new Size(540, 9), Style = ProgressBarStyle.Marquee, Visible = false }; Controls.Add(progress);
        next = Button("Kurulumu başlat", 366, 420, 202, true); next.Click += Next;
        cancel = Button("Vazgeç", 28, 420, 124, false); cancel.Click += (s, e) => Close();
        AcceptButton = next; CancelButton = cancel;
        FormClosing += (s, e) => { if (installing) e.Cancel = true; };
        ResumeLayout(true);
    }
    private Label Label(string text, int x, int y, int w, int h, float size, bool bold)
    { var label = new Label { Text = text, Location = new Point(x, y), Size = new Size(w, h), ForeColor = ink, Font = OwnedFont(size >= 18 ? "Georgia" : "Segoe UI", size, bold && size < 18 ? FontStyle.Bold : FontStyle.Regular) }; Controls.Add(label); return label; }
    private WarmRoundedButton Button(string text, int x, int y, int width, bool primary)
    {
        var button = new WarmRoundedButton { Text = text, Location = new Point(x, y), Size = new Size(width, 40), FlatStyle = FlatStyle.Flat, BackColor = primary ? teal : Color.FromArgb(243, 230, 221), ForeColor = primary ? Color.White : ink, Font = OwnedFont("Segoe UI", 10, FontStyle.Bold), Cursor = Cursors.Hand };
        button.FlatAppearance.BorderSize = 0; button.FlatAppearance.MouseOverBackColor = primary ? Color.FromArgb(193, 95, 60) : Color.FromArgb(238, 223, 206); Controls.Add(button); return button;
    }
    private Font OwnedFont(string family, float size, FontStyle style) { var font = new Font(family, size, style); ownedFonts.Add(font); return font; }
    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (disposing) { foreach (Font font in ownedFonts) font.Dispose(); ownedFonts.Clear(); if (ownedLogo != null) { ownedLogo.Dispose(); ownedLogo = null; } if (Icon != null) Icon.Dispose(); }
    }
    private void Next(object sender, EventArgs args)
    {
        if (done) { Close(); return; }
        installing = true; next.Enabled = false; cancel.Enabled = false; startup.Enabled = false; desktop.Enabled = false; launch.Enabled = false; progress.Visible = true; detail.Text = "Sahne kuruluyor. Dosyalar önce doğrulanıyor.\nHesapların ve Claude oturumların korunuyor.";
        bool auto = startup.Checked, shortcut = desktop.Checked, start = launch.Checked;
        var worker = new BackgroundWorker { WorkerReportsProgress = true };
        worker.ProgressChanged += (s,e) => detail.Text = (string)e.UserState;
        worker.DoWork += (s, e) => e.Result = SetupProgram.Install(SetupProgram.AppDir, auto ? Environment.GetFolderPath(Environment.SpecialFolder.Startup) : null, shortcut ? Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory) : null, SetupProgram.UninstallKey, start, true, null, text => worker.ReportProgress(0, text));
        worker.RunWorkerCompleted += (s, e) =>
        {
            try {
            installing = false; progress.Visible = false; next.Enabled = true; cancel.Enabled = true;
            if (e.Error != null) { MessageBox.Show(e.Error.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error); startup.Enabled = true; desktop.Enabled = true; launch.Enabled = true; detail.Text = "Kurulum tamamlanamadı. Hata ayrıntısını kontrol et.\nHesap kayıtların korunur."; return; }
            bool ready = (bool)e.Result;
            Complete(start, ready);
            } finally { worker.Dispose(); }
        };
        worker.RunWorkerAsync();
    }
    private void Complete(bool start, bool ready)
    {
        done = true; title.Text = "Kurulum tamam."; subtitle.Text = start && ready ? "Hesap seçici bildirim alanında hazır." : "Kurulum tamamlandı. Dosyalar yerinde.";
        detail.Text = !start ? "Hazır olduğunda kısayoldan veya uygulama klasöründen aç.\nHesapların yerinde. Aceleye gerek yok." : ready ? "Saatin yanındaki simgeye tıkla. Simge gizliyse yukarı oka bak.\nİlk hesabını kaydet veya yeni hesap ekle.\nArtık normal claude komutuyla yola devam." : "Uygulama kuruldu, ancak başlangıç doğrulanamadı.\nClaude-Tray.ps1 dosyasını PowerShell -STA ile açabilirsin.\nKurumsal PowerShell politikanı kontrol et.";
        startup.Visible = false; desktop.Visible = false; launch.Visible = false; cancel.Visible = false; next.Text = "Tamam, hazırım";
    }
    internal void Render(string path, bool completed = false)
    {
        if (completed) Complete(true, true);
        StartPosition = FormStartPosition.Manual; Location = new Point(-32000, -32000); Show(); Application.DoEvents();
        using (var bitmap = new Bitmap(Width, Height)) { DrawToBitmap(bitmap, new Rectangle(0, 0, Width, Height)); bitmap.Save(path, System.Drawing.Imaging.ImageFormat.Png); }
        Hide();
    }
}
