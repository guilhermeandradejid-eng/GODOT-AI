#!/usr/bin/env python3
"""Tiny stand-in for a kimodo.cpp demo server (tests / trying the pipeline
without the real model). It implements the same HTTP API:

    GET  /api/models
    POST /api/generate            {"segments": [{"prompt", "frames"}...], ...}
    GET  /api/animations
    GET  /api/animations/<id>/rotations.f32   (frames x joints x XYZW, float32 LE)
    GET  /api/animations/<id>/root.f32        (frames x XYZ, float32 LE)

The "motion" is synthetic (SOMA30 skeleton): the character walks forward and
raises the left arm, so a retarget can be checked numerically.

    python3 tests/kimodo_mock.py --port 8099
"""
from __future__ import annotations

import argparse
import json
import math
import struct
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NAMES = ["Hips", "Spine1", "Spine2", "Chest", "Neck1", "Neck2", "Head", "Jaw", "LeftEye", "RightEye", "LeftShoulder", "LeftArm",
         "LeftForeArm", "LeftHand", "LeftHandThumbEnd", "LeftHandMiddleEnd", "RightShoulder", "RightArm", "RightForeArm", "RightHand",
         "RightHandThumbEnd", "RightHandMiddleEnd", "LeftLeg", "LeftShin", "LeftFoot", "LeftToeBase", "RightLeg", "RightShin", "RightFoot", "RightToeBase"]
PARENTS = [-1, 0, 1, 2, 3, 4, 5, 6, 6, 6, 3, 10, 11, 12, 13, 13, 3, 16, 17, 18, 19, 19, 0, 22, 23, 24, 0, 26, 27, 28]
# Approximate adult proportions (meters, parent-local, identity rest rotations, T-pose, +Z forward, +X left).
OFFSETS = [[0, 0, 0], [0, 0.07, 0], [0, 0.1, 0], [0, 0.1, 0], [0, 0.2, 0], [0, 0.06, 0.01], [0, 0.07, 0.01], [0, 0.0, 0.04],
           [0.03, 0.06, 0.08], [-0.03, 0.06, 0.08], [0.02, 0.2, 0.0], [0.15, 0.0, -0.02], [0.28, 0, 0], [0.26, 0, 0], [0.1, -0.02, 0.05],
           [0.18, 0, 0], [-0.02, 0.2, 0.0], [-0.15, 0.0, -0.02], [-0.28, 0, 0], [-0.26, 0, 0], [-0.1, -0.02, 0.05], [-0.18, 0, 0],
           [0.1, -0.08, 0.0], [0, -0.43, 0.0], [0, -0.42, -0.01], [0, -0.05, 0.13], [-0.1, -0.08, 0.0], [0, -0.43, 0.0], [0, -0.42, -0.01],
           [0, -0.05, 0.13]]
HIPS_HEIGHT = 0.08 + 0.43 + 0.42 + 0.05 + 0.02  # toes joint ~2 cm above the floor

STATE: dict[str, dict] = {}
LOCK = threading.Lock()


def quat_axis(ax: tuple[float, float, float], ang: float) -> tuple[float, float, float, float]:
    s = math.sin(ang / 2)
    return (ax[0] * s, ax[1] * s, ax[2] * s, math.cos(ang / 2))


def synth(frames: int) -> tuple[bytes, bytes]:
    rot = bytearray()
    root = bytearray()
    for f in range(frames):
        t = f / max(frames - 1, 1)
        for j, name in enumerate(NAMES):
            q = (0.0, 0.0, 0.0, 1.0)
            if name == "LeftArm":
                q = quat_axis((0, 0, 1), math.radians(80) * t)  # T-pose -> arm raised up (about +Z)
            elif name == "RightArm":
                q = quat_axis((0, 0, 1), math.radians(80))  # right arm down at the side
            elif name == "LeftShin":
                q = quat_axis((1, 0, 0), math.radians(30) * math.sin(math.pi * t))
            rot += struct.pack("<4f", *q)
        root += struct.pack("<3f", 0.0, HIPS_HEIGHT, 1.2 * t * frames / 30.0)
    return bytes(rot), bytes(root)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):  # quiet
        pass

    def _json(self, code: int, obj) -> None:
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/api/models":
            self._json(200, [{"id": "soma-rp-v1.1", "label": "SOMA RP v1.1 (mock)", "skeleton": "SOMA 30", "skeleton_key": "soma30",
                              "available": True, "license": "mock", "parents": PARENTS, "offsets": OFFSETS}])
            return
        if self.path == "/api/animations":
            with LOCK:
                items = [{k: v for k, v in a.items() if k not in ("rot", "root")} for a in STATE.values()]
            self._json(200, items)
            return
        parts = self.path.strip("/").split("/")
        if len(parts) == 4 and parts[:2] == ["api", "animations"]:
            with LOCK:
                a = STATE.get(parts[2])
            if a is None or a["status"] != "ready":
                self.send_error(404)
                return
            data = a["rot"] if parts[3] == "rotations.f32" else a["root"] if parts[3] == "root.f32" else None
            if data is None:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        self.send_error(404)

    def do_POST(self):
        if self.path != "/api/generate":
            self.send_error(404)
            return
        n = int(self.headers.get("Content-Length", "0"))
        req = json.loads(self.rfile.read(n) or b"{}")
        segs = req.get("segments") or [{"prompt": req.get("prompt", ""), "frames": req.get("frames", 150)}]
        for s in segs:
            if not (60 <= int(s.get("frames", 0)) <= 150) or not s.get("prompt"):
                self._json(400, {"error": "each prompt segment must be 60..150 frames and 1..4096 bytes"})
                return
        total = sum(int(s["frames"]) for s in segs)
        aid = uuid.uuid4().hex[:16]
        rot, root = synth(total)
        item = {"id": aid, "prompt": segs[0]["prompt"], "frames": total, "status": "queued", "model": req.get("model", "soma-rp-v1.1"),
                "segments": segs, "rot": rot, "root": root}
        with LOCK:
            STATE[aid] = item
        threading.Timer(1.2, lambda: item.__setitem__("status", "ready")).start()
        self._json(202, {k: v for k, v in item.items() if k not in ("rot", "root")})


def serve(port: int) -> ThreadingHTTPServer:
    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8099)
    a = ap.parse_args()
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), Handler)
    print(f"mock kimodo on http://127.0.0.1:{a.port}")
    srv.serve_forever()
