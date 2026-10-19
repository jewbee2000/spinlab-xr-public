# Offline tutorial narration

The 38-step course has one bundled neural-voice recording per instruction. A clear introduction explains the mission before asking the learner to seat the rotor: reduce the shake caused by off-center mass, using measured responses to known changes rather than guessing a heavy spot. Later recordings introduce probe geometry, correction vectors, two-plane cross effects, interlocks, amplitude and phase, order analysis, independent trials, verification, repeatability, and resonance as the learner uses them.

Each ordinary instruction has 32–38 spoken words, with 47 words for the introduction. The action and its scientific purpose form one short explanation; the popup only needs a few words. The current set contains **38 clips**, totaling **562.24 seconds** and **3,761,646 bytes**. Recordings last **11.53–17.48 seconds**. The exact transcript is retained in `native/audio/tutorial/manifest.json` and `tools/Generate-TutorialNarration.py`. The full physical learning path is in [TUTORIAL.md](TUTORIAL.md).

The voice is Kokoro v1.0 **af_heart**, an American English female synthetic voice, at speed 1.0. Generation runs locally on the workstation. Quest only plays mono 24 kHz Ogg Vorbis. No TTS model, speech inference, microphone recording, credential, or narration service is required on the headset.

## Playback and controls

Narration follows the current target. **Completing the task advances immediately, even while speech is playing.** The previous recording stops and the next instruction starts; old instructions never queue or overlap. Listen before acting to hear the full explanation. Waiting for speech is optional and never supplies completion evidence.

Some objectives require a finished outcome: release a dial after turning it, latch and release the guard, or wait for a new capture to finish analysis and coast to zero. Narration duration does not add another wait to those real requirements. Voice OFF changes only audio, leaving the same work gates.

Opening the menu or losing input focus pauses playback in place. Returning from a paused guide starts that instruction again; changing, skipping, restarting, or reviewing an instruction replaces its clip. Use **Session → Voice: On/Off** for the persistent preference and **Replay Voice** to hear the current explanation again. With the menu closed, clicking the **right stick** also replays it. Replay does not operate equipment or satisfy an objective. Motor sonification has a separate control.

The minimal callout and physical target highlight remain available with voice off. The app does not display the long transcript over the station; the repository transcript allows it to be reviewed separately.

## Generate or revise recordings

Generation is separate from normal APK builds. Committed clips allow builds and installation without model downloads or Python inference. Python 3.10–3.13 is supported by the pinned wrapper. From PowerShell at the repository root:

```powershell
python -m venv .tools/narration-venv
& .tools/narration-venv/Scripts/python.exe -m pip install kokoro-onnx==0.6.1 soundfile==0.14.0
& .tools/narration-venv/Scripts/python.exe tools/Generate-TutorialNarration.py --download
& .tools/narration-venv/Scripts/python.exe tools/Generate-TutorialNarration.py --verify
```

The generator downloads the pinned approximately 326 MB model and 28 MB voice bundle only when missing or incorrect, checks published SHA256 values, and stores them under ignored `.tools/narration`. The generation environment is ignored too. A mismatch between tutorial IDs and spoken scripts fails explicitly rather than leaving new stages unnarrated.

Edit the spoken scripts in `tools/Generate-TutorialNarration.py`, then regenerate all clips or use `--only guard solve` for selected recordings. Ordinary scripts use a physical action and one plain-language reason. The introduction supplies context before the first action. Scientific units are written for speech: “micrometers peak,” “a tenth of a millimeter,” “quarter gram,” and “once per revolution.” The generator applies safe peak scaling, short endpoint fades and silence, then encodes Ogg with bounded writes. This avoids a Windows libsndfile stack overflow encountered when encoding a long utterance in one native call.

`--verify` checks ordered stage coverage, exact transcript equality with the generator source, audio hashes, mono/sample rate, finite decoded samples, measured duration, aggregate duration/size, clipping and near-silence. Changing a script while keeping an old recording is detected. The manifest records inference/encoding package versions and file hashes; committed files are the reference when exact release bytes matter. Generation dependencies are unnecessary on CI or Quest when using existing audio.

## Sources and terms

Kokoro's model/voice release is Apache-2.0; the `kokoro-onnx` wrapper is MIT. Upstream licenses do not replace the project's own terms. Notices and complete upstream licenses are retained beside the clips in `PROVENANCE.txt`, `LICENSE-KOKORO-APACHE-2.0.txt` and `LICENSE-KOKORO-ONNX-MIT.txt`. Build-time phonemization/inference/encoding dependencies remain in the local environment and are not shipped in the APK.

The local phonemization toolchain includes **GPL-3.0 phonemizer and espeak-ng**. The MIT `espeakng-loader` wrapper loads that separate engine; espeak supplies phonemes, while Kokoro produces the neural voice. SoundFile is BSD-3-Clause and libsndfile is LGPL-2.1. Complete GPL/LGPL texts are retained as generation-tool reference notices beside the clips. These libraries and executables are absent from the Quest runtime. [Phonemizer license](https://github.com/bootphon/phonemizer/blob/master/LICENSE), [espeak-ng license](https://github.com/espeak-ng/espeak-ng/blob/master/COPYING), [libsndfile license](https://github.com/libsndfile/libsndfile/blob/master/COPYING).

Primary references: [Kokoro model card](https://huggingface.co/hexgrad/Kokoro-82M), [voice catalog](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md), [wrapper/setup](https://github.com/thewh1teagle/kokoro-onnx), [pinned model assets](https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.1), [wrapper license](https://github.com/thewh1teagle/kokoro-onnx/blob/3596b26764286a7de9d90c363e988d50578918e5/LICENSE).

## Acceptance

The operator described v0.7.0's spoken guidance and minimal prompts as substantially better, then asked for clearer beginner context and more complete interactive coverage. The revised course keeps that presentation while replacing the transcripts and removing audio-dependent progression.

Scientific wording, decoding, levels, duration, hashes, and Godot imports establish the intended content and usable files. They cannot establish perceived naturalness or pronunciation without listening. On Quest, check the new explanations, comfortable volume, intentional immediate replacement when work is completed, no overlapping voices, replay/pause behavior, and target matching. Record the APK and voice preference with feedback. Exact automated results belong in [NATIVE_VALIDATION.md](NATIVE_VALIDATION.md).
