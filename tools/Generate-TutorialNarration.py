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
SCRIPTS = [('load',
  'Meet the rotor',
  'Welcome to the wheel lab. Your mission is to make a spacecraft rotor shake less. A tiny off-center mass '
  'pulls outward each turn, causing vibration.',
  "We'll measure it, add known test masses, then cancel the shake. Grip the tray rotor and seat it upright on "
  'the spindle.'),
 ('home',
  'Reference the probe',
  "Press Home on the station to set the probe's reference position at six millimeters.",
  'This sensor measures tiny vibration without touching the rotor. Before comparing measurements, we need a '
  'repeatable distance between sensor and target.'),
 ('probe_adjust',
  'Try the micrometer',
  "Use the right stick to reach the station's right side. Grip the micrometer drum, turn to change its reading "
  'by a tenth of a millimeter, then release.',
  'Regrip as needed. One revolution moves half a millimeter.'),
 ('probe_restore',
  'Restore the reference',
  "Release the micrometer before pressing Home to restore six millimeters. We'll keep that probe position "
  'fixed.',
  'Sensor motion changes sensitivity and discards calibration. Comparing vibration requires the same '
  'measurement setup, so rehome before starting our experiment.'),
 ('open_setup',
  'Open for the dial experiment',
  "At zero speed, lift the orange guard if it is closed. We'll adjust rotor weights next.",
  'Mass changes require open access and a stopped rotor. Closing the enclosure instead prepares the station '
  'for spinning.'),
 ('mass_practice',
  'Try the mass dial',
  'With the rotor stopped and the guard open, grip the Mass dial. Twist to add at least five hundredths of a '
  'gram, then release.',
  'This changes the size of the correction weight on the selected plane.'),
 ('angle_practice',
  'Aim the correction weight',
  'Grip the Angle dial and turn the nonzero weight at least twenty degrees, then release.',
  'Mass sets how much correction you add; angle sets where around the rotor it acts. Those two values describe '
  'a correction vector.'),
 ('clear_mass',
  'Restore the bare rotor',
  'Grip Mass and twist back to zero grams, then release. Let go and regrip for extra turns if needed. Leave '
  'Angle unchanged.',
  'With no weight installed, angle creates no force. Our experiment starts with the bare rotor.'),
 ('mode_two',
  'Choose two-plane balancing',
  'Press Mode to select two-plane balancing.',
  'A thin disc can often use one correction plane. Our wheel has two separated planes: their weights can '
  "cancel both an off-center pull and a rocking effect. We'll measure both sensors."),
 ('plane_b',
  'Find plane B',
  'Press Plane to select B. Watch which rotor plane is selected.',
  'The Mass and Angle dials edit only the selected plane. Both planes influence both sensors, so changing B '
  'can affect motion measured near A, too.'),
 ('plane_a',
  'Return to plane A',
  "Press Plane again to return to A. We'll use A for our first known test mass.",
  "Selecting a plane changes which weight you're editing. It does not add a weight or take a vibration "
  'measurement.'),
 ('speed_explore',
  'Explore test speed',
  'Press Speed to try another test-speed setting. The rotor stays stopped while you choose.',
  'A faster rotor produces more force from the same off-center mass. Its support can amplify certain speeds, '
  'so consistent test conditions matter.'),
 ('speed_restore',
  'Set the working speed',
  'Press Speed until the display reads twelve hundred revolutions per minute. The settings cycle through '
  'fifteen hundred, nine hundred, and twelve hundred.',
  'Keep this working speed for baseline, both trials, and verification to compare their responses.'),
 ('guard',
  'Close the guard',
  'Grip the orange handle, lower the guard fully, then release it. Check that the station says closed.',
  'The enclosure interlock prevents starting with an open guard. Release the guard, rotor, and dials before '
  'any spin.'),
 ('preview_start',
  'Start a practice spin',
  'Press Sweep to begin a practice spin. Watch the rotor accelerate and the live vibration appear on the '
  'monitor.',
  "This first spin is only for learning the stopping controls. We'll collect our real measurements afterward."),
 ('stop',
  'Stop the practice spin',
  'Press Stop and watch the rotor coast to zero. Keep the guard closed until it stops.',
  'Stop cancels an unfinished capture. Partly collected data cannot become a trusted calibration point, even '
  'when the rotor looked steady.'),
 ('estop',
  'Try the emergency latch',
  'With the rotor stopped, press the red E-stop. Notice that the emergency state latches.',
  "Unlike a routine stop, this also discards calibration. We're practicing at zero speed before collecting "
  'data, so no balancing result is lost.'),
 ('recover',
  'Recover deliberately',
  'Press Recover at zero speed to release the latch or clear a fault. Another condition may need another '
  'press. The rotor stays stopped.',
  'Recovery removes the probe reference. Rehome and collect fresh calibration before balancing again.'),
 ('rehome',
  'Reference after recovery',
  'Press Home to reference the probe again at six millimeters. Confirm the station is ready with its guard '
  'closed.',
  'Recovery is a deliberate sequence: clear the latch, restore the reference, then request a new run.'),
 ('baseline',
  'Measure the starting shake',
  'Press Baseline and watch the time trace. Keep the guard closed through capture, analysis, and coast-down.',
  'Baseline records the starting shake in micrometers peak. Any changed measurement setup needs a fresh '
  'baseline.'),
 ('chart_order',
  'See the rotation signature',
  'Press Chart to view the order spectrum. Find the markers at one and two.',
  'One means once per revolution; two means twice. Taller peaks mean larger vibration. Our balancing '
  'calculation targets the once-per-turn response.'),
 ('open_trial',
  'Prepare a known change',
  'At zero speed, lift the orange guard handle.',
  'The baseline tells us how much the station shakes, but not which weight will fix it. A known test mass will '
  'reveal how the real measured response changes.'),
 ('trial_fit',
  'Add the A test mass',
  'With plane A selected, press Fit Trial. This adds a known quarter-gram test mass relative to the baseline.',
  'The helper preserves the original configuration on the other plane. Changing one plane at a time keeps its '
  'effect identifiable.'),
 ('close_trial',
  'Close for the A trial',
  'Lower the guard fully and release the handle. Keep the A test mass installed.',
  'Our next run uses the same speed and probe position as baseline. Only the known mass change should explain '
  'the new measured response.'),
 ('trial_measure',
  'Measure the A response',
  'Press Measure Trial A and wait for capture, analysis, and coast-down to zero.',
  'The difference from baseline shows how a known A-plane mass affects both sensors. Vibration phase describes '
  'timing relative to rotation, not simply the heavy spot.'),
 ('open_trial_b',
  'Prepare the second trial',
  "At zero speed, lift the guard again. We'll test the other correction plane.",
  'One trial cannot describe both planes independently. Our second known change supplies the missing '
  'relationship between the B-plane mass and the two sensors.'),
 ('plane_b_trial',
  'Select B for its trial',
  'Press Plane to select B before fitting the second test mass.',
  'We will compare this trial with the original baseline, not with Trial A. Independent tests let the solver '
  "separate the two planes' effects."),
 ('trial_fit_b',
  'Add the B test mass',
  'Press Fit Trial with B selected. It adds the known quarter-gram test mass on B and restores A to its '
  'baseline weight.',
  'Removing the temporary A trial prevents two simultaneous changes from confusing the calibration.'),
 ('close_trial_b',
  'Close for the B trial',
  'Lower the guard fully and release the handle, keeping the B trial installed.',
  'The two tests must use the same speed, sensor positions, and baseline. Repeatable setup lets us attribute '
  'their differences to the known mass changes.'),
 ('trial_measure_b',
  'Measure the B response',
  'Press Measure Trial B and wait for capture, analysis, and coast-down to zero.',
  'Now each known trial has measured responses at both sensors. Together they describe the cross effects '
  'needed to predict two correction weights.'),
 ('solve',
  'Predict the correction',
  'Press Solve. Read the predicted mass and angle for each correction plane on the monitor.',
  'The solver combines both measured trial effects to cancel baseline vibration. Poor conditioning means small '
  'measurement errors could greatly change that prediction.'),
 ('open_apply',
  'Open for the correction',
  'At zero speed, lift the guard. Keep the calculated solution available.',
  "We'll replace the temporary trial with the predicted correction. Leave probe position and speed unchanged: "
  'changing the measurement response would invalidate what we just learned.'),
 ('apply',
  'Install the prediction',
  'Press Apply Correction with the guard open. Watch both plane weights update to calculated total values.',
  'The helper replaces test masses and includes baseline weights correctly. This is a prediction; a fresh '
  'measurement must test it.'),
 ('close_verify',
  'Close for the speed checks',
  'Lower the guard fully and release the handle. Keep the calculated weights installed.',
  "We'll explore their response across speeds, then return to our working speed for verification. That final "
  'matched-speed measurement tests the prediction fairly.'),
 ('sweep',
  'Explore the speed response',
  'Press Sweep and watch the speed-response plot build. Wait for the full sweep and coast-down.',
  "A balanced wheel can still excite support resonance. Next we'll return to twelve hundred revolutions per "
  'minute to verify the correction.'),
 ('verify',
  'Measure the improvement',
  'Press Verify and wait through capture, analysis, and coast-down. Compare the new vibration and reported '
  'reduction with baseline.',
  'A fresh measurement tests the prediction. If reduction is poor, investigate the setup and data rather than '
  'declaring success.'),
 ('repeat',
  'Check the scatter',
  'Press Repeat without changing the setup. Wait for three measurement windows and coast-down.',
  'Compare their mean and scatter on the monitor. Repeats show consistency, but cannot reveal shared '
  'calibration error. Near zero vibration, phase becomes unreliable.'),
 ('report',
  'Keep the evidence',
  'Press Save Report to preserve your settings, measurements, correction, and diagnostic sweep.',
  "You've measured a problem, tested known changes, predicted a fix, and checked it. The saved report keeps "
  'the evidence so someone else can follow your reasoning.')]


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
    scripts_by_id = {row[0]: row for row in SCRIPTS}
    for step_id, row in manifest["clips"].items():
        _, title, instruction, science = scripts_by_id[step_id]
        expected_transcript = {"title": title, "instruction": instruction, "science": science,
                               "text": instruction + " " + science}
        if any(row.get(key) != value for key, value in expected_transcript.items()):
            raise RuntimeError(f"Stale narration transcript for {step_id}; regenerate that clip.")
        path = output / Path(row["path"]).name
        if sha256(path) != row["sha256"]:
            raise RuntimeError(f"Clip hash mismatch: {step_id}")
        if path.stat().st_size != row["bytes"]:
            raise RuntimeError(f"Clip byte-size mismatch: {step_id}")
        samples, rate = sf.read(path)
        if rate != 24000 or samples.ndim != 1 or len(samples) < rate or not np.isfinite(samples).all():
            raise RuntimeError(f"Invalid mono 24 kHz audio: {step_id}")
        if abs(len(samples) / rate - row["duration_s"]) > 0.01:
            raise RuntimeError(f"Clip duration mismatch: {step_id}")
        if np.max(np.abs(samples)) > 0.995 or np.sqrt(np.mean(samples ** 2)) < 0.005:
            raise RuntimeError(f"Clipped or effectively silent audio: {step_id}")
    if abs(sum(row["duration_s"] for row in manifest["clips"].values()) - manifest["total_duration_s"]) > 0.01:
        raise RuntimeError("Manifest total duration does not equal the decoded clip durations.")
    if sum(row["bytes"] for row in manifest["clips"].values()) != manifest["total_bytes"]:
        raise RuntimeError("Manifest total bytes does not equal its clip sizes.")
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
