using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public sealed class AccountHotkeyEventArgs : EventArgs
{
    public int Id { get; private set; }
    public AccountHotkeyEventArgs(int id) { Id = id; }
}

// Message-only window on the existing WinForms UI thread; no hook or worker.
public sealed class AccountHotkeyHost : NativeWindow, IDisposable
{
    [DllImport("user32.dll", SetLastError = true)] private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool UnregisterHotKey(IntPtr window, int id);
    [DllImport("user32.dll")] private static extern short GetKeyState(int key);
    public static bool WindowsKeyDown() { return GetKeyState(0x5B) < 0 || GetKeyState(0x5C) < 0; }
    private readonly HashSet<int> registered = new HashSet<int>();
    private bool disposed;
    public event EventHandler<AccountHotkeyEventArgs> Fired;
    public AccountHotkeyHost() { CreateHandle(new CreateParams { Caption = "ClaudeAccountSwitcherHotkeys", Parent = new IntPtr(-3) }); }
    public bool Register(int id, int modifiers, int key)
    {
        if (disposed || registered.Contains(id)) return false;
        if (!RegisterHotKey(Handle, id, (uint)(modifiers | 0x4000), (uint)key)) return false;
        registered.Add(id); return true;
    }
    public bool Unregister(int id)
    {
        if (!registered.Contains(id)) return true;
        if (!UnregisterHotKey(Handle, id)) return false;
        registered.Remove(id); return true;
    }
    protected override void WndProc(ref Message message)
    {
        if (message.Msg == 0x0312 && registered.Contains(message.WParam.ToInt32()))
        {
            var callback = Fired;
            if (callback != null) callback(this, new AccountHotkeyEventArgs(message.WParam.ToInt32()));
        }
        base.WndProc(ref message);
    }
    public void Dispose()
    {
        if (disposed) return;
        foreach (int id in new List<int>(registered)) UnregisterHotKey(Handle, id);
        registered.Clear(); DestroyHandle(); disposed = true;
    }
}
