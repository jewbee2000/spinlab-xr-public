# Run SpinLab XR on your Quest 2

Version 0.1 is a browser app. It renders locally on the Quest 2 in Meta Quest Browser using WebXR, with a full desktop preview for checking the station first. The USB cable provides a route to a local file server; it is not a Quest Link/PCVR session. There is no APK to install in this release.

The version 0.1 physical-headset acceptance test remains pending. The software's desktop/build tests do not establish controller behavior, comfort, or 72 Hz headset performance. Use this guide to perform that test and record feedback.

## What you need

- Quest 2, its Touch controllers, and Meta Quest Browser.
- A Windows computer and a USB-C **data** cable connected to the headset. A charging-only cable will not work for ADB.
- A current supported Node.js LTS release. Node 22 or 24 is suitable for this project's tools; [Node's release table](https://nodejs.org/en/about/previous-releases) listed both as LTS on 18 October 2026. Download from [Node.js](https://nodejs.org/en/download).
- [Android SDK Platform-Tools for Windows](https://developer.android.com/tools/releases/platform-tools), which contains `adb.exe`. Android Studio, Unity, a gaming GPU, and a Quest Link setup are not required for this browser route.
- Developer mode and USB debugging authorization on the headset. Follow [Meta's Device Setup](https://developers.meta.com/vr/documentation/native/android/mobile-device-setup/) for the current account verification, developer team, phone app, and Windows driver requirements. These are Meta's requirements for the USB debugging route, not requirements imposed by SpinLab.

The app's runtime dependencies are vendored in the project. You do not need to run `npm install`, obtain an API key, create an app account, or buy 3D assets.

## 1. Start the app on the computer

Open PowerShell in the project folder. Replace the example path with your checkout or extracted release directory:

```powershell
Set-Location -LiteralPath 'C:\Projects\spinlab-xr'
node --version
node tools/serve.mjs
```

If using an extracted portable release or a cloned repository elsewhere, change to that folder instead. Keep this terminal open. The server should print:

```text
SpinLab XR: http://localhost:8080
```

On the computer, open [http://localhost:8080](http://localhost:8080) in a modern desktop browser. Confirm that the lab appears. The desktop workflow is useful even when the browser has no immersive VR support.

If `node` is not recognized, install Node.js and open a new PowerShell window. If your Node install is already available only by an explicit executable path, run that executable in place of `node`.

## 2. Authorize Quest USB debugging

Complete [Meta's Device Setup](https://developers.meta.com/vr/documentation/native/android/mobile-device-setup/) before continuing. In the paired Meta Horizon phone app, select the headset's settings and enable Developer Mode after satisfying the account prerequisites. Connect the data cable, put on the headset, and accept the USB debugging prompt for your computer. If prompted to launch Quest Link, remain in the headset's normal interface and open Browser for this app.

The development setup stores Google's Platform-Tools in the ignored local folder `.tools\platform-tools`. These tools are not committed to the repository or included as an app runtime dependency. Open a **second** PowerShell window in the project folder and set its path:

```powershell
$spinlabAdb = Join-Path (Get-Location) '.tools\platform-tools\adb.exe'
& $spinlabAdb version
& $spinlabAdb devices
```

On another computer, download/extract Google's Platform-Tools first. For example, if extracted to `C:\Tools\platform-tools`, use `$spinlabAdb = 'C:\Tools\platform-tools\adb.exe'` instead. Every command below uses that variable. The development check found no connected ADB device; connecting and authorizing your physical Quest 2 is still required.

Expected shape of the output:

```text
List of devices attached
YOUR_HEADSET_SERIAL    device
```

If the status is `unauthorized`, put on the headset and accept USB debugging, then rerun the command. If no device appears, check the cable, developer mode, and Meta's Windows driver setup. Authorizing file access alone is different from authorizing USB debugging. Google's [ADB documentation](https://developer.android.com/tools/adb) explains device states, authorization, and selecting a serial when multiple devices are connected.

If more than one Android device is listed, use the headset serial with every subsequent command, for example:

```powershell
& $spinlabAdb -s YOUR_HEADSET_SERIAL reverse tcp:8080 tcp:8080
```

## 3. Forward localhost to the headset

With the app server still running:

```powershell
& $spinlabAdb reverse tcp:8080 tcp:8080
& $spinlabAdb reverse --list
```

Meta documents this port-reversal workflow for local Browser development. [Meta: Debug Browser content](https://developers.meta.com/vr/documentation/web/browser-remote-debugging/)

Inside **Meta Quest Browser on the headset**, type exactly:

```text
http://localhost:8080
```

Here, `localhost` is the headset. ADB forwards its port 8080 to the server on the computer. Typing the computer's Wi-Fi IP address over plain HTTP is a different connection and can leave immersive WebXR unavailable. The app needs a secure context: qualifying localhost is supported for development; a remote deployment needs valid HTTPS. [W3C Secure Contexts](https://www.w3.org/TR/secure-contexts/)

Keep the cable connected and the server running for reloads. Port reversal may need to be repeated after a disconnect/reboot. The current app has no service-worker/offline-install claim.

## 4. Enter the lab

1. Dismiss the introductory controls guide if it is open.
2. Select **Enter VR** in the page header and allow the browser's immersive-session permission if requested.
3. Look toward the station. Point either controller ray at a control and press its index trigger.
4. Check the bench height. With no dial held, left thumbstick down lowers the station and up raises it.
5. Perform the short test below. Use the headset's system interface to exit VR when finished.

The app must request immersive mode from your action; it cannot automatically enter without your input. If entry fails, record the exact message and browser version and use the troubleshooting table below.

## Controls

| Action | Quest Touch | Desktop preview |
| --- | --- | --- |
| Select a button or fixture target | Point at it and press trigger | Click the object or labeled button |
| Operate rotor/guard/probe | Point and trigger; squeeze is an additional shortcut | Use Load rotor, Home probe, or Close/Open guard |
| Adjust a dial | Hold trigger on it and rotate wrist; move thumbstick horizontally for fine adjustment | Use Probe, Trim mass, or Trim angle sliders |
| Adjust seated bench height | Left thumbstick vertically, with no dial held | Not necessary for the desktop orbit view |
| Inspect assembly | Select Explore assembly | Click Explore assembly; drag to orbit and scroll to zoom |
| Emergency stop | Select E-STOP | Click E-STOP |
| Recover/re-arm | Select RESET FAULT after zero speed and required guard action; E-stop first requires RELEASE E-STOP, then RESET FAULT | The same button changes from Release E-stop to Reset / re-arm |
| Save report | Select SAVE REPORT; exit VR and use Saved report in the page header to download the saved snapshot | Save report captures/downloads the current session; Saved report downloads the earlier snapshot |
| Restart the exercise | Select NEW SESSION at the lower right beside SENSOR FAULT | Click New session |

The initial squeeze interaction issues a fixture command; it does not let you freely grab and carry a physical rigid body. Optional haptics are feedback only and may depend on browser support. Reloading the page starts a fresh station and discards any unfinished run. The last explicitly saved report persists in this browser's local storage when permitted. Download that snapshot with **Saved report**; pressing **Save report** again replaces it with the current station snapshot. Clearing site data removes the stored report, so download a JSON file you want to keep.

## 5. First test: approximately five minutes

### Baseline

1. Begin a New session. Try **Run sweep** before loading. A specific interlock message should prevent the run.
2. Select **Load rotor**, **Home probe**, and **Close guard** in sequence. The nominal probe position is `6.00 mm`; its fictional acceptable range is `5.5–6.5 mm`.
3. Select **Run sweep**. Watch the RPM and vibration readouts. The acquisition lasts 12 simulated seconds, reaches `1,800 rpm`, then the rotor coasts to zero. Wait for zero speed before opening the guard or changing mass.
4. The baseline residual should be `18 g·mm`, with compensated imbalance position near `120°`. The instrument is synthetic; phase is a compensated rotor-position angle rather than raw accelerometer phase.

### Correct and verify

1. After the rotor reaches zero, open the guard.
2. Set Trim mass to **`0.600 g`** and Trim angle to **`300°`**. The correction radius is fixed at `30 mm`.
3. Close the guard and run another complete sweep, including coast-down.
4. The modeled residual should cancel to essentially zero and the completed exercise should report PASS. That threshold (`2 g·mm`) belongs only to this fictional exercise.
5. Select **SAVE REPORT**. In VR the app stores the report snapshot; it does not initiate a download in the headset view. Exit immersive mode, then select **Saved report** in the page header. Keep the resulting JSON for feedback. If local storage is unavailable, download the current report before closing/reloading the page.

### Fault and recovery

1. Start another sweep and select **SENSOR FAULT** in VR, or **Inject sensor fault** on desktop. Drive should be removed and the rotor should coast, with a latched fault displayed.
2. Wait for zero speed, select **RESET FAULT** in VR or **Reset / re-arm** on desktop, and home the probe again before restarting.
3. Test **E-STOP** during rotation. It removes simulated drive and latches a fault; it does not teleport the rotor to zero speed. After coast-down, select **RELEASE E-STOP** / **Release E-stop**. Then select the same control again after its label changes to **RESET FAULT** / **Reset / re-arm**. Recheck readiness and start a new run deliberately; releasing/resetting never restarts the drive automatically.
4. In a separate run, opening the guard while rotating should remove drive and latch a guard fault. After zero speed, close the guard and reset before restarting.

All hardware and interlocks in this app are simulated. This test does not operate any real motor or machine.

## Troubleshooting

| Symptom | Next step |
| --- | --- |
| `node` not recognized | Install a supported Node.js LTS or use its full executable path, then reopen PowerShell. |
| Server reports `EADDRINUSE` | Stop the older app server if it is yours. Alternatively run `node tools/serve.mjs --port 8081`, reverse `tcp:8081 tcp:8081`, and browse `http://localhost:8081`. Keep all three ports consistent. |
| `adb.exe` path does not exist | Use the folder where you extracted Google's Platform-Tools; there should be an `adb.exe` beside its companion DLLs. |
| `adb devices` shows `unauthorized` | Accept the USB debugging prompt inside the headset. Reconnect the cable if no prompt appears. |
| No device appears | Try a known data cable and another USB port; confirm Developer Mode and Meta's Windows ADB driver instructions. |
| More than one device | Add `-s YOUR_HEADSET_SERIAL` before `reverse` or other commands. |
| Page will not load in headset | Confirm the server works on the computer; check `adb devices`, repeat `reverse`, and type headset `http://localhost:8080`. |
| App loads but VR is unavailable | Use Meta Quest Browser on the headset, the localhost URL, and its immersive permission. A desktop browser without an XR runtime is expected to show the desktop preview. Do not disable browser security or trust a random HTTP LAN origin. |
| Immersive request denied | Check Browser site permissions and retry Enter VR from a new button press. Record the exact app error if it persists. |
| Controller actions fail | Confirm both controllers are awake/tracked, point at a highlighted target, and use an index trigger. Report which hand/action failed. Grip and thumbstick behavior still need physical acceptance. |
| Correction slider/dial is rejected | Wait for zero speed, clear a latched fault, mount the rotor, and open the guard before editing correction mass/angle. |
| App feels slow or text is hard to read | Record browser/OS versions and the control/panel involved. Avoid treating a desktop FPS reading as a headset performance result. |
| Download does not appear during VR | SAVE REPORT stores a snapshot. Exit immersive mode and use Saved report in the header; report browser download behavior if it still fails. |

For deeper debugging, connect desktop Chrome at `chrome://inspect/#devices` and inspect the headset's Browser tab. Useful console checks are `window.isSecureContext`, `navigator.xr`, and `navigator.xr.isSessionSupported('immersive-vr')`. Meta documents this inspection route in its [Browser debugging guide](https://developers.meta.com/vr/documentation/web/browser-remote-debugging/). Paste errors into feedback, excluding unrelated account information.

## Stop and remove the local connection

Exit immersive VR, close the page if desired, and press Ctrl+C in the serving terminal. Remove the forwarded port in the second terminal:

```powershell
& $spinlabAdb reverse --remove tcp:8080
```

No Android application was installed by these steps. You can retain or delete the project folder normally. If you later turn off Developer Mode, follow Meta's current settings instructions.

## Return useful feedback

Use the unfilled hardware record in [TEST_PLAN.md](TEST_PLAN.md), or send:

```text
App version / commit:
Quest 2 OS version:
Meta Quest Browser version:
Date and seated/standing:
Entered VR successfully? yes/no + exact error:
Controller targeting/dials/height controls:
Baseline run completed? correction pass completed?:
Guard / sensor fault / emergency-stop recovery:
Text readability (1–5, 5 best):
Comfort (1–5, 5 best) and test duration:
Stutter or tracking problems:
What you expected / what happened / reproduction steps:
Report JSON and optional recording:
```

For a performance pass, collect at least five minutes on the physical headset with a supported performance HUD or profiler and record the method. The target is 72 Hz, about 13.9 ms per frame interval. Comfort, input mapping, and text readability also need your judgment; automated tests cannot establish them.

Instructions and source links last checked on 18 October 2026. Platform menus may change. This USB testing route serves the app from the connected development computer.
