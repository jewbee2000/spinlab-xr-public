#!/usr/bin/env python3
"""Generate the bundled SpinLab tutorial voice locally; no runtime TTS service.

Install generator dependencies in an ignored environment:
  python -m venv .tools/narration-venv
  .tools/narration-venv/Scripts/python -m pip install kokoro-onnx==0.6.1 soundfile==0.14.0
  .tools/narration-venv/Scripts/python tools/Generate-TutorialNarration.py --download
Only the resulting clips, transcripts, manifest and notices ship in the app.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import math
from pathlib import Path
import re
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
MODEL_RELEASE = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/"
ASSETS = {
    "kokoro-v1.0.onnx": "beb0d1848dee9a49da392cc3df26958d46cfa35d321edf434f52949153f0df3a",
    "voices-v1.0.bin": "bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d",
}
# Explicit spoken scripts avoid pronunciation of mathematical glyphs, units,
# abbreviations and formatting intended for a visual display.
SCRIPTS = [
    ("load", "Seat the rotor upright", 
     "Grip the rotor in the tray, carry it upright over the spindle, and release to seat it. If it is already seated, leave it in place.",
     "Unbalance is mass times radius. Its rotating force grows with the square of speed. We will measure that response, calculate a correction, and test it."),
    ("home", "Reference the vibration probe",
     "With the rotor loaded and stopped, press the physical Home button. Confirm the probe reads six millimeters. Press Home now, even if an earlier reference is displayed.",
     "A repeatable sensor position makes the calibration meaningful. Homing or changing probe position, speed, or mode discards the previous calibration."),
    ("guard", "Latch the enclosure",
     "Grip the orange handle, lower the guard fully, then release. Check that the interlock says closed, and let go of every fixture handle.",
     "The interlock inhibits starting until the guard is closed and the controls are released. This does not certify real machinery containment."),
    ("baseline", "Measure the baseline",
     "Press Baseline on the station. Keep the guard closed, and wait for capture, analysis, and coast-down to zero. Stop aborts an incomplete capture.",
     "This is the reference vibration before the trial mass. Displacement is in micrometers peak. For a sine wave, divide peak by the square root of two to get root mean square amplitude."),
    ("open_trial", "Open for the known trial",
     "Once the spindle reads zero, grip the orange handle and lift the guard. Leave the baseline setup unchanged until the known trial is installed.",
     "Baseline and trial must use the same speed, correction radius, and sensor setup. Otherwise their difference would mix the trial effect with a changed measurement system."),
    ("trial_fit", "Install the known trial",
     "With the guard open and plane A selected, press Fit Trial on the station. The helper adds a known quarter-gram trial relative to the baseline.",
     "This known change reveals how unbalance affects vibration. Keeping the other plane at its baseline makes the calibration change independent."),
    ("close_trial", "Latch for Trial A",
     "Lower the orange guard handle fully, release your grip, and check closed. Keep the trial mass installed for the next measurement.",
     "Closing the guard prepares the apparatus; it does not measure anything. The trial capture must observe the known mass at exactly the baseline setup and speed."),
    ("trial_measure", "Measure Trial A",
     "Press Measure Trial A on the station. Wait for the new capture, analysis, and coast-down to zero. An old trial result cannot replace this measurement.",
     "Subtracting the baseline response isolates the known trial's effect. Tachometer-referenced analysis separates the once-per-revolution response from offset and second-harmonic motion."),
    ("solve", "Calculate the correction",
     "At zero speed, press Solve. Read the calculated correction mass, angle, and condition information on the analyzer. Rejected trial data must be measured again.",
     "The influence coefficient, alpha, is the response change divided by trial unbalance. Correction is minus the baseline response divided by alpha. This accounts for support phase, rather than guessing the heavy spot."),
    ("open_apply", "Open for correction",
     "At zero speed, lift the orange guard handle. Keep the calculated solution available. Do not change probe geometry or test speed.",
     "The correction depends on the calibrated response of the apparatus. Changing the sensor or support can invalidate that sensitivity, even if a displayed mass still looks plausible."),
    ("apply", "Install the calculated correction",
     "With the guard open, press Apply Correction on the station. The helper removes the trial configuration and installs the total calculated masses.",
     "The correction is added to the baseline mass vector, not to the temporary trial mass. This is still a prediction; a new measurement must test it."),
    ("close_verify", "Latch for verification",
     "Lower the guard fully and release the handle. Keep the calculated correction installed, and confirm closed before measuring.",
     "Single-plane correction targets sensor A at one speed. Sensor B can still show vibration. Only a fresh measurement can tell us whether the installed correction works."),
    ("verify", "Verify with a fresh measurement",
     "Press Verify on the station. Wait through analysis and coast-down to zero, then inspect the measured reduction. A low reduction is a result to diagnose and retry.",
     "Fresh verification tests the installed correction. Old results or changed settings do not count. Near zero amplitude, phase becomes unobservable, rather than a useful correction direction."),
    ("repeat", "Check repeatability",
     "Press Repeat with the setup unchanged. Wait for all three measurement windows and coast-down. Read the mean amplitude, standard deviation, and Type A standard error.",
     "Standard deviation describes scatter. Dividing it by the square root of three gives the standard error of the mean. These simulated repeats do not measure calibration bias or total uncertainty."),
    ("report", "Save the evidence",
     "Press Save Report on the station and confirm the saved path. The guide finishes after the success message, while your laboratory data stay available.",
     "The report links settings, accepted measurements, calculations, events, and limits. Keep it as evidence of this synthetic exercise. Guide completion can include skips; it does not certify competence or equipment safety."),
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def checked_asset(cache: Path, name: str, download: bool) -> Path:
    path = cache / name
    expected = ASSETS[name]
    if path.exists() and sha256(path) == expected:
        return path
    if not download:
        raise RuntimeError(f"Missing/incorrect {path}; run with --download to retrieve the pinned asset.")
    cache.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".part")
    request = urllib.request.Request(MODEL_RELEASE + name, headers={"User-Agent": "SpinLab-Narration-Generator/1"})
    print(f"Downloading {name}...", flush=True)
    with urllib.request.urlopen(request, timeout=120) as response, temporary.open("wb") as output:
        while block := response.read(1024 * 1024):
            output.write(block)
    if sha256(temporary) != expected:
        temporary.unlink()
        raise RuntimeError(f"SHA256 mismatch for {name}; the unverified download was removed.")
    temporary.replace(path)
    return path


def check_step_coverage() -> None:
    source = (ROOT / "native/scripts/lab_tutorial.gd").read_text(encoding="utf-8")
    actual = re.findall(r'_step\("([a-z_]+)"', source)
    expected = [item[0] for item in SCRIPTS]
    if actual != expected:
        raise RuntimeError(f"Narration/current tutorial step mismatch: {actual!r} != {expected!r}")


def verify_manifest(output: Path) -> None:
    import numpy as np
    import soundfile as sf
    manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
    if list(manifest["clips"]) != [item[0] for item in SCRIPTS]:
        raise RuntimeError("Manifest step coverage/order does not match source scripts.")
    for step_id, row in manifest["clips"].items():
        path = output / Path(row["path"]).name
        if sha256(path) != row["sha256"]:
            raise RuntimeError(f"Clip hash mismatch: {step_id}")
        samples, rate = sf.read(path)
        if rate != 24000 or samples.ndim != 1 or len(samples) < rate or not np.isfinite(samples).all():
            raise RuntimeError(f"Invalid mono 24 kHz audio: {step_id}")
        if abs(len(samples) / rate - row["duration_s"]) > 0.01:
            raise RuntimeError(f"Clip duration mismatch: {step_id}")
        if np.max(np.abs(samples)) > 0.995 or np.sqrt(np.mean(samples ** 2)) < 0.005:
            raise RuntimeError(f"Clipped or effectively silent audio: {step_id}")
    print(f"Verified {len(manifest['clips'])} clips, {manifest['total_duration_s']:.2f} seconds.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download", action="store_true", help="Download only missing pinned model/voice files into ignored cache.")
    parser.add_argument("--verify", action="store_true", help="Check existing generated clips and their manifest without inference.")
    parser.add_argument("--only", nargs="*", choices=[row[0] for row in SCRIPTS], help="Regenerate selected clips and merge into existing manifest.")
    parser.add_argument("--voice", default="af_heart")
    parser.add_argument("--speed", type=float, default=1.0)
    parser.add_argument("--cache", type=Path, default=ROOT / ".tools/narration")
    parser.add_argument("--output", type=Path, default=ROOT / "native/audio/tutorial")
    args = parser.parse_args()
    check_step_coverage()
    if args.verify:
        verify_manifest(args.output)
        return
    if not math.isfinite(args.speed) or not 0.8 <= args.speed <= 1.2:
        raise RuntimeError("Speech speed must be finite and between 0.8 and 1.2.")
    import numpy as np
    import soundfile as sf
    from kokoro_onnx import Kokoro
    model = checked_asset(args.cache, "kokoro-v1.0.onnx", args.download)
    voices = checked_asset(args.cache, "voices-v1.0.bin", args.download)
    synthesizer = Kokoro(str(model), str(voices))
    args.output.mkdir(parents=True, exist_ok=True)
    old_manifest = args.output / "manifest.json"
    clips = json.loads(old_manifest.read_text(encoding="utf-8"))["clips"] if args.only and old_manifest.exists() else {}
    for step_id, title, instruction, science in SCRIPTS:
        if args.only and step_id not in args.only:
            continue
        text = instruction + " " + science
        print(f"Synthesizing {step_id} ({len(text.split())} words)...", flush=True)
        samples, rate = synthesizer.create(text, voice=args.voice, speed=args.speed, lang="en-us")
        samples = np.asarray(samples, dtype=np.float32)
        if rate != 24000 or samples.ndim != 1 or not np.isfinite(samples).all() or len(samples) < rate:
            raise RuntimeError(f"Unexpected inference output for {step_id}.")
        # Consistent safe peak with gentle endpoints; no lossy time stretching.
        peak = float(np.max(np.abs(samples)))
        if peak <= 0.001:
            raise RuntimeError(f"Silent inference output for {step_id}.")
        samples *= min(0.88 / peak, 2.0)
        fade = min(int(rate * 0.012), len(samples) // 2)
        samples[:fade] *= np.linspace(0, 1, fade)
        samples[-fade:] *= np.linspace(1, 0, fade)
        samples = np.concatenate([np.zeros(int(rate * 0.12), dtype=np.float32), samples, np.zeros(int(rate * 0.24), dtype=np.float32)])
        path = args.output / f"{step_id}.ogg"
        # Bounded writes avoid a Windows libsndfile/Vorbis stack overflow
        # when a complete longer utterance is passed in one native call.
        with sf.SoundFile(path, "w", samplerate=rate, channels=1, format="OGG", subtype="VORBIS") as output_audio:
            for start in range(0, len(samples), 4096):
                output_audio.write(samples[start:start + 4096])
        decoded, decoded_rate = sf.read(path)
        clips[step_id] = {
            "path": f"res://audio/tutorial/{step_id}.ogg", "title": title,
            "instruction": instruction, "science": science, "text": text,
            "duration_s": round(len(decoded) / decoded_rate, 6), "sample_rate_hz": decoded_rate,
            "channels": 1, "codec": "Ogg Vorbis", "bytes": path.stat().st_size,
            "sha256": sha256(path), "voice": args.voice, "speed": args.speed,
            "peak_dbfs": round(20 * math.log10(float(np.max(np.abs(decoded)))), 3),
            "rms_dbfs": round(20 * math.log10(float(np.sqrt(np.mean(decoded ** 2)))), 3),
        }
        print(f"  {clips[step_id]['duration_s']:.2f}s, {path.stat().st_size} bytes", flush=True)
    clips = {step_id: clips[step_id] for step_id, *_ in SCRIPTS if step_id in clips}
    manifest = {
        "schema": "spinlab-tutorial-narration-v1", "language": "en-US", "voice": args.voice,
        "voice_description": "Kokoro af_heart synthetic American English female voice" if args.voice == "af_heart" else args.voice,
        "model": "hexgrad/Kokoro-82M v1.0", "model_license": "Apache-2.0",
        "model_asset_url": MODEL_RELEASE + model.name, "model_sha256": sha256(model),
        "voices_asset_url": MODEL_RELEASE + voices.name, "voices_sha256": sha256(voices),
        "generator": "tools/Generate-TutorialNarration.py", "generator_license": "project LICENSE; all rights reserved",
        "packages": {name: importlib.metadata.version(name) for name in ["kokoro-onnx","onnxruntime","phonemizer","espeakng-loader","numpy","soundfile"]},
        "runtime_note": "Pre-generated local audio. Quest performs no speech inference and sends no narration text or audio to a service.",
        "total_duration_s": round(sum(row["duration_s"] for row in clips.values()),6),
        "total_bytes": sum(row["bytes"] for row in clips.values()), "clips": clips,
    }
    old_manifest.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if len(clips) == len(SCRIPTS):
        verify_manifest(args.output)

if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError) as error:
        print(f"Narration generation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
