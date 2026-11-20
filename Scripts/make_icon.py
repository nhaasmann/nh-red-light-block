#!/usr/bin/env python3
"""Writes Resources/brand/AppIcon.svg: dark navy plate with a light-spectrum curve whose blue peak is
removed (dotted ghost) and whose warm side glows like a setting sun."""
import pathlib
root = pathlib.Path(__file__).resolve().parent.parent
BASE = 668
line = f"M196,{BASE} L436,{BASE} C506,{BASE} 520,318 604,318 C700,318 716,612 828,650"
area = f"{line} L828,{BASE} Z"
ghost = f"M236,{BASE} C276,{BASE} 284,520 312,520 C340,520 348,{BASE} 388,{BASE}"
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <linearGradient id="plate" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#16244D"/><stop offset="0.55" stop-color="#0B1430"/><stop offset="1" stop-color="#050A1C"/>
    </linearGradient>
    <linearGradient id="warm" gradientUnits="userSpaceOnUse" x1="436" y1="0" x2="828" y2="0">
      <stop offset="0" stop-color="#FFD24A"/><stop offset="0.36" stop-color="#FF9A2E"/>
      <stop offset="0.68" stop-color="#FF4F33"/><stop offset="1" stop-color="#D4162A"/>
    </linearGradient>
    <linearGradient id="fade" gradientUnits="userSpaceOnUse" x1="0" y1="318" x2="0" y2="{BASE}">
      <stop offset="0" stop-color="#0B1430" stop-opacity="0"/><stop offset="1" stop-color="#0B1430" stop-opacity="0.72"/>
    </linearGradient>
    <radialGradient id="glow" gradientUnits="userSpaceOnUse" cx="612" cy="520" r="330">
      <stop offset="0" stop-color="#FF7A2E" stop-opacity="0.42"/><stop offset="1" stop-color="#FF7A2E" stop-opacity="0"/>
    </radialGradient>
    <clipPath id="clip"><rect x="100" y="100" width="824" height="824" rx="186" ry="186"/></clipPath>
  </defs>
  <rect x="100" y="100" width="824" height="824" rx="186" ry="186" fill="url(#plate)"/>
  <g clip-path="url(#clip)">
    <rect x="100" y="100" width="824" height="824" fill="url(#glow)"/>
    <path d="{area}" fill="url(#warm)"/>
    <path d="{area}" fill="url(#fade)"/>
    <path d="{ghost}" fill="none" stroke="#6F8FE8" stroke-opacity="0.55" stroke-width="9" stroke-linecap="round" stroke-dasharray="2 22"/>
    <path d="M196,{BASE} L828,{BASE}" stroke="#FFFFFF" stroke-opacity="0.16" stroke-width="5" stroke-linecap="round"/>
    <path d="{line}" fill="none" stroke="url(#warm)" stroke-width="24" stroke-linecap="round" stroke-linejoin="round"/>
    <path d="M196,{BASE} L436,{BASE}" stroke="#FFD24A" stroke-opacity="0.9" stroke-width="24" stroke-linecap="round"/>
  </g>
  <rect x="101.5" y="101.5" width="821" height="821" rx="184.5" ry="184.5" fill="none" stroke="#FFFFFF" stroke-opacity="0.09" stroke-width="3"/>
</svg>'''
(root / "Resources/brand/AppIcon.svg").write_text(svg)
print("wrote Resources/brand/AppIcon.svg")
