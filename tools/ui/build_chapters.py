#!/usr/bin/env python3
"""Generate data/chapters/chapters.json: the 30-chapter framework.

Chapter 1 uses the approved Little Italy goals. Chapters 2-30 are PLACEHOLDERS
(no story, titles pending approval): objective templates built from existing
mechanics, scaled requirements, cash rewards and power unlocks. Replace the
titles, dialogue and objectives as the story is approved; the game reads only
this file.

Usage: python3 tools/ui/build_chapters.py
"""
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

chapters = [{
    "id": "ch01", "number": 1, "title": "Little Italy", "placeholder": False,
    "summary": "Secure the family's footing on Mulberry Street.",
    "intro_dialogue": "ch01_intro",
    "unlock": {},
    "objectives": [
        {"type": "business_level", "business": "biz_vesuvio", "target": 3, "text": "Upgrade Ristorante Vesuvio to Lv 3"},
        {"type": "own_business", "business": "biz_grand_freight", "target": 1, "text": "Take over Grand Street Freight"},
        {"type": "business_level", "business": "biz_bowery_auto", "target": 2, "text": "Upgrade Bowery Auto Body to Lv 2"},
        {"type": "income", "target": 5000, "text": "Raise family income to $5,000/h"},
    ],
    "rewards": {"cash": 5000},
}]
for n in range(2, 31):
    objectives = [
        {"type": "income", "target": 5000 + (n - 1) * 1500, "text": "Raise family income to ${:,}/h".format(5000 + (n - 1) * 1500)},
        {"type": "collected_total", "target": int(8000 * n ** 1.6), "text": "Collect ${:,} in total".format(int(8000 * n ** 1.6))},
    ]
    if n % 2 == 0:
        objectives.append({"type": "upgrades_total", "target": 2 + n, "text": "Complete {} business upgrades".format(2 + n)})
    if n % 3 == 0:
        objectives.append({"type": "family_power", "target": 300 + n * 45, "text": "Reach {} family power".format(300 + n * 45)})
    chapters.append({
        "id": "ch%02d" % n, "number": n, "title": "Chapter %d" % n, "placeholder": True,
        "summary": "Story pending approval.", "intro_dialogue": "",
        "unlock": {"family_power": 250 + (n - 1) * 60},
        "objectives": objectives,
        "rewards": {"cash": 2500 * n},
    })
with open(os.path.join(ROOT, "data", "chapters", "chapters.json"), "w") as f:
    json.dump({"version": 1, "note": "Chapters 2-30 are placeholders pending story approval.", "chapters": chapters}, f, indent=1)
print("chapters:", len(chapters))
