using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;
using Toybox.Math;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.ActivityMonitor;
using Toybox.Activity;
using Toybox.Application;

class DarkTechWatchView extends Ui.WatchFace {

    var isAwake = true;
    var days = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
    var months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];

    // palettes per theme: [battery, steps, heart rate]
    var darkPal = [
        [0x00FF00, 0x00E5FF, 0xFF0000],
        [0x00E5FF, 0x4FC3F7, 0x80D8FF],
        [0xFF6D00, 0xFFAB00, 0xFF1744],
        [0xFFC107, 0xFFD54F, 0xFF8F00],
        [0xFFFFFF, 0xFFFFFF, 0xFFFFFF]
    ];
    var lightPal = [
        [0x008A00, 0x007A99, 0xCC0000],
        [0x006C99, 0x0277BD, 0x01579B],
        [0xD84315, 0xE65100, 0xB71C1C],
        [0xB28704, 0x8D6E00, 0xE65100],
        [0x000000, 0x000000, 0x000000]
    ];

    // settings
    var cfgBg = 0;
    var cfgTime = 0;
    var cfgTheme = 0;
    var cfgDate = 0;
    var cfgSeconds = 1;
    var cfgSlot = [0, 1, 2, 3];

    // colors
    var bg = Gfx.COLOR_BLACK;
    var fg = Gfx.COLOR_WHITE;
    var dim = Gfx.COLOR_LT_GRAY;
    var track = Gfx.COLOR_DK_GRAY;
    var cBatt = 0x00FF00;
    var cSteps = 0x00E5FF;
    var cHr = 0xFF0000;
    var cGold = 0xFFAA00;
    var cRed = 0xFF0000;

    // data refreshed on every update
    var battery = 0.0;
    var battColor = 0x00FF00;
    var battDays = "";
    var stepsPct = 0.0;
    var stepsColor = 0x00E5FF;
    var stepsStr = "--";
    var calStr = "--";
    var distStr = "--";
    var floorsStr = "--";
    var hrStr = "--";
    var dateStr = "";
    var timeString = "";
    var clockTime = null;
    var connected = false;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc) {
    }

    function onEnterSleep() {
        isAwake = false;
        Ui.requestUpdate();
    }

    function onExitSleep() {
        isAwake = true;
        Ui.requestUpdate();
    }

    // ---------- settings ----------
    function getSetting(key, def) {
        var v = null;
        try {
            v = Application.Properties.getValue(key);
        } catch (e) {
            v = null;
        }
        if (v == null) {
            return def;
        }
        return v;
    }

    function loadSettings() {
        cfgBg = getSetting("Background", 0);
        cfgTime = getSetting("TimeFormat", 0);
        if (Edition.PREMIUM) {
            cfgTheme = getSetting("Theme", 0);
            cfgDate = getSetting("DateFormat", 0);
            cfgSeconds = getSetting("SecondsDot", 1);
            cfgSlot = [getSetting("SlotA", 0), getSetting("SlotB", 1),
                       getSetting("SlotC", 2), getSetting("SlotD", 3)];
        } else {
            cfgTheme = 0;
            cfgDate = 0;
            cfgSeconds = 1;
            // Free: Slot 0 pod zegarem, Slot 1 i 2 na dole, Slot 3 wyłączony
            cfgSlot = [0, 1, 2, 6];
        }
        if (cfgTheme < 0 || cfgTheme > 4) {
            cfgTheme = 0;
        }

        var light = (cfgBg == 1);
        var pal = light ? lightPal[cfgTheme] : darkPal[cfgTheme];
        bg = light ? Gfx.COLOR_WHITE : Gfx.COLOR_BLACK;
        fg = light ? Gfx.COLOR_BLACK : Gfx.COLOR_WHITE;
        dim = light ? Gfx.COLOR_DK_GRAY : Gfx.COLOR_LT_GRAY;
        track = light ? Gfx.COLOR_LT_GRAY : Gfx.COLOR_DK_GRAY;
        cBatt = pal[0];
        cSteps = pal[1];
        cHr = pal[2];
        cGold = light ? 0xB36B00 : 0xFFAA00;
        cRed = light ? 0xCC0000 : 0xFF0000;
    }

    // ---------- helpers ----------
    function drawProgress(dc, cx, cy, r, pct, color, pen) {
        if (pct > 1.0) {
            pct = 1.0;
        }
        var sweep = (pct * 360).toNumber();
        if (sweep < 1) {
            return;
        }
        dc.setPenWidth(pen);
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        if (sweep >= 360) {
            dc.drawCircle(cx, cy, r);
            return;
        }
        var endDeg = 90 - sweep;
        while (endDeg < 0) {
            endDeg += 360;
        }
        dc.drawArc(cx, cy, r, Gfx.ARC_CLOCKWISE, 90, endDeg);
    }

    function pickTimeFont(dc, maxWidth) {
        var fonts = [Gfx.FONT_NUMBER_HOT, Gfx.FONT_NUMBER_MEDIUM, Gfx.FONT_NUMBER_MILD];
        for (var i = 0; i < fonts.size(); i++) {
            if (dc.getTextWidthInPixels(timeString, fonts[i]) <= maxWidth) {
                return fonts[i];
            }
        }
        return Gfx.FONT_NUMBER_MILD;
    }

    function slotText(id) {
        if (id == 0) {
            return stepsStr + " st";
        }
        if (id == 1) {
            return hrStr + " bpm";
        }
        if (id == 2) {
            return calStr + " kcal";
        }
        if (id == 3) {
            return distStr;
        }
        if (id == 4) {
            return floorsStr + " fl";
        }
        if (id == 5) {
            return (battDays.length() > 0) ? (battDays + " days") : "-- days";
        }
        return "";
    }

    function slotColor(id) {
        if (id == 0) {
            return stepsColor;
        }
        if (id == 1) {
            return cHr;
        }
        if (id == 2) {
            return cGold;
        }
        if (id == 3) {
            return dim;
        }
        if (id == 4) {
            return cSteps;
        }
        return battColor;
    }

    function drawSlot(dc, id, x, y, font, just, useColor) {
        if (id == 6) {
            return;
        }
        dc.setColor(useColor ? slotColor(id) : fg, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, slotText(id), just | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    function drawBluetooth(dc, x, y, mono) {
        if (connected) {
            dc.setColor(mono ? fg : Gfx.COLOR_BLUE, Gfx.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, mono ? 2 : 4);
        } else if (!mono) {
            dc.setPenWidth(1);
            dc.setColor(track, Gfx.COLOR_TRANSPARENT);
            dc.drawCircle(x, y, 4);
        }
    }

    // ---------- data ----------
    function collectData() {
        clockTime = Sys.getClockTime();
        var ds = Sys.getDeviceSettings();

        // battery
        var stats = Sys.getSystemStats();
        battery = stats.battery;
        battColor = cBatt;
        if (Edition.PREMIUM && cfgTheme != 4) {
            if (battery < 20) {
                battColor = cRed;
            } else if (battery < 50 && cfgTheme == 0) {
                battColor = (cfgBg == 1) ? 0xB28704 : 0xFFD600;
            }
        }
        battDays = "";
        if (stats has :batteryInDays) {
            if (stats.batteryInDays != null) {
                battDays = stats.batteryInDays.toNumber().toString();
            }
        }

        // activity
        var am = ActivityMonitor.getInfo();
        var steps = am.steps;
        var goal = am.stepGoal;
        stepsPct = 0.0;
        if (steps != null && goal != null && goal > 0) {
            stepsPct = steps.toFloat() / goal;
        }
        stepsColor = cSteps;
        if (Edition.PREMIUM && stepsPct >= 1.0) {
            stepsColor = cGold;
        }
        stepsStr = (steps != null) ? steps.toString() : "--";
        calStr = (am.calories != null) ? am.calories.toString() : "--";

        var dist = am.distance;
        if (dist != null) {
            if (ds.distanceUnits == Sys.UNIT_STATUTE) {
                distStr = (dist / 160934.0).format("%.1f") + " mi";
            } else {
                distStr = (dist / 100000.0).format("%.1f") + " km";
            }
        } else {
            distStr = "-- km";
        }

        floorsStr = "--";
        if (am has :floorsClimbed) {
            if (am.floorsClimbed != null) {
                floorsStr = am.floorsClimbed.toString();
            }
        }

        // heart rate
        var ai = Activity.getActivityInfo();
        var hr = (ai != null) ? ai.currentHeartRate : null;
        hrStr = (hr != null) ? hr.toString() : "--";

        // date
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var wd = days[info.day_of_week - 1];
        var dd = info.day.format("%02d");
        var mm = info.month.format("%02d");
        if (cfgDate == 1) {
            dateStr = wd + " " + dd + "." + mm;
        } else if (cfgDate == 2) {
            dateStr = wd + " " + mm + "/" + dd;
        } else if (cfgDate == 3) {
            dateStr = dd + months[info.month - 1] + (info.year % 100).format("%02d");
        } else {
            dateStr = wd + " " + dd + " " + months[info.month - 1];
        }

        // time
        var fmt = cfgTime;
        if (fmt == 3 && !Edition.PREMIUM) {
            fmt = 2;
        }
        if (fmt < 1 || fmt > 3) {
            fmt = ds.is24Hour ? 2 : 1;
        }
        var hour = clockTime.hour;
        if (fmt == 1) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
            timeString = hour.format("%d") + ":" + clockTime.min.format("%02d");
        } else if (fmt == 2) {
            timeString = hour.format("%02d") + ":" + clockTime.min.format("%02d");
        } else {
            timeString = hour.format("%02d") + clockTime.min.format("%02d");
        }
        connected = ds.phoneConnected;
    }

    // ---------- main ----------
    function onUpdate(dc) {
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        loadSettings();
        dc.setColor(fg, bg);
        dc.clear();

        collectData();

        var ds = Sys.getDeviceSettings();
        var sub = null;
        if (Ui has :getSubscreen) {
            sub = Ui.getSubscreen();
        }
        if (sub != null || (ds.screenShape != Sys.SCREEN_SHAPE_ROUND && ds.screenShape != Sys.SCREEN_SHAPE_RECTANGLE)) {
            drawMono(dc, sub);
        } else if (ds.screenShape == Sys.SCREEN_SHAPE_ROUND) {
            drawRound(dc);
        } else {
            drawRect(dc);
        }
    }

    // ---------- round screens ----------
    function drawRound(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var u = h / 260.0;
        var r1 = (w < h ? cx : cy) - 5;
        var r2 = r1 - 11;
        var tickOuter = r2 - 8;
        var orbit = tickOuter - 14 * u;

        // outer ring: battery
        dc.setPenWidth(6);
        dc.setColor(track, Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r1);
        drawProgress(dc, cx, cy, r1, battery / 100.0, battColor, 6);

        if (Edition.PREMIUM) {
            // inner ring: steps goal
            dc.setPenWidth(6);
            dc.setColor(track, Gfx.COLOR_TRANSPARENT);
            dc.drawCircle(cx, cy, r2);
            drawProgress(dc, cx, cy, r2, stepsPct, stepsColor, 6);

            // hour ticks
            for (var i = 0; i < 12; i++) {
                var a = i * 30 * Math.PI / 180.0;
                var s = Math.sin(a);
                var c = Math.cos(a);
                var rIn = tickOuter - 6 * u;
                var pen = 2;
                var tickColor = dim;
                if (i % 3 == 0) {
                    rIn = tickOuter - 11 * u;
                    pen = 3;
                    tickColor = fg;
                }
                if (i == 0) {
                    tickColor = Gfx.COLOR_ORANGE;
                }
                dc.setPenWidth(pen);
                dc.setColor(tickColor, Gfx.COLOR_TRANSPARENT);
                dc.drawLine((cx + rIn * s).toNumber(), (cy - rIn * c).toNumber(),
                            (cx + tickOuter * s).toNumber(), (cy - tickOuter * c).toNumber());
            }

            // seconds dot (only when awake and enabled)
            if (isAwake && cfgSeconds == 1) {
                var sa = clockTime.sec * 6 * Math.PI / 180.0;
                var dotR = (3 * u).toNumber();
                if (dotR < 3) {
                    dotR = 3;
                }
                dc.setColor(cRed, Gfx.COLOR_TRANSPARENT);
                dc.fillCircle((cx + orbit * Math.sin(sa)).toNumber(), (cy - orbit * Math.cos(sa)).toNumber(), dotR);
            }
        }

        // time
        var timeFont = pickTimeFont(dc, w * 0.62);
        dc.setColor(fg, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, timeFont, timeString, Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);

        // element directly under the clock (Slot 0)
        drawSlot(dc, cfgSlot[0], cx, cy + (38 * u).toNumber(), Gfx.FONT_XTINY, Gfx.TEXT_JUSTIFY_CENTER, true);

        // battery % and Bluetooth dot next to it
        var battText = battery.toNumber().toString() + "%";
        var battY = cy - (80 * u).toNumber();
        dc.setColor(battColor, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, battY, Gfx.FONT_XTINY, battText,
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        drawBluetooth(dc, cx + dc.getTextWidthInPixels(battText, Gfx.FONT_XTINY) / 2 + 10, battY, false);

        // date
        dc.setColor(dim, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (55 * u).toNumber(), Gfx.FONT_TINY, dateStr,
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);

        // bottom slots (Slot 1 and Slot 2)
        drawSlot(dc, cfgSlot[1], cx, cy + (65 * u).toNumber(), Gfx.FONT_TINY, Gfx.TEXT_JUSTIFY_CENTER, true);
        drawSlot(dc, cfgSlot[2], cx, cy + (88 * u).toNumber(), Gfx.FONT_TINY, Gfx.TEXT_JUSTIFY_CENTER, true);
    }

    // ---------- rectangular color screens (Venu Sq) ----------
    function drawRect(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var pad = (w * 0.06).toNumber();
        var barW = w - 2 * pad;
        var barH = (h * 0.06).toNumber();
        if (barH < 6) {
            barH = 6;
        }
        var barY = (h * 0.63).toNumber();
        var topY = (h * 0.10).toNumber();
        var battText = battery.toNumber().toString() + "%";

        // date (left) and battery (right)
        dc.setColor(dim, Gfx.COLOR_TRANSPARENT);
        dc.drawText(pad, topY, Gfx.FONT_TINY, dateStr,
                    Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
        dc.setColor(battColor, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w - pad, topY, Gfx.FONT_TINY, battText,
                    Gfx.TEXT_JUSTIFY_RIGHT | Gfx.TEXT_JUSTIFY_VCENTER);
        drawBluetooth(dc, w - pad - dc.getTextWidthInPixels(battText, Gfx.FONT_TINY) - 10, topY, false);

        // time
        var timeFont = pickTimeFont(dc, w * 0.80);
        dc.setColor(fg, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, (h * 0.38).toNumber(), timeFont, timeString,
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);

        // element directly under the clock (Slot 0)
        drawSlot(dc, cfgSlot[0], w / 2, (h * 0.54).toNumber(), Gfx.FONT_TINY, Gfx.TEXT_JUSTIFY_CENTER, true);

        // battery bar
        dc.setPenWidth(1);
        dc.setColor(battColor, Gfx.COLOR_TRANSPARENT);
        dc.drawRectangle(pad, barY, barW, barH);
        var fill = ((barW - 4) * battery / 100.0).toNumber();
        if (fill > 0) {
            dc.fillRectangle(pad + 2, barY + 2, fill, barH - 4);
        }

        if (Edition.PREMIUM) {
            // steps goal bar
            var y2 = barY + barH + 3;
            var h2 = barH / 2;
            if (h2 < 4) {
                h2 = 4;
            }
            var pct = stepsPct;
            if (pct > 1.0) {
                pct = 1.0;
            }
            dc.setPenWidth(1);
            dc.setColor(stepsColor, Gfx.COLOR_TRANSPARENT);
            dc.drawRectangle(pad, y2, barW, h2);
            var fill2 = ((barW - 4) * pct).toNumber();
            if (fill2 > 0) {
                dc.fillRectangle(pad + 2, y2 + 2, fill2, h2 - 4);
            }

            // extra row (Slot 2 and 3)
            var ey = (h * 0.79).toNumber();
            drawSlot(dc, cfgSlot[2], pad, ey, Gfx.FONT_XTINY, Gfx.TEXT_JUSTIFY_LEFT, true);
            drawSlot(dc, cfgSlot[3], w - pad, ey, Gfx.FONT_XTINY, Gfx.TEXT_JUSTIFY_RIGHT, true);
        }

        // bottom row (Slot 1)
        drawSlot(dc, cfgSlot[1], w / 2, (h * 0.88).toNumber(), Gfx.FONT_TINY, Gfx.TEXT_JUSTIFY_CENTER, true);
    }

    // ---------- monochrome screens with subscreen (Instinct) ----------
    function drawMono(dc, sub) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var pad = (w * 0.09).toNumber();

        var sx;
        var sy;
        var sw;
        var sh;
        if (sub != null) {
            sx = sub.x;
            sy = sub.y;
            sw = sub.width;
            sh = sub.height;
        } else {
            sx = (w * 0.60).toNumber();
            sy = 0;
            sw = w - sx;
            sh = (h * 0.40).toNumber();
        }
        var scx = sx + sw / 2;
        var scy = sy + sh / 2;
        var sr = ((sw < sh) ? sw : sh) / 2 - 3;

        // subscreen: battery ring + percent
        dc.setPenWidth(1);
        dc.setColor(fg, Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(scx, scy, sr - 4);
        drawProgress(dc, scx, scy, sr - 4, battery / 100.0, fg, 4);

        // premium: steps goal ring inside the battery ring
        var dotOffset = 0.55;
        if (Edition.PREMIUM && (sr - 11) >= 13) {
            dc.setPenWidth(1);
            dc.setColor(fg, Gfx.COLOR_TRANSPARENT);
            dc.drawCircle(scx, scy, sr - 10);
            drawProgress(dc, scx, scy, sr - 10, stepsPct, fg, 3);
            dotOffset = 0.45;
        }

        dc.setColor(fg, Gfx.COLOR_TRANSPARENT);
        dc.drawText(scx, scy, Gfx.FONT_XTINY, battery.toNumber().toString(),
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        drawBluetooth(dc, scx, scy + (sr * dotOffset).toNumber(), true);

        // date, left of the subscreen
        var availW = sx - pad - 2;
        var dstr = dateStr;
        var dfont = Gfx.FONT_TINY;
        if (dc.getTextWidthInPixels(dstr, dfont) > availW) {
            dfont = Gfx.FONT_XTINY;
        }
        if (dc.getTextWidthInPixels(dstr, dfont) > availW) {
            dstr = dateStr.substring(0, 6);
        }
        dc.setColor(fg, Gfx.COLOR_TRANSPARENT);
        dc.drawText(pad, scy, dfont, dstr, Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);

        // time, always below the subscreen
        var timeFont = pickTimeFont(dc, w * 0.78);
        var fontH = dc.getFontHeight(timeFont);
        var timeY = (h * 0.52).toNumber();
        var minY = sy + sh + 2 + fontH / 2;
        if (timeY < minY) {
            timeY = minY;
        }
        dc.setColor(fg, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, timeY, timeFont, timeString, Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);

        // bottom row
        var botY = (h * 0.86).toNumber();
        var bf = Gfx.FONT_TINY;
        if (dc.getTextWidthInPixels(slotText(cfgSlot[0]), bf) + dc.getTextWidthInPixels(slotText(cfgSlot[1]), bf) + 3 * pad > w) {
            bf = Gfx.FONT_XTINY;
        }
        drawSlot(dc, cfgSlot[0], pad, botY, bf, Gfx.TEXT_JUSTIFY_LEFT, false);
        drawSlot(dc, cfgSlot[1], w - pad, botY, bf, Gfx.TEXT_JUSTIFY_RIGHT, false);

        // premium: extra row between time and bottom row
        if (Edition.PREMIUM) {
            var xf = Gfx.FONT_XTINY;
            var xh = dc.getFontHeight(xf);
            var ey = timeY + fontH / 2 + 2 + xh / 2;
            var botTop = botY - dc.getFontHeight(bf) / 2;
            if (ey + xh / 2 <= botTop) {
                drawSlot(dc, cfgSlot[2], pad, ey, xf, Gfx.TEXT_JUSTIFY_LEFT, false);
                drawSlot(dc, cfgSlot[3], w - pad, ey, xf, Gfx.TEXT_JUSTIFY_RIGHT, false);
            }
        }
    }
}