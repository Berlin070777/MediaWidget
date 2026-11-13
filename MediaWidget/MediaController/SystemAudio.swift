import AudioToolbox
import CoreAudio
import Foundation

enum SystemAudio {
    private static let system = AudioObjectID(kAudioObjectSystemObject)
    private static var device: AudioObjectID? {
        var id: AudioObjectID = 0
        var property = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        return read(&id, from: system, property: &property) && id != kAudioObjectUnknown ? id : nil
    }

    struct Snapshot: Equatable {
        var volume: Float?
        var muted: Bool?
        var canSetVolume = false
        var canMute = false
    }

    static func snapshot() -> Snapshot {
        guard let device else { return Snapshot() }
        var volume: Float32 = 0
        var mute: UInt32 = 0
        var volumeAddress = volumeAddress(for: device)
        var muteAddress = output(kAudioDevicePropertyMute)
        return Snapshot(
            volume: read(&volume, from: device, property: &volumeAddress) && volume.isFinite ? volume : nil,
            muted: read(&mute, from: device, property: &muteAddress) ? mute != 0 : nil,
            canSetVolume: settable(device, &volumeAddress), canMute: settable(device, &muteAddress)
        )
    }

    static func setVolume(_ volume: Float) -> Bool {
        guard let device, volume.isFinite else { return false }
        var value = min(max(volume, 0), 1)
        var property = volumeAddress(for: device)
        return write(&value, to: device, property: &property)
    }

    static func toggleMute() -> Bool {
        guard let device else { return false }
        var value: UInt32 = 0
        var property = output(kAudioDevicePropertyMute)
        guard read(&value, from: device, property: &property) else { return false }
        value = value == 0 ? 1 : 0
        return write(&value, to: device, property: &property)
    }

    private static func volumeAddress(for device: AudioObjectID) -> AudioObjectPropertyAddress {
        var virtual = output(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        return AudioObjectHasProperty(device, &virtual) ? virtual : output(kAudioDevicePropertyVolumeScalar)
    }

    private static func output(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func settable(_ id: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> Bool {
        var result = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(id, &address, &result) == noErr && result.boolValue
    }

    private static func read<T>(_ value: inout T, from id: AudioObjectID,
                                property: inout AudioObjectPropertyAddress) -> Bool {
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutableBytes(of: &value) { bytes in
            AudioObjectGetPropertyData(id, &property, 0, nil, &size, bytes.baseAddress!) == noErr
        }
    }

    private static func write<T>(_ value: inout T, to id: AudioObjectID,
                                 property: inout AudioObjectPropertyAddress) -> Bool {
        guard settable(id, &property) else { return false }
        return withUnsafeBytes(of: &value) { bytes in
            AudioObjectSetPropertyData(id, &property, 0, nil, UInt32(bytes.count), bytes.baseAddress!) == noErr
        }
    }
}
