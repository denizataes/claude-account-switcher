using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public sealed class WarmButtonAppearance
{
    public int BorderSize { get; set; }
    public Color BorderColor { get; set; }
    public Color MouseOverBackColor { get; set; }
    public Color MouseDownBackColor { get; set; }
}
public sealed class WarmRoundedButton : Control, IButtonControl
{
    private bool pressed;
    public FlatStyle FlatStyle { get; set; }
    public ContentAlignment TextAlign { get; set; }
    public WarmButtonAppearance FlatAppearance { get; private set; }
    public DialogResult DialogResult { get; set; }
    public int CornerRadius { get; set; }
    public WarmRoundedButton() { CornerRadius = 12; FlatAppearance = new WarmButtonAppearance(); TabStop = true; AccessibleRole = AccessibleRole.PushButton; SetStyle(ControlStyles.Selectable | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint, true); }
    public void NotifyDefault(bool value) { Invalidate(); }
    public void PerformClick() { if (Enabled) OnClick(EventArgs.Empty); }
    protected override void OnClick(EventArgs e) { base.OnClick(e); if (DialogResult != DialogResult.None && FindForm() != null) FindForm().DialogResult = DialogResult; }
    protected override void OnMouseDown(MouseEventArgs e) { if(e.Button == MouseButtons.Left){Focus();pressed=true;Invalidate();} base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e) { pressed=false;Invalidate();base.OnMouseUp(e); }
    protected override void OnKeyDown(KeyEventArgs e) { if(e.KeyCode==Keys.Space){pressed=true;Invalidate();e.Handled=true;} base.OnKeyDown(e); }
    protected override void OnKeyUp(KeyEventArgs e) { if(e.KeyCode==Keys.Space){bool activate=pressed;pressed=false;if(activate)PerformClick();Invalidate();e.Handled=true;} base.OnKeyUp(e); }
    protected override bool ProcessDialogKey(Keys keyData) { if(keyData==Keys.Enter){PerformClick();return true;}return base.ProcessDialogKey(keyData); }
    protected override void OnGotFocus(EventArgs e){Invalidate();base.OnGotFocus(e);}
    protected override void OnLostFocus(EventArgs e){pressed=false;Invalidate();base.OnLostFocus(e);}
    protected override void OnMouseCaptureChanged(EventArgs e){if(!Capture){pressed=false;Invalidate();}base.OnMouseCaptureChanged(e);}
    protected override void OnMouseEnter(EventArgs e) { Invalidate(true); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { Invalidate(true); base.OnMouseLeave(e); }
    protected override void OnControlAdded(ControlEventArgs e){base.OnControlAdded(e);Watch(e.Control);}
    private void Watch(Control child){child.MouseEnter+=delegate{Invalidate(true);};child.MouseLeave+=delegate{Invalidate(true);};child.ControlAdded+=delegate(object s,ControlEventArgs e){Watch(e.Control);};foreach(Control c in child.Controls)Watch(c);}
    private bool CursorInside(){if(!IsHandleCreated)return false;Control control=this;while(control!=null){if(!control.ClientRectangle.Contains(control.PointToClient(Cursor.Position)))return false;control=control.Parent;}return true;}
    public Color SurfaceColor { get { bool hover=CursorInside();Color color=hover && Enabled && !FlatAppearance.MouseOverBackColor.IsEmpty ? FlatAppearance.MouseOverBackColor : BackColor; if(pressed)color=!FlatAppearance.MouseDownBackColor.IsEmpty ? FlatAppearance.MouseDownBackColor : Color.FromArgb((color.R*9+193)/10,(color.G*9+95)/10,(color.B*9+60)/10);return color;} }
    protected override void OnPaintBackground(PaintEventArgs e) { e.Graphics.Clear(WarmRegions.Background(Parent)); }
    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using (var path = WarmRegions.Path(Width - 1, Height - 1, CornerRadius))
        using (var brush = new SolidBrush(SurfaceColor))
        {
            e.Graphics.FillPath(brush, path);
            if (FlatAppearance.BorderSize > 0) using (var pen = new Pen(FlatAppearance.BorderColor, FlatAppearance.BorderSize)) e.Graphics.DrawPath(pen, path);
        }
        if (!string.IsNullOrEmpty(Text)) TextRenderer.DrawText(e.Graphics, Text, Font, ClientRectangle, Enabled ? ForeColor : SystemColors.GrayText, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
        if (Focused && ShowFocusCues) using(var path=WarmRegions.Path(Width-7,Height-7,CornerRadius)) using(var pen=new Pen(Color.FromArgb(193,95,60),1)){e.Graphics.TranslateTransform(3,3);e.Graphics.DrawPath(pen,path);e.Graphics.ResetTransform();}
    }
}
public static class WarmRegions
{
    public static Color Background(Control parent){while(parent!=null){var button=parent as WarmRoundedButton;if(button!=null)return button.SurfaceColor;if(parent.BackColor.A==255)return parent.BackColor;parent=parent.Parent;}return SystemColors.Control;}
    public static GraphicsPath Path(int width, int height, int radius)
    {
        var path = new GraphicsPath(); int diameter = Math.Max(1, Math.Min(radius * 2, Math.Min(width, height)));
        path.AddArc(0, 0, diameter, diameter, 180, 90); path.AddArc(width - diameter, 0, diameter, diameter, 270, 90);
        path.AddArc(width - diameter, height - diameter, diameter, diameter, 0, 90); path.AddArc(0, height - diameter, diameter, diameter, 90, 90); path.CloseFigure(); return path;
    }
    public static void Apply(Control control, int radius)
    {
        EventHandler resize = delegate
        {
            if (control.Width < 2 || control.Height < 2) return;
            using (var path = Path(control.Width, control.Height, radius)) { Region old = control.Region; control.Region = new Region(path); if (old != null) old.Dispose(); }
        };
        control.Resize += resize; resize(control, EventArgs.Empty);
        control.Disposed += delegate { if (control.Region != null) control.Region.Dispose(); };
    }
}
public sealed class WarmAvatar : Label
{
    public WarmAvatar() { SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint, true); }
    protected override void OnPaintBackground(PaintEventArgs e) { e.Graphics.Clear(WarmRegions.Background(Parent)); }
    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using (var brush = new SolidBrush(BackColor)) e.Graphics.FillEllipse(brush, 0, 0, Width - 1, Height - 1);
        TextRenderer.DrawText(e.Graphics, Text, Font, ClientRectangle, ForeColor, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
    }
}
public sealed class WarmRoundedPanel : Panel
{
    public WarmRoundedPanel() { SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint, true); }
    protected override void OnPaintBackground(PaintEventArgs e)
    {
        e.Graphics.Clear(WarmRegions.Background(Parent));
        if (Width < 2 || Height < 2) return;
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using (var path = WarmRegions.Path(Width - 1, Height - 1, 3)) using (var brush = new SolidBrush(BackColor)) e.Graphics.FillPath(brush, path);
    }
}
