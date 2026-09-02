#!/usr/bin/env python3
"""Visualize a JSONL report as a standalone HTML dashboard.

Usage:
  python3 visualize_json_report.py /path/to/report.jsonl
  python3 visualize_json_report.py /path/to/report.jsonl -o report_dashboard.html
"""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from datetime import datetime
from html import escape
from pathlib import Path


def parse_ts(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        # Supports "...Z" and timezone offsets.
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def bar_svg(title: str, data: dict[str, int], width: int = 860, row_h: int = 28) -> str:
    if not data:
        return f"<h3>{escape(title)}</h3><p>No data</p>"

    items = sorted(data.items(), key=lambda kv: kv[1], reverse=True)
    max_v = max(v for _, v in items) or 1
    left_pad = 180
    right_pad = 70
    top_pad = 10
    chart_w = width - left_pad - right_pad
    height = top_pad + row_h * len(items) + 20

    lines = [f"<h3>{escape(title)}</h3>", f'<svg width="{width}" height="{height}" viewBox="0 0 {width} {height}">']

    for i, (name, value) in enumerate(items):
        y = top_pad + i * row_h
        bar_w = int((value / max_v) * chart_w)
        label = escape(name)
        lines.append(
            f'<text x="8" y="{y + 18}" font-size="13" fill="#1f2d3d">{label}</text>'
            f'<rect x="{left_pad}" y="{y + 4}" width="{bar_w}" height="18" fill="#2f6db2" rx="3"/>'
            f'<text x="{left_pad + bar_w + 8}" y="{y + 18}" font-size="12" fill="#23313f">{value}</text>'
        )

    lines.append("</svg>")
    return "\n".join(lines)


def line_svg(title: str, points: list[tuple[str, int]], width: int = 860, height: int = 260) -> str:
    if not points:
        return f"<h3>{escape(title)}</h3><p>No data</p>"

    left_pad = 56
    right_pad = 16
    top_pad = 16
    bottom_pad = 40
    chart_w = width - left_pad - right_pad
    chart_h = height - top_pad - bottom_pad

    max_v = max(v for _, v in points) or 1
    n = max(1, len(points) - 1)

    coords: list[tuple[float, float]] = []
    for i, (_, v) in enumerate(points):
        x = left_pad + (chart_w * i / n)
        y = top_pad + chart_h - (chart_h * v / max_v)
        coords.append((x, y))

    poly = " ".join(f"{x:.2f},{y:.2f}" for x, y in coords)

    out = [
        f"<h3>{escape(title)}</h3>",
        f'<svg width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        f'<rect x="{left_pad}" y="{top_pad}" width="{chart_w}" height="{chart_h}" fill="#f8fbff" stroke="#d6deea"/>',
    ]

    # Y-axis ticks
    for t in range(5):
        val = int(max_v * t / 4)
        y = top_pad + chart_h - (chart_h * t / 4)
        out.append(
            f'<line x1="{left_pad}" y1="{y:.2f}" x2="{left_pad + chart_w}" y2="{y:.2f}" stroke="#e5ebf4"/>'
            f'<text x="8" y="{y + 4:.2f}" font-size="11" fill="#58677a">{val}</text>'
        )

    out.append(f'<polyline points="{poly}" fill="none" stroke="#2f6db2" stroke-width="2.5"/>')
    for (x, y), (_, v) in zip(coords, points):
        out.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="3.2" fill="#1d4f8c"/><title>{v}</title>')

    # X labels: show up to 8 labels to avoid overlap
    step = max(1, len(points) // 8)
    for i, (label, _) in enumerate(points):
        if i % step == 0 or i == len(points) - 1:
            x = left_pad + (chart_w * i / n)
            out.append(
                f'<text x="{x:.2f}" y="{height - 14}" text-anchor="middle" font-size="10" fill="#58677a">{escape(label)}</text>'
            )

    out.append("</svg>")
    return "\n".join(out)


def build_dashboard(input_path: Path) -> str:
    total_lines = 0
    bad_lines = 0
    event_counts: Counter[str] = Counter()
    model_counts: Counter[str] = Counter()
    agent_counts: Counter[str] = Counter()
    tool_counts: Counter[str] = Counter()
    by_minute: dict[str, int] = defaultdict(int)
    first_ts: datetime | None = None
    last_ts: datetime | None = None

    with input_path.open("r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            total_lines += 1
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                bad_lines += 1
                continue

            ts = parse_ts(obj.get("timestamp")) or parse_ts(obj.get("timestamp_iso"))
            if ts:
                key = ts.strftime("%Y-%m-%d %H:%M")
                by_minute[key] += 1
                if first_ts is None or ts < first_ts:
                    first_ts = ts
                if last_ts is None or ts > last_ts:
                    last_ts = ts

            if "event" in obj:
                event_counts[str(obj["event"])] += 1
            if "model" in obj:
                model_counts[str(obj["model"])] += 1
            if "agent_name" in obj:
                agent_counts[str(obj["agent_name"])] += 1

            for tc in obj.get("tool_calls", []) or []:
                fn = ((tc.get("function") or {}).get("name"))
                if fn:
                    tool_counts[str(fn)] += 1
            for choice in obj.get("choices", []) or []:
                msg = (choice.get("message") or {})
                for tc in msg.get("tool_calls", []) or []:
                    fn = ((tc.get("function") or {}).get("name"))
                    if fn:
                        tool_counts[str(fn)] += 1

    timeline = sorted(by_minute.items(), key=lambda kv: kv[0])
    summary_rows = [
        ("Input file", str(input_path)),
        ("Total JSON lines", str(total_lines)),
        ("Invalid JSON lines", str(bad_lines)),
        ("Session start", first_ts.isoformat() if first_ts else "N/A"),
        ("Session end", last_ts.isoformat() if last_ts else "N/A"),
    ]

    def summary_table() -> str:
        rows = "".join(
            f"<tr><th>{escape(k)}</th><td>{escape(v)}</td></tr>" for k, v in summary_rows
        )
        return f"<table class='summary'>{rows}</table>"

    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>JSON Report Dashboard</title>
  <style>
    :root {{
      --bg: #f2f6fb;
      --card: #ffffff;
      --ink: #17212d;
      --line: #d7e0ec;
      --accent: #2f6db2;
    }}
    body {{
      margin: 0;
      font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif;
      background: var(--bg);
      color: var(--ink);
    }}
    .wrap {{
      max-width: 940px;
      margin: 24px auto;
      padding: 0 14px 20px;
    }}
    .card {{
      background: var(--card);
      border: 1px solid var(--line);
      border-radius: 10px;
      padding: 14px 16px;
      margin-bottom: 14px;
    }}
    h1, h2, h3 {{ margin: 0 0 10px; }}
    h1 {{ font-size: 1.45rem; }}
    h2 {{ font-size: 1.1rem; }}
    h3 {{ font-size: 1rem; color: #2a4057; }}
    .summary {{
      border-collapse: collapse;
      width: 100%;
    }}
    .summary th, .summary td {{
      border-bottom: 1px solid var(--line);
      text-align: left;
      padding: 7px 8px;
      font-size: 0.95rem;
      vertical-align: top;
    }}
    .summary th {{ width: 180px; color: #2a4057; }}
    .muted {{ color: #4d5f75; font-size: 0.92rem; }}
    svg {{ max-width: 100%; height: auto; display: block; }}
  </style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      <h1>JSON Report Dashboard</h1>
      <p class="muted">Generated from JSONL session log.</p>
      {summary_table()}
    </div>

    <div class="card">{bar_svg("Event Counts", dict(event_counts))}</div>
    <div class="card">{line_svg("Activity Over Time (per minute)", timeline)}</div>
    <div class="card">{bar_svg("Model Counts", dict(model_counts))}</div>
    <div class="card">{bar_svg("Tool Call Counts", dict(tool_counts))}</div>
    <div class="card">{bar_svg("Agent Counts", dict(agent_counts))}</div>
  </div>
</body>
</html>
"""


def main() -> None:
    parser = argparse.ArgumentParser(description="Visualize a JSONL report in HTML.")
    parser.add_argument("input", type=Path, help="Path to input .jsonl file")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("json_report_dashboard.html"),
        help="Output HTML path (default: json_report_dashboard.html)",
    )
    args = parser.parse_args()

    if not args.input.exists():
        raise SystemExit(f"Input file not found: {args.input}")

    html = build_dashboard(args.input)
    args.output.write_text(html, encoding="utf-8")
    print(f"Dashboard written to: {args.output}")


if __name__ == "__main__":
    main()
