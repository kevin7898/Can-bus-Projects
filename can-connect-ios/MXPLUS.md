# OBDLink MX+ Bluetooth — development integration

Build 7 supports OBDLink MX+ through Apple's External Accessory framework and the `com.obdlink` protocol, using Bluetooth Classic/MFi. Real 2014 Jetta TDI DSG tests verified short recording sessions and Mac transfers with 20 available fields. See [JETTA_2014.md](JETTA_2014.md) for the actual signals and outstanding hardware checks. OBDLink CX (BLE), generic Bluetooth ELM327, USB and raw CAN remain separate unsupported transports.

Cancel/disconnect stops acquisition and drains an in-flight response through its prompt. Reconnect waits for canceled work to unwind, including after explicit Disconnect, then reuses the foreground EASession. Recreating the MX+ iAP data session while Bluetooth remained paired reproduced a silent connection on the physical adapter. Build 8 retains the session during app switching/locking using the External Accessory background mode; transport failure closes it. Identification begins with ATI and reviewed settings; it does not reset the adapter on every connection. A protected local journal distinguishes startup, command timeout and selection failures without reusing a previous session's diagnostic log.

## Connect on iPhone

1. Plug the MX+ into the vehicle and turn ignition on while parked. Press the adapter's Connect button and pair **OBDLink MX+** in iPhone Settings → Bluetooth. Finish pairing within its two-minute pairing window. Close other OBD apps; the adapter serves one app at a time.
2. Open CAN Connect and select the real vehicle, using manual onboarding if necessary. In **Connect → CAN recorder**, choose **OBDLink MX+ · Bluetooth**.
3. Use **Pair / reconnect MX+** if the paired adapter is disconnected, then **Refresh paired adapters**. A renamed adapter can be reconnected in iPhone Bluetooth settings. Choose the authenticated MX+ and tap **Connect selected vehicle**. Wi-Fi address/port fields are not used for Bluetooth.
4. The app opens the accessory's session, confirms standard diagnostic settings, reads VIN and supported PIDs, and starts the same measured-readings pipeline as Wi-Fi. A detected VIN must match the selected vehicle when both are present. Without a VIN, confirm the selected vehicle manually.
5. Verify sensible RPM, coolant, speed and voltage against another trusted reader, then verify recording starts automatically. Switch apps and lock/unlock the phone: build 8 should keep the same session and recording. Finish remains available. GPS remains a separate recording source.
6. Confirm the saved scanner recording and transfer it to the Mac. Bluetooth recordings retain transport provenance, original commands/replies and receipt timestamps. Only supported readings are shown; missing values stay unavailable.

## Failures to check on hardware

- No adapter: confirm power, pairing, the MX+ model and completed MFi authentication. Refresh after a few seconds. OBDLink CX/LX and unauthenticated accessories are deliberately excluded.
- Session unavailable: close OBDLink/other scan apps, reconnect in Settings and retry. If iOS still refuses an otherwise authenticated adapter, confirm manufacturer authorization for bundle ID `com.canconnect.companion` with OBD Solutions. No vendor authorization has been obtained or represented by this implementation.
- Timed out/disconnected: check ignition and Bluetooth range; the recording draft should save and stale readings clear. The saved MX+ retries automatically with backoff while available. An explicit Disconnect suppresses those retries until the accessory disappears/reappears or you connect manually. A connection to the adapter alone does not prove vehicle communication.
- Several adapters: choose the correct MX+. Its serial is remembered privately in the vehicle profile; reconnect never silently substitutes another selected adapter.

App Store distribution may require adding the app to the manufacturer's MFi product plan. A locally signed development build and simulator tests do not establish that approval or real-device compatibility. Do not copy another app's product-plan approval or claim official OBDLink certification.

References: [OBDLink MX+ specifications](https://www.obdlink.com/products/obdlink-mxp/), [official iOS quick start](https://www.scantool.net/scantool/downloads/263/mxp_qsg_ios.pdf), [OBDLink connection troubleshooting](https://support.obdlink.com/support/solutions/articles/43000724694), [Apple External Accessory](https://developer.apple.com/documentation/externalaccessory/), and [CornucopiaStreams protocol example](https://github.com/Cornucopia-Swift/CornucopiaStreams#external-accessory).
