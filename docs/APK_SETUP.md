# Install and test the native Quest 2 APK

These instructions are for the **v0.4 standalone Android/OpenXR app** with its Learn tutorial, visible Touch-controller gloves, and direct interactions. The older browser instructions remain in [INSTALL_QUEST2.md](INSTALL_QUEST2.md). After installation, the native app runs on the headset without a local web server, Quest Link, or a tethered gaming PC.

Instructions checked 18 October 2026. Meta may change menu names. A physical Quest 2 smoke test confirmed v0.2's lab, controller buttons, and spinning rotor; v0.3 installed successfully. Direct-hand behavior, report retrieval, and sustained performance remain unconfirmed. Version 0.4 installed successfully and its tutorial requires its own physical acceptance; installation does not establish readability or interaction quality. Build/install evidence belongs in [NATIVE_VALIDATION.md](NATIVE_VALIDATION.md).

## 1. Enable developer mode and authorize this computer

On your phone, use the **same Meta account** that owns the headset:

1. Open the [Meta developer sign-up](https://developers.meta.com/horizon/sign-up/) if this account is not registered. Complete Meta's account verification and developer-team steps using Meta's official account interface.
2. In the **Meta Horizon** app, select the headset icon, your paired **Quest 2**, **Headset Settings**, then **Developer Mode**. Turn it on. If Meta asks for a developer team, finish that account prerequisite first.
3. Keep the headset awake. Connect a USB-C **data-capable** cable directly to the PC.
4. Put on the headset. When **Allow USB debugging?** appears, select **Always allow from this computer**, then **Allow**. File-access/MTP permission is a separate prompt.
5. If the debugging prompt is absent, check the headset's **Settings → Developer → MTP Notification** toggle, reconnect the cable, and check again.

These are Meta's current device-development requirements. A missing developer toggle is an account/device setup issue; rebuilding the APK cannot resolve it. [Meta, *Test your app on your device*](https://developers.meta.com/vr/documentation/android-apps/enable-developer-mode/), [developer-verification FAQ](https://developers.meta.com/vr/faqs/).

## 2. Confirm the connection

In PowerShell at the project root:

```powershell
Set-Location -LiteralPath 'C:\Projects\spinlab-xr'
$spinlabAdb = Join-Path (Get-Location) '.tools\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $spinlabAdb)) {
    $spinlabAdb = Join-Path (Get-Location) '.tools\android-sdk\platform-tools\adb.exe'
}
& $spinlabAdb devices -l
```

Replace the example checkout directory with your own. If the project uses another SDK location, set `$spinlabAdb` to that SDK's `platform-tools\adb.exe`. A working connection lists the Quest serial followed by **`device`**. Keep that serial private when posting public screenshots.

| Result | Action |
| --- | --- |
| `device` | Ready to install. |
| `unauthorized` | Accept the debugging prompt inside the headset, then retry. |
| Empty device list | Check developer mode, an awake headset, a data cable, and another direct USB port. On Windows, install [Meta's ADB driver](https://developers.meta.com/horizon/downloads/package/oculus-adb-drivers/) if the ADB interface is absent. |
| `offline` | Reconnect the device and restart it if needed; retry the same SDK copy of ADB. |
| Several devices | Add `-s YOUR_QUEST_SERIAL` immediately after `$spinlabAdb` in each command. |

Avoid running competing copies of ADB from SideQuest, Android Studio, and other SDKs. [Android's ADB guide](https://developer.android.com/tools/adb) describes authorization, device states, and serial selection. A USB 3 connection is useful for large transfers but is not a requirement for installing this APK; the cable must carry data.

On Windows, extract the official Meta driver package and install `android_winusb.inf` with administrator approval. If Windows still lists the device as **ADB Interface** with `winusb.inf` and ADB remains empty, the package may be installed without being assigned to that interface. In Device Manager, right-click **ADB Interface** → Update driver → Browse my computer → Let me pick → Have Disk; select that INF and **Oculus Composite ADB Interface**. Reconnect and approve USB debugging. Select the ADB interface rather than the separate XRSP or MTP interface.

If Windows retains its generic WinUSB driver and omits the ADB device-interface registration, `tools/Repair-Quest-Adb.ps1` diagnoses that specific condition without changing anything by default. Its `-Apply` mode requires an administrator PowerShell: it backs up the selected interface's registration under `.local`, adds the standard ADB interface GUID from Meta's INF, and restarts only that interface. It requires exactly one connected Meta interface with the ADB class/subclass/protocol and preserves the MTP and XRSP interfaces. Run it only for the matching diagnosis. [Microsoft WinUSB device-interface registration](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/winusb-installation).

The repository includes helpers: `tools/Install-APK.ps1` installs and launches `com.godot.game.GodotAppLauncher` with Meta's VR category; `tools/Pull-Quest-Reports.ps1` retrieves saved JSON from the development app. The Meta driver package is a local setup dependency and is not part of the source or APK.

## 3. Install the built APK

The v0.4 build output is `artifacts/SpinLabXR-v0.4.0.apk` and its Android package is `us.teitelbaum.spinlabxr`. Build it with `tools/Build-APK.ps1`, or place the matching downloaded release APK at that path. In the same PowerShell window:

```powershell
$spinlabApk = Join-Path (Get-Location) 'artifacts\SpinLabXR-v0.4.0.apk'
Test-Path -LiteralPath $spinlabApk
& $spinlabAdb install -r $spinlabApk
```

`Success` means Android accepted the installation. `-r` updates the same signed app while retaining its data. A signature mismatch requires the matching signing key or an uninstall; uninstalling removes its saved app data, so export reports first. Do not blindly uninstall other packages.

Put on the headset, open **Library**, select **Unknown Sources**, and choose **SpinLab XR**. That section may appear only after the first successful sideload. Keep Quest Link closed for this standalone test. The app should fill the immersive view with tracked stereo rendering rather than appear as a flat Android panel.

## 4. First physical-headset acceptance run

Start seated or standing with a clear boundary and both Touch controllers awake. **Keep holding the controllers.** The gloves use their tracked poses and inferred finger animation; you do not need to enable optical hand tracking in the headset settings.

On a fresh installation, **LEARN** opens as the fifth control-panel tab. Read WHAT and WHY, then choose Next or Practice. Practice opens the real control menu and leaves the current instruction on the compact coach board; it does not operate the fixture. Next on practical pages becomes available only after the required accepted state, and never advances automatically.

Choose **Skip for now** to enter the lab without changing its data. Set **STARTUP: OFF** if you do not want the tutorial on later launches. Reopen the Learn tab manually and use Restart at any time; neither resets your measurements. Completing the final page also turns startup off. Back, Skip lesson, and Skip for now let you leave a practical objective unmet. [TUTORIAL.md](TUTORIAL.md) describes all 23 pages and the persistence behavior.

| Action | Version 0.4 headset control |
| --- | --- |
| Push a menu button | Reach the visible index tip toward its front face and push through its short travel. Keep the index trigger released to extend the virtual finger. Withdraw before another press. A successful actuation gives one haptic click. |
| Hold a nearby object/handle | Move the palm close until the `GRIP` hint appears, then squeeze and hold the controller's side grip. Release to let go. |
| Load the rotor | Grip the tray rotor, carry it upright and centered over the spindle, then release. An unsuitable placement returns it to the tray. |
| Open/close the guard | Grip the orange handle nearby. Lift the counterbalanced enclosure to open it; lower it fully and release to latch the interlock. |
| Adjust a dial | Grip the nearby dial and rotate your wrist about its axis. The probe moves 0.5 mm per turn, mass changes 0.5 g per turn, and the angle dial follows the turn directly. Release to finish; nearby physical ± buttons make small increments. Thumbsticks do not turn dials. |
| Change menu/chart | Short B/Y press cycles Operate, Balance, Analyze, Session, and Learn; A/X cycles analyzer charts. |
| Return to the current lesson | Use OPEN LESSON while the objective is unmet, or LESSON / NEXT when ready. The Learn tab also returns to the active page. |
| Use menu reach assist | Hold B/Y for about one second (0.85 s threshold), or select the Session-menu reach-assist control. Point the ray and use the index trigger for menu buttons. It does not remotely grab handles or load the rotor. |
| Place the station within reach | Left thumbstick up/down changes bench height while no handle is held. The Session menu provides height, near/far distance, and recenter controls. Withdraw your hand after moving/recentering the station before the next press. |

In XR, the **Load Rotor** and **Open/Close Guard** menu buttons explain the physical gesture; they do not move that mechanism for you. Motor sonification starts muted. When tracking quality drops or a system menu interrupts the app, hands/contact are suspended and active holds are cancelled; release the grip and approach again after tracking returns.

Follow Learn for the guided first exercise, or use this manual single-plane sequence:

1. Grip the tray rotor, carry it upright to the spindle, and release to seat it. Push **Home Vibration Probe**.
2. Grip the orange guard handle, lower fully, and release to latch. Push **Record Baseline**; wait for acquisition and coast-down to finish.
3. Lift the guard with its handle. In Balance, push **Fit Known Trial**, lower/latch the guard, then push **Measure Trial A**.
4. After coast-down, push **Solve**. Open the guard physically and push **Fit Calculated Correction**; this replaces the trial mass with the calculated total correction.
5. Lower/latch the guard and push **Verify**. Keep the measured baseline, trial, solution, and independent verification results for feedback.

For two-plane mode, acquire a fresh baseline, fit and measure the plane-A trial, switch active plane to B, and fit/measure its independent trial before solving. The trial helper restores the other plane to its baseline masses; records retain the actual installed vectors. The scientific methods are unchanged from v0.2.

Check the new interactions as well as the lab sequence:

1. Confirm both gloves follow your hands naturally and their visible index tips meet the buttons where you expect. Check text and graph readability while reaching.
2. Press with each hand, hold a button depressed, then withdraw and press again. Holding should produce one command. Try a side/back approach; it should not actuate the button.
3. Grip/carry/release the rotor, lift/latch the guard, and turn each dial. Confirm holding any mechanism inhibits a new acquisition. Check rejection of mass changes or opening the guard while the rotor is moving.
4. Try running before setup, plus deliberate sensor/tach faults and E-stop recovery. Reset/release must not restart the rotor automatically.
5. Change menu, move/recenter the station, and briefly interrupt tracking with the headset's system interface. Existing contact must not become a new press; reacquire the target deliberately.
6. Try Learn's first-time sequence, Practice/return, disabled Next, Back/Skip controls, and restart during existing work. Check the startup preference across an app relaunch and verify that a page change under a fingertip does not cause a press. Record any truncated text or unclear next action.
7. Save a report and use section 5 to retrieve it. Saving/retrieving on physical v0.2 remains unconfirmed; no files were available in the earlier retrieval check. Check this explicitly in the installed v0.4 build before relying on the export.
8. Run for at least five minutes through representative pressing, carrying, dial adjustment, lesson navigation, and analysis. Observe comfort, frame pacing, and controller responsiveness. The Quest 2 starting target is 72 Hz (about 13.9 ms per frame interval). The earlier v0.2 short runtime sample and a desktop FPS counter do not establish v0.4 sustained performance.

Report what the headset actually does. An APK build, manifest inspection, or numerical unit test does not prove that the physical-controller and rendering checks passed.

## 5. Logs and report retrieval

Before reproducing a crash, save the existing relevant log if needed. Then capture a fresh session without clearing unrelated device logs:

```powershell
& $spinlabAdb logcat -v threadtime 'godot:V' 'Godot:V' 'AndroidRuntime:E' '*:S' > .\artifacts\quest-logcat.txt
```

Leave the terminal collecting while reproducing the issue, then press **Ctrl+C**. Logs can contain unrelated device/app details: review them before posting outside the private project.

For a debuggable build, Android's `run-as` can inspect the app's internal report directory after the exact package ID is known:

```powershell
& $spinlabAdb shell run-as us.teitelbaum.spinlabxr ls files
```

Use the app's report export or the release's retrieval script when supplied. `adb pull` does not automatically have permission to read private internal app storage, and release builds may disallow `run-as`. A native `user://` report path is inside the app sandbox; it is not a Windows path.

From the project root, run `.\tools\Pull-Quest-Reports.ps1` for this signed development build. Reports are written to `artifacts/quest-reports`. The helper correctly reads `files/reports` relative to the app's data directory through `run-as`; save at least one report in the app first. In Godot 4.7.2, Android `user://` resolves through `OS_Android::get_user_data_dir()` and the Java wrapper to `GodotIO.getDataDir()`, which calls Android `Context.getFilesDir()` for internal app files. This is separate from the external-files location returned by `getSystemDir()`. Android's `run-as` changes its working directory to the package's data directory, so an absolute `/data/...` path need not be hard-coded. [Godot 4.7.2 Android OS source](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/android/os_android.cpp#L697), [JNI wrapper](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/android/java_godot_io_wrapper.cpp#L114), [GodotIO.java](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/android/java/lib/src/main/java/org/godotengine/godot/GodotIO.java#L151), [Android run-as source](https://android.googlesource.com/platform/system/core/+/refs/heads/android14-qpr3-s12-release/run-as/run-as.cpp).

## Troubleshooting

| Symptom | Next useful evidence/action |
| --- | --- |
| Developer Mode toggle absent | Confirm the owning account is registered/verified and belongs to a developer team in Meta's dashboard, then reopen the phone app. |
| No debugging prompt | Recheck Developer Mode after the OS update, keep the headset awake, toggle MTP Notification as described above, and reconnect a known data cable. |
| Windows sees storage but ADB sees nothing | File transfer and ADB use distinct interfaces; check the Meta ADB driver and debugging authorization. |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | Installed app has another signing key. Preserve reports before removing only the matching SpinLab package or install the correctly signed update. |
| `INSTALL_FAILED_OLDER_SDK` | Record `adb shell getprop ro.build.version.sdk` and the APK minimum SDK. Rebuild with a supported minimum rather than bypassing platform checks. |
| App appears as a flat panel or fails XR initialization | Capture logs and inspect APK manifest VR/immersive categories, OpenXR runtime discovery, and ARM64 libraries. |
| Black screen or immediate exit | Keep headset awake; record exact app version and collect launch logs. Shader, runtime, and script errors are distinguishable in logs. |
| One controller does nothing | Confirm tracking in the Meta home interface, wake both controllers, and record hand/button/action. |
| Gloves disappear or a hold is cancelled | The app requires current high-quality controller tracking. Keep the controllers visible to the headset, release grip, and approach again when the gloves return. |
| A direct button does not press | Release the index trigger to extend the visible finger, approach from the front, and withdraw far enough between attempts. Use Session height/distance/recenter or hold B/Y for menu reach assist. |
| Load/Guard menu button only shows a hint | In XR these controls teach the gesture. Grip/carry the actual tray rotor or grip/lift/lower the orange guard handle. Reach assist does not replace those physical actions. |
| Rotor returns to the tray | Release it upright and centered over the spindle with the guard open and spindle stopped. |
| Guard remains unlatched | Lower the handle fully before releasing it. A partially raised counterbalanced guard remains open. |
| Thumbstick does not adjust a dial | The native app uses a nearby grip plus wrist rotation; the physical ± buttons offer fine increments. |
| Learn's Next is disabled | Read its hint, choose Practice, and complete the actual action; a rejected or interrupted run does not count. Use Back, Skip lesson, or Skip for now when you prefer to leave it. |
| Learn opens on every launch | In Learn, select STARTUP: OFF. Skip for now leaves that preference unchanged. Learn remains available manually. |
| Tutorial settings error | Record the full message. Continue with the lab if useful; its measurements and interlocks are separate from tutorial preferences. |
| Text stutters or view feels uncomfortable | Record the plot/panel, operating scenario, headset OS, and duration; report perceived discomfort promptly. |

## Rebuilding from source

The project is `native/project.godot` and its export preset is **Quest 2**. Use the checked-in build tooling where available. For a manual Windows setup, install **Godot 4.7.2 stable** and its matching non-.NET export templates, **OpenJDK 17**, Android Platform-Tools, and the SDK command-line tools. The exact 4.7.2 Gradle template pins **Android Platform 36**, **Build-Tools 36.1.0**, and **NDK 29.0.14206865**. Install these versions for this build. Gradle 8.11.1 is supplied through its wrapper. The project targets SDK 35 with minimum SDK 29, while compiling against Platform 36; these are distinct settings. The general 4.7 export guide still lists older Android packages, so the tagged template is the authority for reproducibility. [Godot Android export guide](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html), [4.7.2 Gradle configuration](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/android/java/app/config.gradle), [Gradle wrapper pin](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/android/java/gradle/wrapper/gradle-wrapper.properties).

Set Godot's **Editor Settings → Export → Android** Java SDK Path and Android SDK Path. Native XR requires **OpenXR enabled**, **XR shaders enabled**, a tracked `XROrigin3D`/`XRCamera3D` scene, and correctly bound controller action maps. The APK preset should select ARM64 and OpenXR. If using the official **OpenXR Vendors 5.1.0** Meta plugin, install the Android Gradle build template and select **Enable Meta Plugin**, with Quest 2 support. The final APK manifest must identify an immersive Quest/OpenXR activity; the generic Android activity alone is insufficient evidence. [Godot XR setup](https://docs.godotengine.org/en/4.7/tutorials/xr/setting_up_xr.html), [vendors release](https://github.com/GodotVR/godot_openxr_vendors/releases/tag/5.1.0-stable).

Use `tools/Build-APK.ps1` after installing the template. It exports the template's `.GodotApp` activity as well as the generated launcher alias so Meta's VR intent can resolve correctly. It keeps `show_as_launcher_app=false`: the lab must not become a replacement home launcher. Controller nodes use Godot's `left_hand`/`right_hand` tracker aliases and then select their `aim` or `grip` pose; OpenXR action-map paths remain `/user/hand/left` and `/user/hand/right`.

Keep local SDKs, downloaded binaries, generated templates, APKs, signing keys, and machine paths out of source commits except intentional release artifacts. Debug signing is suitable for this private device test. A future store release needs stable release signing and its own submission review.

## Feedback to return

```text
APK version / commit:
Quest 2 OS version:
Developer mode and adb state:
Installed and launched immersive? exact error if any:
Both gloves / fingertip alignment / direct presses and retract:
Rotor carry + upright seating / guard lift + full latch / wrist dials:
Reach assist / menu cycling / height, distance, and recenter:
Learn page / WHAT-WHY readability / Practice and return / Next gating:
Skip for now / startup OFF persistence / manual restart:
Tracking interruption and recovery:
Readable text and seated/standing comfort:
Baseline → trial(s) → correction → independent verification:
Fault and recovery behavior:
Report saved/exported:
Five-minute run: stutter, tracking, comfort, battery/thermal observations:
Reproduction steps, expected behavior, actual behavior:
Relevant log/report files:
```
