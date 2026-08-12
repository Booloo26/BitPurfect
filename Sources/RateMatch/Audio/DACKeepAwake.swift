import CoreAudio
import Foundation
import SimplyCoreAudio

/// Holds an external DAC's Core Audio engine running so the device never drops into
/// standby between tracks. It's the wake-up out of standby — output relay closing, charge
/// pumps spinning back up — that fires the pop you hear in sensitive IEMs, so the fix is
/// to never let it go to sleep in the first place.
///
/// While Apple Music is streaming, the IOProc writes exact digital zeros: summed into the
/// mix they leave every bit of the music untouched, so a bit-perfect lock stays bit
/// perfect. When nothing is playing it writes ~-120 dBFS of dither instead — non-zero, but
/// ~20 dB below the noise floor of any 16-bit source — for DACs that watch for digital
/// silence rather than for an idle USB stream.
final class DACKeepAwake {
    /// -120 dBFS. Inaudible even on high-sensitivity IEMs at listening gain, while still
    /// being a live signal as far as the DAC's silence detector is concerned.
    private static let ditherAmplitude: Float32 = 1e-6

    private(set) var activeDeviceID: AudioObjectID?
    private var procID: AudioDeviceIOProcID?

    /// Read by the realtime IO thread on every cycle, written from the main thread when
    /// playback starts or stops. Naturally aligned 32-bit words: a single load and a single
    /// store, so the IO thread never takes a lock it could block on.
    private let ditherFlag = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
    /// LCG state for the dither generator. Touched only by the IO thread.
    private let randomState = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)

    var isRunning: Bool { procID != nil }

    /// Set while Apple Music is feeding the device — the one condition under which the
    /// keep-awake signal must be pure zeros.
    var isSourcePlaying: Bool = false {
        didSet { ditherFlag.pointee = isSourcePlaying ? 0 : 1 }
    }

    init() {
        ditherFlag.initialize(to: 1)
        randomState.initialize(to: 0x2545_F491)
    }

    deinit {
        stop()
        ditherFlag.deallocate()
        randomState.deallocate()
    }

    /// Starts (or moves) the keep-awake stream on `device`. A no-op if it's already
    /// running there, so this is safe to call on every state change.
    func start(on device: AudioDevice) {
        if activeDeviceID == device.id, procID != nil { return }
        stop()

        let deviceID = device.id
        let dither = ditherFlag
        let random = randomState
        let isFloat32 = Self.usesPackedFloat32(device)

        let block: AudioDeviceIOBlock = { _, _, _, outputData, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            let wantsDither = isFloat32 && dither.pointee != 0

            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                memset(data, 0, Int(buffer.mDataByteSize))
                guard wantsDither else { continue }

                let samples = data.assumingMemoryBound(to: Float32.self)
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
                var seed = random.pointee
                for index in 0 ..< count {
                    seed = seed &* 1_664_525 &+ 1_013_904_223
                    let normalized = Float32(Int32(bitPattern: seed)) / Float32(Int32.max)
                    samples[index] = normalized * DACKeepAwake.ditherAmplitude
                }
                random.pointee = seed
            }
        }

        var newProcID: AudioDeviceIOProcID?
        guard AudioDeviceCreateIOProcIDWithBlock(&newProcID, deviceID, nil, block) == noErr,
              let newProcID else { return }

        guard AudioDeviceStart(deviceID, newProcID) == noErr else {
            AudioDeviceDestroyIOProcID(deviceID, newProcID)
            return
        }

        procID = newProcID
        activeDeviceID = deviceID
    }

    func stop() {
        guard let procID, let deviceID = activeDeviceID else {
            activeDeviceID = nil
            return
        }
        AudioDeviceStop(deviceID, procID)
        AudioDeviceDestroyIOProcID(deviceID, procID)
        self.procID = nil
        activeDeviceID = nil
    }

    /// The HAL hands IOProcs 32-bit float buffers on every device we've seen, but the
    /// dither generator writes `Float32` directly, so it only runs once that's confirmed.
    /// Zero-fill is memset and stays correct for any format either way.
    private static func usesPackedFloat32(_ device: AudioDevice) -> Bool {
        guard let format = device.streams(scope: .output)?.first?.virtualFormat else { return false }
        return format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.mBitsPerChannel == 32
    }
}
