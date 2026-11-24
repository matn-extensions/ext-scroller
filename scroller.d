module matn.editor.scroller;

import std.algorithm : min, max, clamp;
import std.conv : to;

import matn.platform.sdl;
import matn.platform.font : FontEngine;
import matn.ui.grid.cell : Color;
import matn.ui.grid.renderer : drawRealBox, drawRealRect;
import matn.extension.base;

/// A marker indicator drawn on the scroller track (e.g. diagnostic, search match)
struct ScrollerMarker
{
    int line;
    Color color;
}

/// Editor Scroller Extension: Smooth vector vertical scrollbar with interactive dragging and overview markers
class ScrollerExtension : Extension
{
    float trackWidth = 5.0f;
    bool showOverviewMarks = true;

    private bool _isHovered = false;
    private bool _isDragging = false;
    private float _dragOffsetThumbY = 0.0f;

    private float _lastTrackX = 0.0f;
    private float _lastTrackY = 0.0f;
    private float _lastTrackW = 0.0f;
    private float _lastTrackH = 0.0f;
    private float _lastThumbY = 0.0f;
    private float _lastThumbH = 0.0f;
    private int _lastTotalLines = 1;
    private int _lastVisibleRows = 1;

    this()
    {
        super(ExtensionManifest(
            "matn.scroller",
            "Editor Scroller",
            "1.0.0",
            "Matn Core",
            "Smooth interactive vertical scrollbar with visual document overview and track dragging",
            true
        ));
        this._enabled = true;
    }

    override protected void onActivate()
    {
        if (_context)
        {
            _context.registerSetting("EDITOR", "Editor Scroller", "Smooth interactive vertical scrollbar with track dragging", {
                _enabled = !_enabled;
            });
            _context.registerSetting("EDITOR", "Scroller Overview Marks", "Show diagnostic and search markers on the scrollbar track", {
                showOverviewMarks = !showOverviewMarks;
            });

            _context.registerCommand(ExtensionCommand(
                "scroller.toggle", "Toggle Editor Scroller", "View", "",
                { _enabled = !_enabled; }
            ));
        }
    }

    @property bool isHovered() const { return _isHovered; }
    @property bool isDragging() const { return _isDragging; }
    @property float lastTrackX() const { return _lastTrackX; }
    @property float lastTrackY() const { return _lastTrackY; }
    @property float lastTrackW() const { return _lastTrackW; }
    @property float lastTrackH() const { return _lastTrackH; }
    @property float lastThumbY() const { return _lastThumbY; }
    @property float lastThumbH() const { return _lastThumbH; }

    /// Computes thumb geometry without rendering (useful for testing or layout)
    void computeGeometry(float trackX, float trackY, float trackW, float trackH,
                         int totalDocLines, int scrollRow, int visibleRows,
                         out float outThumbY, out float outThumbH)
    {
        int totalLines = max(1, totalDocLines);
        int vis = max(1, visibleRows);
        float thumbRatio = cast(float) vis / cast(float) totalLines;
        outThumbH = clamp(thumbRatio * trackH, 16.0f, trackH);
        float maxScroll = cast(float)(totalLines - vis);
        float scrollNorm = maxScroll > 0 ? clamp(cast(float) scrollRow / maxScroll, 0.0f, 1.0f) : 0.0f;
        outThumbY = trackY + scrollNorm * (trackH - outThumbH);
    }

    /// Render smooth vector scrollbar on the editor display
    void renderReal(
        SDL_Renderer* renderer,
        FontEngine font,
        float padX,
        float padY,
        int gridCols,
        int startRow,
        int endRow,
        int totalDocLines,
        int scrollRow,
        int cursorRow,
        Color accentColor,
        Color defaultBg,
        bool isLight,
        const(ScrollerMarker)[] markers = null
    )
    {
        if (!_enabled || renderer is null || font is null || endRow <= startRow || gridCols <= 0)
            return;

        _lastTrackX = padX + (gridCols * font.charWidth) - trackWidth - 1.0f;
        _lastTrackY = padY + startRow * font.lineHeight;
        _lastTrackW = trackWidth;
        _lastTrackH = max(1.0f, (endRow - startRow) * font.lineHeight);
        _lastVisibleRows = max(1, endRow - startRow);
        _lastTotalLines = max(1, totalDocLines);

        computeGeometry(_lastTrackX, _lastTrackY, _lastTrackW, _lastTrackH,
                        _lastTotalLines, scrollRow, _lastVisibleRows,
                        _lastThumbY, _lastThumbH);

        // 1. Subtle semi-transparent track line
        Color trackBg = isLight ? Color(0, 0, 0, 16) : Color(255, 255, 255, 12);
        drawRealBox(renderer, _lastTrackX, _lastTrackY, _lastTrackW, _lastTrackH, Color(0, 0, 0, 0), trackBg);

        // 2. Overview markers (diagnostics, search results)
        if (showOverviewMarks && markers !is null && _lastTotalLines > 0)
        {
            foreach (ref m; markers)
            {
                if (m.line < 0 || m.line >= _lastTotalLines) continue;
                float mNorm = clamp(cast(float) m.line / cast(float) _lastTotalLines, 0.0f, 1.0f);
                float mY = _lastTrackY + mNorm * (_lastTrackH - 2.0f);
                drawRealRect(renderer, _lastTrackX, mY, _lastTrackW, 2.0f, m.color);
            }
        }

        // 3. Current cursor line indicator
        if (_lastTotalLines > 0 && cursorRow >= 0 && cursorRow < _lastTotalLines)
        {
            float cNorm = clamp(cast(float) cursorRow / cast(float) _lastTotalLines, 0.0f, 1.0f);
            float cY = _lastTrackY + cNorm * (_lastTrackH - 2.0f);
            Color curCol = Color(accentColor.r, accentColor.g, accentColor.b, 180);
            drawRealRect(renderer, _lastTrackX - 1.0f, cY, _lastTrackW + 2.0f, 2.0f, curCol);
        }

        // 4. Proportional thumb pill
        Color thumbCol;
        if (_isDragging)
        {
            thumbCol = Color(accentColor.r, accentColor.g, accentColor.b, 240);
        }
        else if (_isHovered)
        {
            thumbCol = isLight ? Color(100, 110, 130, 220) : Color(180, 195, 225, 220);
        }
        else
        {
            thumbCol = isLight ? Color(130, 140, 160, 150) : Color(145, 160, 185, 150);
        }

        drawRealBox(renderer, _lastTrackX, _lastThumbY, _lastTrackW, _lastThumbH, Color(0, 0, 0, 0), thumbCol);
    }

    /// Check if mouse coordinates fall within the interactive scrollbar hit region
    bool isOverScroller(float mouseX, float mouseY) const
    {
        if (!_enabled || _lastTrackH <= 0) return false;
        // 8px horizontal margin makes the scrollbar easy to grab
        return (mouseX >= _lastTrackX - 8.0f && mouseX <= _lastTrackX + _lastTrackW + 8.0f &&
                mouseY >= _lastTrackY && mouseY <= _lastTrackY + _lastTrackH);
    }

    /// Handle mouse down event on the scrollbar. Returns true if handled.
    bool handleMouseDown(float mouseX, float mouseY, out int newScrollRow)
    {
        if (!isOverScroller(mouseX, mouseY))
        {
            newScrollRow = -1;
            return false;
        }

        // Check if click landed directly on thumb
        if (mouseY >= _lastThumbY && mouseY <= _lastThumbY + _lastThumbH)
        {
            _isDragging = true;
            _dragOffsetThumbY = mouseY - _lastThumbY;
            newScrollRow = -1; // keep current scroll row
            return true;
        }

        // Clicked outside thumb on track: proportional jump to that position
        float availableH = max(1.0f, _lastTrackH - _lastThumbH);
        float targetNorm = clamp((mouseY - _lastTrackY - _lastThumbH / 2.0f) / availableH, 0.0f, 1.0f);
        int maxScroll = max(0, _lastTotalLines - _lastVisibleRows);
        newScrollRow = cast(int)(targetNorm * maxScroll);
        _isDragging = true;
        _dragOffsetThumbY = _lastThumbH / 2.0f;
        return true;
    }

    /// Handle mouse motion event. Returns true if scroll position updated.
    bool handleMouseMotion(float mouseX, float mouseY, out int newScrollRow)
    {
        _isHovered = isOverScroller(mouseX, mouseY);

        if (_isDragging)
        {
            float targetThumbY = mouseY - _dragOffsetThumbY;
            float availableH = max(1.0f, _lastTrackH - _lastThumbH);
            float norm = clamp((targetThumbY - _lastTrackY) / availableH, 0.0f, 1.0f);
            int maxScroll = max(0, _lastTotalLines - _lastVisibleRows);
            newScrollRow = cast(int)(norm * maxScroll);
            return true;
        }

        newScrollRow = -1;
        return false;
    }

    /// Handle mouse button release. Returns true if dragging ended.
    bool handleMouseUp()
    {
        bool wasDragging = _isDragging;
        _isDragging = false;
        return wasDragging;
    }
}

unittest
{
    auto scroller = new ScrollerExtension();
    assert(scroller.id == "matn.scroller");
    assert(scroller.isEnabled);

    // Test geometry computation
    float thumbY, thumbH;
    scroller.computeGeometry(100.0f, 20.0f, 5.0f, 300.0f, 100, 0, 20, thumbY, thumbH);
    assert(thumbY == 20.0f);
    assert(thumbH == 60.0f); // 20/100 * 300 = 60

    // Halfway scroll
    scroller.computeGeometry(100.0f, 20.0f, 5.0f, 300.0f, 100, 40, 20, thumbY, thumbH);
    // maxScroll = 80, norm = 40/80 = 0.5, availableH = 240, thumbY = 20 + 120 = 140
    assert(thumbY == 140.0f);

    // Full scroll
    scroller.computeGeometry(100.0f, 20.0f, 5.0f, 300.0f, 100, 80, 20, thumbY, thumbH);
    assert(thumbY == 260.0f); // 20 + 240 = 260

    // Small document where lines < visible rows
    scroller.computeGeometry(100.0f, 0.0f, 5.0f, 200.0f, 10, 0, 30, thumbY, thumbH);
    assert(thumbH == 200.0f); // thumb occupies full height
    assert(thumbY == 0.0f);

    // Interactive mouse drag simulation
    scroller._lastTrackX = 500.0f;
    scroller._lastTrackY = 10.0f;
    scroller._lastTrackW = 5.0f;
    scroller._lastTrackH = 200.0f;
    scroller._lastThumbY = 10.0f;
    scroller._lastThumbH = 40.0f;
    scroller._lastTotalLines = 100;
    scroller._lastVisibleRows = 20;

    assert(scroller.isOverScroller(502.0f, 50.0f));
    assert(!scroller.isOverScroller(100.0f, 50.0f));

    // Click on thumb (y = 20) -> starts dragging without jumping
    int newScroll = -1;
    bool downHandled = scroller.handleMouseDown(502.0f, 20.0f, newScroll);
    assert(downHandled);
    assert(scroller.isDragging);
    assert(newScroll == -1);

    // Drag down to y = 100
    bool motionHandled = scroller.handleMouseMotion(502.0f, 100.0f, newScroll);
    assert(motionHandled);
    assert(newScroll > 0);

    // Mouse up
    bool upHandled = scroller.handleMouseUp();
    assert(upHandled);
    assert(!scroller.isDragging);
}
