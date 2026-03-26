using AutomatonDesigner.Models;
using AutomatonDesigner.Services;

namespace AutomatonDesigner.UI.Controls;

/// <summary>
/// MAUI GraphicsView drawable that renders automaton states as circles
/// and transitions as arrows.  Supports active-state highlighting.
/// </summary>
public sealed class AutomatonCanvasDrawable : IDrawable
{
    public AppViewModel? ViewModel { get; set; }

    const float StateRadius = 30f;

    // ── Drag state ──────────────────────────────────────────
    State? _dragState;
    float _dragOffsetX, _dragOffsetY;

    /// <summary>Hit-test on touch/click start — pick up a state if close enough.</summary>
    public void OnStartInteraction(PointF point)
    {
        _dragState = null;
        var vm = ViewModel;
        if (vm == null) return;

        foreach (var (state, pos) in vm.Layout)
        {
            float dx = point.X - (float)pos.X;
            float dy = point.Y - (float)pos.Y;
            if (dx * dx + dy * dy <= StateRadius * StateRadius)
            {
                _dragState = state;
                _dragOffsetX = dx;
                _dragOffsetY = dy;
                return;
            }
        }
    }

    /// <summary>Move the dragged state to follow the pointer.</summary>
    public void OnDragInteraction(PointF point)
    {
        if (_dragState == null || ViewModel == null) return;
        ViewModel.Layout[_dragState] = new Position(
            point.X - _dragOffsetX,
            point.Y - _dragOffsetY);
        ViewModel.RequestCanvasInvalidate();
    }

    /// <summary>Release the dragged state.</summary>
    public void OnEndInteraction() => _dragState = null;

    // Catppuccin Mocha colours
    static readonly Color BgColor        = Color.FromArgb("#11111b");
    static readonly Color StateFill      = Color.FromArgb("#313244");
    static readonly Color StateStroke    = Color.FromArgb("#cdd6f4");
    static readonly Color ActiveFill     = Color.FromArgb("#2d4a2e");
    static readonly Color ActiveStroke   = Color.FromArgb("#a6e3a1");
    static readonly Color AcceptRing     = Color.FromArgb("#f9e2af");
    static readonly Color StartArrow     = Color.FromArgb("#89b4fa");
    static readonly Color TransColor     = Color.FromArgb("#9399b2");
    static readonly Color TransText      = Color.FromArgb("#bac2de");
    static readonly Color LabelColor     = Color.FromArgb("#cdd6f4");
    static readonly Color GridColor      = Color.FromArgb("#1e1e2e");

    public void Draw(ICanvas canvas, RectF dirtyRect)
    {
        var vm = ViewModel;
        if (vm == null) return;

        var aut = vm.Automaton;
        var layout = vm.Layout;
        var active = vm.ActiveStates;

        // Background
        canvas.FillColor = BgColor;
        canvas.FillRectangle(dirtyRect);

        // Grid dots
        canvas.FillColor = GridColor;
        for (float gx = 20; gx < dirtyRect.Width; gx += 40)
            for (float gy = 20; gy < dirtyRect.Height; gy += 40)
                canvas.FillRectangle(gx, gy, 1, 1);

        if (aut == null || layout.Count == 0) return;

        // Draw transitions first (below states)
        foreach (var t in aut.Transitions)
            DrawTransition(canvas, aut, layout, t);

        // Draw states on top
        foreach (var s in aut.States)
        {
            if (!layout.TryGetValue(s, out var pos)) continue;
            bool isActive = active.Contains(s);
            bool isStart = s == aut.Start;
            bool isAccept = aut.Accept.Contains(s);
            DrawState(canvas, (float)pos.X, (float)pos.Y, s.Name, isStart, isAccept, isActive);
        }
    }

    void DrawState(ICanvas canvas, float x, float y, string name,
                   bool isStart, bool isAccept, bool isActive)
    {
        // Outer circle
        canvas.FillColor = isActive ? ActiveFill : StateFill;
        canvas.FillCircle(x, y, StateRadius);
        canvas.StrokeColor = isActive ? ActiveStroke : StateStroke;
        canvas.StrokeSize = 2;
        canvas.DrawCircle(x, y, StateRadius);

        // Accept: inner ring
        if (isAccept)
        {
            canvas.StrokeColor = isActive ? ActiveStroke : AcceptRing;
            canvas.StrokeSize = 2;
            canvas.DrawCircle(x, y, StateRadius - 5);
        }

        // Start arrow
        if (isStart)
        {
            float ax = x - StateRadius;
            canvas.StrokeColor = StartArrow;
            canvas.StrokeSize = 2;
            canvas.DrawLine(ax - 28, y, ax - 3, y);

            // Arrowhead
            var path = new PathF();
            path.MoveTo(ax - 3, y);
            path.LineTo(ax - 11, y - 5);
            path.LineTo(ax - 11, y + 5);
            path.Close();
            canvas.FillColor = StartArrow;
            canvas.FillPath(path);
        }

        // Label
        canvas.FontColor = isActive ? ActiveStroke : LabelColor;
        canvas.FontSize = 14;
        canvas.DrawString(name, x - StateRadius, y - 10, StateRadius * 2, 20,
            HorizontalAlignment.Center, VerticalAlignment.Center);
    }

    void DrawTransition(ICanvas canvas, Automaton aut,
                        Dictionary<State, Position> layout, Transition t)
    {
        if (!layout.TryGetValue(t.From, out var fromPos) ||
            !layout.TryGetValue(t.To, out var toPos)) return;

        string labelStr = t.Label switch
        {
            OnSymbol s => s.Symbol.Char.ToString(),
            _ => "ε"
        };

        float fx = (float)fromPos.X, fy = (float)fromPos.Y;
        float tx = (float)toPos.X, ty = (float)toPos.Y;

        // Self-loop
        if (t.From == t.To)
        {
            DrawSelfLoop(canvas, fx, fy, labelStr);
            return;
        }

        float dx = tx - fx, dy = ty - fy;
        float dist = MathF.Sqrt(dx * dx + dy * dy);
        if (dist < 0.01f) return;
        float nx = dx / dist, ny = dy / dist;

        // Check for bidirectional pair → curve
        bool hasPair = aut.Transitions.Any(o => o.From == t.To && o.To == t.From);
        float curve = hasPair ? 22f : 0f;
        float px = -ny, py = nx;

        float sx = fx + nx * StateRadius + px * curve * 0.4f;
        float sy = fy + ny * StateRadius + py * curve * 0.4f;
        float ex = tx - nx * StateRadius + px * curve * 0.4f;
        float ey = ty - ny * StateRadius + py * curve * 0.4f;
        float mx = (sx + ex) / 2 + px * curve;
        float my = (sy + ey) / 2 + py * curve;

        canvas.StrokeColor = TransColor;
        canvas.StrokeSize = 1.5f;

        if (hasPair)
        {
            var path = new PathF();
            path.MoveTo(sx, sy);
            path.QuadTo(mx, my, ex, ey);
            canvas.DrawPath(path);
        }
        else
        {
            canvas.DrawLine(sx, sy, ex, ey);
        }

        // Arrowhead
        float angle = hasPair ? MathF.Atan2(ey - my, ex - mx) : MathF.Atan2(dy, dx);
        float al = 10;
        var arrow = new PathF();
        arrow.MoveTo(ex, ey);
        arrow.LineTo(ex - al * MathF.Cos(angle - 0.3f), ey - al * MathF.Sin(angle - 0.3f));
        arrow.LineTo(ex - al * MathF.Cos(angle + 0.3f), ey - al * MathF.Sin(angle + 0.3f));
        arrow.Close();
        canvas.FillColor = TransColor;
        canvas.FillPath(arrow);

        // Label
        float lx = hasPair ? mx + px * 12 : (sx + ex) / 2 + px * 14;
        float ly = hasPair ? my + py * 12 : (sy + ey) / 2 + py * 14;
        canvas.FontColor = TransText;
        canvas.FontSize = 13;
        canvas.DrawString(labelStr, lx - 20, ly - 8, 40, 16,
            HorizontalAlignment.Center, VerticalAlignment.Center);
    }

    void DrawSelfLoop(ICanvas canvas, float x, float y, string label)
    {
        float cy = y - StateRadius - 16;
        float r = 16;

        canvas.StrokeColor = TransColor;
        canvas.StrokeSize = 1.5f;
        canvas.DrawArc(x - r, cy - r, r * 2, r * 2, 20, 320, false, false);

        // Label above
        canvas.FontColor = TransText;
        canvas.FontSize = 13;
        canvas.DrawString(label, x - 20, cy - r - 18, 40, 16,
            HorizontalAlignment.Center, VerticalAlignment.Center);
    }
}
