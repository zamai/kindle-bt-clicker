// kturn: turn Kindle pages over Bluetooth by nudging the volume of the "Kindle PW5"
// CoreAudio output device. macOS sends that as AVRCP SetAbsoluteVolume; the Kindle's
// kindle-hid-passthrough media remote maps volume up -> PageDown, down -> PageUp.
// Does not change the default output device.
//   kturn next|prev [count]      kturn list
import CoreAudio
import Foundation

func prop(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
          _ el: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: el)
}
func devices() -> [AudioDeviceID] {
    var a = prop(kAudioHardwarePropertyDevices); var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size)
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids)
    return ids
}
func name(_ d: AudioDeviceID) -> String {
    var a = prop(kAudioObjectPropertyName); var n: Unmanaged<CFString>?; var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    AudioObjectGetPropertyData(d, &a, 0, nil, &size, &n)
    return (n?.takeRetainedValue() as String?) ?? "?"
}
func volAddr(_ ch: UInt32) -> AudioObjectPropertyAddress { prop(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, ch) }
func channel(_ d: AudioDeviceID) -> UInt32? {
    for ch: UInt32 in [0, 1] { var a = volAddr(ch); if AudioObjectHasProperty(d, &a) { return ch } }
    return nil
}
func getVol(_ d: AudioDeviceID, _ ch: UInt32) -> Float32 {
    var a = volAddr(ch); var v: Float32 = 0; var size = UInt32(4)
    AudioObjectGetPropertyData(d, &a, 0, nil, &size, &v); return v
}
func setVol(_ d: AudioDeviceID, _ ch: UInt32, _ v: Float32) -> OSStatus {
    var a = volAddr(ch); var x = max(0, min(1, v))
    var st = AudioObjectSetPropertyData(d, &a, 0, nil, 4, &x)
    if ch == 1 { var b = volAddr(2); if AudioObjectHasProperty(d, &b) { st = AudioObjectSetPropertyData(d, &b, 0, nil, 4, &x) } }
    return st
}

let args = CommandLine.arguments.dropFirst()
let cmd = args.first ?? "help"
let match = ProcessInfo.processInfo.environment["KINDLE_AUDIO_NAME"] ?? "Kindle"
if cmd == "list" { for d in devices() { print(d, name(d)) }; exit(0) }
guard cmd == "next" || cmd == "prev" else { print("usage: kturn next|prev [count] | list"); exit(2) }
let count = Int(args.dropFirst().first ?? "1") ?? 1
guard let dev = devices().first(where: { name($0).contains(match) }) else {
    FileHandle.standardError.write("no audio device matching '\(match)' (is the Kindle connected?)\n".data(using: .utf8)!); exit(1)
}
guard let ch = channel(dev) else { FileHandle.standardError.write("device has no volume control\n".data(using: .utf8)!); exit(1) }
let step: Float32 = 1.0 / 16.0
for i in 0..<count {
    var v = getVol(dev, ch)
    // keep room to move in the requested direction (Kindle re-centers its own side)
    if cmd == "next" && v > 1 - step { _ = setVol(dev, ch, 0.5); usleep(700_000); v = getVol(dev, ch) }
    if cmd == "prev" && v < step { _ = setVol(dev, ch, 0.5); usleep(700_000); v = getVol(dev, ch) }
    let target = cmd == "next" ? v + step : v - step
    let st = setVol(dev, ch, target)
    print("\(name(dev)) ch\(ch) volume \(String(format: "%.3f", v)) -> \(String(format: "%.3f", target)) status \(st)")
    if i < count - 1 { usleep(900_000) }
}
