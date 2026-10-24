# OBDLink MX+ Bluetooth — development integration

Build 3 adds OBDLink MX+ through Apple's External Accessory framework and the `com.obdlink` protocol. It uses Bluetooth Classic/MFi. OBDLink CX (BLE), generic Bluetooth ELM327, USB and raw CAN are separate transports and are not implemented here. This integration has stream-fixture coverage; real MX+ acceptance is pending.

## Connect on iPhone

1. Plug the MX+ into the vehicle and turn ignition on while parked. Press the adapter's Connect button and pair **OBDLink MX+** in iPhone Settings → Bluetooth. Finish pairing within its two-minute pairing window. Close other OBD apps; the adapter serves one app at a time.
2. Open CAN Connect and select the real vehicle, using manual onboarding if necessary. In **Connect → CAN recorder**, choose **OBDLink MX+ · Bluetooth**.
3. Use **Pair / reconnect MX+** if the paired adapter is disconnected, then **Refresh paired adapters**. A renamed adapter can be reconnected in iPhone Bluetooth settings. Choose the authenticated MX+ and tap **Connect selected vehicle**. Wi-Fi address/port fields are not used for Bluetooth.
4. The app opens the accessory's session, confirms standard diagnostic settings, reads VIN and supported PIDs, and starts the same measured-readings pipeline as Wi-Fi. A detected VIN must match the selected vehicle when both are present. Without a VIN, confirm the selected vehicle manually.
5. Verify sensible RPM, coolant, speed and voltage against another trusted reader, then record and finish. Keep CAN Connect visible; backgrounding or locking saves/stops scanner recording and disconnects. GPS remains a separate recording source.
6. Confirm the saved scanner recording and transfer it to the Mac. Bluetooth recordings retain transport provenance, original commands/replies and receipt timestamps. Only supported readings are shown; missing values stay unavailable.

## Failures to check on hardware

- No adapter: confirm power, pairing, the MX+ model and completed MFi authentication. Refresh after a few seconds. OBDLink CX/LX and unauthenticated accessories are deliberately excluded.
- Session unavailable: close OBDLink/other scan apps, reconnect in Settings and retry. If iOS still refuses an otherwise authenticated adapter, confirm manufacturer authorization for bundle ID `com.canconnect.companion` with OBD Solutions. No vendor authorization has been obtained or represented by this implementation.
- Timed out/disconnected: check ignition and Bluetooth range; the recording draft should save and stale readings clear. Reconnect explicitly. A connection to the adapter alone does not prove vehicle communication.
- Several adapters: choose the correct MX+. Its serial is remembered privately in the vehicle profile; reconnect never silently substitutes another selected adapter.

App Store distribution may require adding the app to the manufacturer's MFi product plan. A locally signed development build and simulator tests do not establish that approval or real-device compatibility. Do not copy another app's product-plan approval or claim official OBDLink certification.

References: [OBDLink MX+ specifications](https://www.obdlink.com/products/obdlink-mxp/), [official iOS quick start](https://www.scantool.net/scantool/downloads/263/mxp_qsg_ios.pdf), [OBDLink connection troubleshooting](https://support.obdlink.com/support/solutions/articles/43000724694), [Apple External Accessory](https://developer.apple.com/documentation/externalaccessory/), and [CornucopiaStreams protocol example](https://github.com/Cornucopia-Swift/CornucopiaStreams#external-accessory).
