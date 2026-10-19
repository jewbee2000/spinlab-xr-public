# Offline tutorial narration

Each of the 15 balancing instructions has one bundled neural-voice recording. It starts with the physical action, then explains the engineering reason. The popup can stay short while the learner hears the fuller explanation. The exact instruction/science transcript is in `native/audio/tutorial/manifest.json` and the generator source.

The voice is Kokoro v1.0 **af_heart**, an American English female synthetic voice, at speed 1.0. Generation runs on the workstation. Quest only plays mono 24 kHz Ogg Vorbis; no TTS model, speech inference, microphone recording, credential, or narration network service is required on the headset.

The generated set contains 15 clips totaling **309.28 seconds** and **2,064,545 bytes**. Individual recordings last 17.53–24.93 seconds. Each contains 44–56 spoken words; scientific symbols and units are written out for speech.

## Playback and controls

Narration follows the active instruction. The application waits for enabled narration to finish before consuming the automatic success dwell, so fast completed work does not cut off its explanation. Opening the menu or losing input focus pauses playback. Changing/restarting the instruction stops the previous clip; returning from a paused guide can start that instruction again. Voice OFF removes the audio wait while retaining actual-work gates.

Use **Session → Voice: On/Off** for the persistent preference and **Replay Voice** to hear the current instruction again. With the menu closed, clicking the **right stick** also replays it. Replay does not operate the laboratory or satisfy a work objective. The minimal callout, progress hint, and physical target remain available when voice is off.

## Generate or revise recordings

Generation is separate from normal APK builds. Existing clips are committed, so building/installing the app does not download a model or run Python inference. Python 3.10–3.13 is supported by the pinned wrapper. From PowerShell at the repository root:

```powershell
python -m venv .tools/narration-venv
& .tools/narration-venv/Scripts/python.exe -m pip install kokoro-onnx==0.6.1 soundfile==0.14.0
& .tools/narration-venv/Scripts/python.exe tools/Generate-TutorialNarration.py --download
& .tools/narration-venv/Scripts/python.exe tools/Generate-TutorialNarration.py --verify
```

The generator downloads the pinned approximately 326 MB model and 28 MB voice bundle only if missing or incorrect, checks the published SHA256 values, and stores them under ignored `.tools/narration`. The environment is ignored too. A tutorial-ID mismatch fails explicitly instead of leaving new stages unnarrated.

Edit the spoken scripts in `tools/Generate-TutorialNarration.py`, then regenerate all clips or use `--only guard solve` to replace selected recordings. Each script puts the action before its purpose. Scientific speech is spelled out: “micrometers peak,” “square root of two,” “alpha,” “once per revolution,” and “quarter gram.” The generator applies safe peak scaling, short fades and endpoint silence, then encodes Ogg using bounded writes. This avoids a Windows libsndfile stack overflow encountered when encoding a long utterance in one call.

`--verify` checks ordered stage coverage, hashes, mono/sample rate, finite decoded samples, measured duration, clipping and near-silence. The manifest records inference/encoding package versions and output hashes; use committed files when exact release bytes matter. Generation dependencies are unnecessary on CI or Quest when using existing audio.

## Sources and terms

Kokoro's model/voice release is Apache-2.0; the `kokoro-onnx` wrapper is MIT. Upstream licenses do not replace the project's own terms. Notices and complete upstream licenses are retained beside the clips in `PROVENANCE.txt`, `LICENSE-KOKORO-APACHE-2.0.txt` and `LICENSE-KOKORO-ONNX-MIT.txt`. Build-time phonemization/inference/encoding dependencies stay in the local environment and are not shipped in the APK.

The local phonemization toolchain includes **GPL-3.0 phonemizer and espeak-ng**. The MIT `espeakng-loader` wrapper loads that separate engine; espeak supplies phonemes, while Kokoro produces the neural voice. SoundFile is BSD-3-Clause and its encoding library libsndfile is LGPL-2.1. Complete GPL/LGPL texts are retained as generation-tool reference notices beside the clips. These libraries and executables are absent from the Quest runtime. [Phonemizer license](https://github.com/bootphon/phonemizer/blob/master/LICENSE), [espeak-ng license](https://github.com/espeak-ng/espeak-ng/blob/master/COPYING), [libsndfile license](https://github.com/libsndfile/libsndfile/blob/master/COPYING).

Primary references: [Kokoro model card](https://huggingface.co/hexgrad/Kokoro-82M), [voice catalog](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md), [wrapper/setup](https://github.com/thewh1teagle/kokoro-onnx), [pinned model assets](https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.1), [wrapper license](https://github.com/thewh1teagle/kokoro-onnx/blob/3596b26764286a7de9d90c363e988d50578918e5/LICENSE).

## Acceptance

The spoken scripts received a scientific wording review. Decoding, levels, duration, hashes and Godot import checks establish usable files; perceived naturalness and pronunciation require listening. The available agent audio-input path cannot listen to these recordings. On Quest, check clear units, no abrupt cuts, comfortable volume, no overlapping stages, pause/replay behavior, and automatic progression. Record the exact APK and voice preference with feedback. Motor sonification and narration use separate controls.
