#!/usr/bin/env python3
"""
FRANCKY TRI-FLUX - log analyser (spec section 11, Table 17, C.4 transparency report).

Reads the CSV journals written by the EA (trades.csv, signals.csv, events.csv) from one or more run folders
and prints a Markdown report per symbol x engine:
  setups/day, trades/day, execution rate, win rate, profit factor, expectancy, max drawdown,
  average win / loss, average duration, average spread / slippage / latency, rejection reasons,
  exit reasons, MAE/MFE.

Usage:
  python3 tools/analyze_logs.py <run folder> [<run folder> ...] [--out report.md] [--stress-commission 7.0]
  python3 tools/analyze_logs.py "%APPDATA%/MetaQuotes/Terminal/Common/Files/FranckyTriFlux/TEST_MT5_EURUSD_I1_..."

Only the Python standard library is used.
"""
import argparse
import csv
import math
import os
import sys
from collections import Counter, defaultdict
from datetime import datetime


def fnum(x, default=0.0):
    try:
        return float(str(x).replace(",", "."))
    except (TypeError, ValueError):
        return default


def parse_time(s):
    s = (s or "").strip()
    for fmt in ("%Y.%m.%d %H:%M:%S.%f", "%Y.%m.%d %H:%M:%S", "%Y.%m.%d %H:%M"):
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            pass
    return None


def read_csv(path):
    if not os.path.exists(path):
        return []
    with open(path, newline="", encoding="utf-8", errors="replace") as fh:
        lines = [ln for ln in fh if not ln.startswith("#")]
    return list(csv.DictReader(lines, delimiter=";"))


def max_drawdown(pnls):
    peak = cum = mdd = 0.0
    for p in pnls:
        cum += p
        peak = max(peak, cum)
        mdd = max(mdd, peak - cum)
    return mdd


def stats_for(trades, signals, days, stress_commission):
    s = {}
    n = len(trades)
    nets = [fnum(t.get("net_pnl")) - stress_commission * fnum(t.get("lots")) for t in trades]
    wins = [x for x in nets if x > 0]
    losses = [x for x in nets if x <= 0]
    gp, gl = sum(wins), -sum(losses)
    s["setups"] = len(signals)
    s["accepted"] = sum(1 for r in signals if r.get("decision") == "ACCEPTED")
    s["trades"] = n
    s["setups_day"] = len(signals) / days if days > 0 else 0
    s["trades_day"] = n / days if days > 0 else 0
    s["exec_rate"] = 100.0 * s["accepted"] / len(signals) if signals else 0
    s["win_rate"] = 100.0 * len(wins) / n if n else 0
    s["pf"] = (gp / gl) if gl > 0 else (float("inf") if gp > 0 else 0)
    s["expectancy"] = sum(nets) / n if n else 0
    s["net"] = sum(nets)
    s["avg_win"] = gp / len(wins) if wins else 0
    s["avg_loss"] = -gl / len(losses) if losses else 0
    s["max_dd"] = max_drawdown(nets)
    s["avg_dur"] = sum(fnum(t.get("duration_s")) for t in trades) / n if n else 0
    s["avg_spread"] = sum(fnum(t.get("spread_pts")) for t in trades) / n if n else 0
    s["avg_slip"] = sum(fnum(t.get("slippage_pts")) for t in trades) / n if n else 0
    s["avg_lat"] = sum(fnum(t.get("latency_ms")) for t in trades) / n if n else 0
    s["max_lat"] = max([fnum(t.get("latency_ms")) for t in trades] or [0])
    s["avg_mae"] = sum(fnum(t.get("mae_pts")) for t in trades) / n if n else 0
    s["avg_mfe"] = sum(fnum(t.get("mfe_pts")) for t in trades) / n if n else 0
    s["avg_r"] = sum(fnum(t.get("r_multiple")) for t in trades) / n if n else 0
    s["rejects"] = Counter(r.get("reason") for r in signals if r.get("decision") != "ACCEPTED")
    s["exits"] = Counter(t.get("exit_reason") for t in trades)
    return s


def fmt(v, d=2):
    if isinstance(v, float) and math.isinf(v):
        return "inf"
    return ("%." + str(d) + "f") % v


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folders", nargs="+")
    ap.add_argument("--out", default="")
    ap.add_argument("--stress-commission", type=float, default=0.0,
                    help="extra commission per lot subtracted from every trade (degraded-cost test)")
    a = ap.parse_args()

    trades_by = defaultdict(list)
    signals_by = defaultdict(list)
    first, last = None, None
    events = Counter()
    for folder in a.folders:
        for t in read_csv(os.path.join(folder, "trades.csv")):
            trades_by[(t.get("symbol", "?"), t.get("engine", "?"))].append(t)
            for k in ("open_time", "close_time"):
                ts = parse_time(t.get(k))
                if ts:
                    first = ts if first is None or ts < first else first
                    last = ts if last is None or ts > last else last
        for r in read_csv(os.path.join(folder, "signals.csv")):
            signals_by[(r.get("symbol", "?"), r.get("engine", "?"))].append(r)
            ts = parse_time(r.get("time"))
            if ts:
                first = ts if first is None or ts < first else first
                last = ts if last is None or ts > last else last
        for e in read_csv(os.path.join(folder, "events.csv")):
            events[(e.get("category"), e.get("code"))] += 1

    days = ((last - first).total_seconds() / 86400.0) if first and last else 0
    days = max(days, 1.0 / 24.0) if days else 0
    keys = sorted(set(trades_by) | set(signals_by))
    out = ["# FRANCKY TRI-FLUX - run report", "",
           "Folders: " + ", ".join(a.folders), "",
           "Period: %s -> %s (%.2f days)%s" % (first, last, days,
                                               "  |  stress commission %.2f / lot" % a.stress_commission if a.stress_commission else ""),
           "", "| Symbol | Engine | Setups/day | Trades/day | Exec % | Trades | Win % | PF | Expectancy | Net | Avg win | Avg loss | Max DD | Avg dur s | Spread pts | Slip pts | Latency ms (max) | MAE/MFE pts | Avg R |",
           "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    per_symbol_total = defaultdict(lambda: ([], []))
    detail = []
    for k in keys:
        s = stats_for(trades_by[k], signals_by[k], days, a.stress_commission)
        per_symbol_total[k[0]][0].extend(trades_by[k])
        per_symbol_total[k[0]][1].extend(signals_by[k])
        out.append("| %s | %s | %s | %s | %s | %d | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s (%s) | %s / %s | %s |" % (
            k[0], k[1], fmt(s["setups_day"], 1), fmt(s["trades_day"], 1), fmt(s["exec_rate"], 1), s["trades"],
            fmt(s["win_rate"], 1), fmt(s["pf"]), fmt(s["expectancy"]), fmt(s["net"]), fmt(s["avg_win"]), fmt(s["avg_loss"]),
            fmt(s["max_dd"]), fmt(s["avg_dur"], 1), fmt(s["avg_spread"], 1), fmt(s["avg_slip"], 2), fmt(s["avg_lat"], 1),
            fmt(s["max_lat"], 1), fmt(s["avg_mae"], 1), fmt(s["avg_mfe"], 1), fmt(s["avg_r"])))
        detail.append("### %s / %s" % k)
        detail.append("* Top rejection reasons: " + (", ".join("%s %d" % (r, c) for r, c in s["rejects"].most_common(8)) or "none"))
        detail.append("* Exit reasons: " + (", ".join("%s %d" % (r, c) for r, c in s["exits"].most_common(10)) or "none"))
        detail.append("")
    for sym, (tr, sg) in sorted(per_symbol_total.items()):
        s = stats_for(tr, sg, days, a.stress_commission)
        out.append("| **%s** | **ALL** | %s | %s | %s | %d | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s (%s) | %s / %s | %s |" % (
            sym, fmt(s["setups_day"], 1), fmt(s["trades_day"], 1), fmt(s["exec_rate"], 1), s["trades"], fmt(s["win_rate"], 1),
            fmt(s["pf"]), fmt(s["expectancy"]), fmt(s["net"]), fmt(s["avg_win"]), fmt(s["avg_loss"]), fmt(s["max_dd"]),
            fmt(s["avg_dur"], 1), fmt(s["avg_spread"], 1), fmt(s["avg_slip"], 2), fmt(s["avg_lat"], 1), fmt(s["max_lat"], 1),
            fmt(s["avg_mae"], 1), fmt(s["avg_mfe"], 1), fmt(s["avg_r"])))
    out += ["", "## Details", ""] + detail
    if events:
        out += ["## Events", "", "| Category | Code | Count |", "|---|---|---|"]
        for (c, code), n in sorted(events.items()):
            out.append("| %s | %s | %d |" % (c, code, n))
    out += ["", "> Win rate alone is not a target: check PF, expectancy, max DD, out-of-sample and stress results (spec 11, C.4)."]
    text = "\n".join(out) + "\n"
    if a.out:
        with open(a.out, "w", encoding="utf-8") as fh:
            fh.write(text)
        print("report written to " + a.out)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
