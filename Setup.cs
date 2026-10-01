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

internal static class SetupProgram
{
    internal const string Version = "1.5.0";
    internal const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\ClaudeAccountSwitcher";
    internal static readonly string AppDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ClaudeAccountSwitcher", "app");
    internal static readonly string[] AppFiles = { "AccountCore.ps1", "TraySupport.ps1", "TrayUI.ps1", "TrayRuntime.ps1", "VisualControls.dll", "UsageCore.ps1", "Usage-Collector.ps1", "Claude-Hesap.ps1", "Claude-Hesap.bat", "Claude-Tray.ps1", "Claude-Tray.vbs", "Claude-Switch.ico", "README.md", "LICENSE" };
    [DllImport("user32.dll", SetLastError = true)] private static extern bool PostThreadMessage(uint id, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();

    [STAThread]
    private static int Main(string[] args)
    {
        SetProcessDPIAware(); Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
        Mutex operation = null; bool acquired = false;
        try
        {
            if (args.Length > 0 && args[0] == "/test") { SelfTest(); return 0; }
            if (args.Length > 0 && args[0] == "/preview") { using (var wizard = new SetupWizard()) wizard.Render(args[1]); return 0; }
            if (args.Length > 0 && args[0] == "/cleanup")
            {
                if (args.Length != 2) throw new InvalidOperationException("Geçersiz kaldırma isteği.");
                int parent = int.Parse(args[1]); try { if (!Process.GetProcessById(parent).WaitForExit(15000)) throw new InvalidOperationException("Önceki kaldırma işlemi kapanmadı."); } catch (ArgumentException) { }
                operation = new Mutex(false, @"Local\ClaudeAccountSwitcherSetup-" + WindowsIdentity.GetCurrent().User.Value);
                try { acquired = operation.WaitOne(0); } catch (AbandonedMutexException) { acquired = true; }
                if (!acquired) throw new InvalidOperationException("Başka bir kurulum işlemi devam ediyor.");
                RemoveFiles(AppDir); Registry.CurrentUser.DeleteSubKeyTree(UninstallKey, false); MessageBox.Show("Uygulama kaldırıldı. Kayıtlı hesapların korundu.", "Claude Hesap Seçici"); return 0;
            }
            operation = new Mutex(false, @"Local\ClaudeAccountSwitcherSetup-" + WindowsIdentity.GetCurrent().User.Value);
            try { acquired = operation.WaitOne(0); } catch (AbandonedMutexException) { acquired = true; }
            if (!acquired) throw new InvalidOperationException("Başka bir kurulum işlemi devam ediyor.");
            if (args.Length > 0 && args[0] == "/uninstall") { Uninstall(); return 0; }
            if (args.Length > 0 && args[0] == "/install") { Install(AppDir, Environment.GetFolderPath(Environment.SpecialFolder.Startup), null, UninstallKey, true, true); return 0; }
            Application.Run(new SetupWizard()); return 0;
        }
        catch (Exception ex) { if (args.Length > 0 && args[0] == "/test") { Console.Error.WriteLine(ex); } else if (args.Length > 1 && args[0] == "/preview") { File.WriteAllText(args[1] + ".error.txt", ex.ToString()); } else MessageBox.Show(ex.Message, "Claude Hesap Seçici", MessageBoxButtons.OK, MessageBoxIcon.Error); return 1; }
        finally { if (acquired) operation.ReleaseMutex(); if (operation != null) operation.Dispose(); }
    }

    internal static void StopOwnedTray()
    {
        string sid = WindowsIdentity.GetCurrent().User.Value;
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
            catch (WaitHandleCannotBeOpenedException) { return; }
            using (existing)
            {
                bool acquired = false;
                try { acquired = existing.WaitOne(0); } catch (AbandonedMutexException) { acquired = true; }
                if (acquired) { existing.ReleaseMutex(); return; }
            }
            Thread.Sleep(100);
        }
        throw new InvalidOperationException("Hesap seçici güncelleme için kapanamadı. Bildirim alanındaki uygulamadan Çıkış seçip tekrar deneyin. Claude oturumlarına dokunulmadı.");
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
            shortcut.TargetPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "wscript.exe");
            shortcut.Arguments = "\"" + Path.Combine(app, "Claude-Tray.vbs") + "\"";
            shortcut.WorkingDirectory = app; shortcut.IconLocation = Path.Combine(app, "Claude-Switch.ico") + ",0"; shortcut.Save();
        }
        finally { Marshal.FinalReleaseComObject(shortcut); Marshal.FinalReleaseComObject(shell); }
    }

    internal static void Install(string destination, string startup, string desktop, string registryKey, bool launch, bool stopTray)
    {
        if (stopTray) StopOwnedTray();
        Extract(destination);
        string uninstaller = Path.Combine(destination, "Uninstall.exe");
        File.Copy(Application.ExecutablePath, uninstaller, true);
        if (startup != null) Shortcut(startup, destination);
        else
        {
            string old = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup), "Claude Hesap Secici.lnk");
            if (stopTray && File.Exists(old)) File.Delete(old);
        }
        if (desktop != null) Shortcut(desktop, destination);
        using (RegistryKey key = Registry.CurrentUser.CreateSubKey(registryKey))
        {
            key.SetValue("DisplayName", "Claude Hesap Seçici"); key.SetValue("DisplayVersion", Version);
            key.SetValue("Publisher", "Claude Account Switcher team tool"); key.SetValue("InstallLocation", destination);
            key.SetValue("DisplayIcon", Path.Combine(destination, "Claude-Switch.ico"));
            key.SetValue("UninstallString", "\"" + uninstaller + "\" /uninstall");
            key.SetValue("NoModify", 1, RegistryValueKind.DWord); key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
        }
        if (launch) Launch(destination);
    }

    internal static void Launch(string app)
    {
        var info = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "wscript.exe"), "\"" + Path.Combine(app, "Claude-Tray.vbs") + "\"");
        info.WindowStyle = ProcessWindowStyle.Hidden; Process.Start(info);
    }

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
        foreach (string folder in new[] { Environment.GetFolderPath(Environment.SpecialFolder.Startup), Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory) })
        { string path = Path.Combine(folder, "Claude Hesap Secici.lnk"); if (File.Exists(path)) File.Delete(path); }
        string helper = Path.Combine(Path.GetTempPath(), "ClaudeSwitcher-Uninstall-" + Guid.NewGuid().ToString("N") + ".exe");
        File.Copy(Application.ExecutablePath, helper);
        Process.Start(new ProcessStartInfo(helper, "/cleanup " + Process.GetCurrentProcess().Id) { UseShellExecute = false });
    }

    private static void SelfTest()
    {
        string root = Path.Combine(Path.GetTempPath(), "ClaudeSetupTest-" + Guid.NewGuid().ToString("N"));
        string registry = @"Software\ClaudeAccountSwitcher\SetupTests\" + Guid.NewGuid().ToString("N");
        try
        {
            string app = Path.Combine(root, "app"), accounts = Path.Combine(root, "accounts"), startup = Path.Combine(root, "startup");
            Directory.CreateDirectory(accounts); File.WriteAllText(Path.Combine(accounts, "sentinel"), "preserve");
            Install(app, startup, null, registry, false, false);
            if (AppFiles.Any(name => !File.Exists(Path.Combine(app, name)))) throw new Exception("Missing installed asset");
            if (!File.Exists(Path.Combine(startup, "Claude Hesap Secici.lnk"))) throw new Exception("Missing shortcut");
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(registry)) if ((string)key.GetValue("UninstallString") != "\"" + Path.Combine(app, "Uninstall.exe") + "\" /uninstall") throw new Exception("Uninstall quoting wrong");
            File.WriteAllText(Path.Combine(app, "user-note.txt"), "preserve"); RemoveFiles(app);
            if (!File.Exists(Path.Combine(accounts, "sentinel")) || !File.Exists(Path.Combine(app, "user-note.txt"))) throw new Exception("User data removed");
            File.WriteAllText(Path.Combine(root, "PASS.txt"), "Setup install, shortcut, isolated HKCU registration, uninstall and data preservation passed.");
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
    private readonly CheckBox startup, desktop;
    private readonly WarmRoundedButton next, cancel;
    private readonly ProgressBar progress;
    private bool done;
    private bool installing;
    internal SetupWizard()
    {
        SuspendLayout();
        Text = "Claude Hesap Seçici · Kurulum"; ClientSize = new Size(600, 440); StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog; MaximizeBox = false; MinimizeBox = false; BackColor = paper;
        AutoScaleDimensions = new SizeF(96, 96); AutoScaleMode = AutoScaleMode.Dpi; Font = OwnedFont("Segoe UI", 10, FontStyle.Regular);
        using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("AppIcon.ico")) Icon = new Icon(stream);
        Bitmap logo;
        using (Stream image = Assembly.GetExecutingAssembly().GetManifestResourceStream("AppLogo.png")) using (var bitmap = new Bitmap(image)) logo = (Bitmap)bitmap.Clone();
        ownedLogo = logo;
        var picture = new PictureBox { Location = new Point(28, 30), Size = new Size(64, 64), Image = logo, SizeMode = PictureBoxSizeMode.Zoom }; Controls.Add(picture);
        title = Label("Hesaplar hazır.", 112, 27, 448, 82, 23, true);
        subtitle = Label("Sahne senin. Claude hesaplarını tek tıkla değiştir.", 28, 133, 540, 28, 12, false);
        detail = Label("Bildirim alanında küçük bir yardımcı.\nKayıtlı hesapların ve Claude geçmişin korunur.\nYalnızca senin Windows kullanıcına kurulur; yönetici gerekmez.", 28, 176, 540, 89, 10, false);
        startup = new CheckBox { Text = "Windows açılınca hazır olsun", Checked = true, Location = new Point(28, 276), Size = new Size(390, 28), ForeColor = ink };
        desktop = new CheckBox { Text = "Masaüstüne bir kısayol ekle", Location = new Point(28, 312), Size = new Size(390, 28), ForeColor = ink }; Controls.Add(startup); Controls.Add(desktop);
        progress = new ProgressBar { Location = new Point(28, 346), Size = new Size(540, 9), Style = ProgressBarStyle.Marquee, Visible = false }; Controls.Add(progress);
        next = Button("Kur ve başlat", 366, 380, 202, true); next.Click += Next;
        cancel = Button("Vazgeç", 28, 380, 124, false); cancel.Click += (s, e) => Close();
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
        installing = true; next.Enabled = false; cancel.Enabled = false; startup.Enabled = false; desktop.Enabled = false; progress.Visible = true; detail.Text = "Uygulama hazırlanıyor. Claude oturumlarına dokunulmuyor.";
        bool auto = startup.Checked, shortcut = desktop.Checked;
        var worker = new BackgroundWorker();
        worker.DoWork += (s, e) => SetupProgram.Install(SetupProgram.AppDir, auto ? Environment.GetFolderPath(Environment.SpecialFolder.Startup) : null, shortcut ? Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory) : null, SetupProgram.UninstallKey, true, true);
        worker.RunWorkerCompleted += (s, e) =>
        {
            installing = false; progress.Visible = false; next.Enabled = true; cancel.Enabled = true;
            if (e.Error != null) { MessageBox.Show(e.Error.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error); startup.Enabled = true; desktop.Enabled = true; detail.Text = "Kurulum tamamlanamadı. Tekrar deneyebilirsin."; return; }
            done = true; title.Text = "Direksiyon sende."; subtitle.Text = "Hesap seçici bildirim alanında hazır.";
            detail.Text = "Saatin yanındaki simgeye tıkla. Simge gizliyse yukarı oka bak.\nİlk hesabını kaydet veya yeni hesap ekle.\nArtık normal claude komutuyla yola devam."; startup.Visible = false; desktop.Visible = false; cancel.Visible = false; next.Text = "Hadi başlayalım";
        };
        worker.RunWorkerAsync();
    }
    internal void Render(string path)
    {
        StartPosition = FormStartPosition.Manual; Location = new Point(-32000, -32000); Show(); Application.DoEvents();
        using (var bitmap = new Bitmap(Width, Height)) { DrawToBitmap(bitmap, new Rectangle(0, 0, Width, Height)); bitmap.Save(path, System.Drawing.Imaging.ImageFormat.Png); }
        Hide();
    }
}
