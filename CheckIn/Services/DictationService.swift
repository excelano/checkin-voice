// DictationService.swift — CheckIn Voice
// Speech recognition using SFSpeechRecognizer for voice commands and reply dictation
//
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import Speech
import AVFoundation

@MainActor @Observable
final class DictationService {
    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    private(set) var transcript = ""
    private(set) var isListening = false
    private(set) var permissionGranted = false

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale.current)
    }

    // MARK: - Permissions

    func requestPermission() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            permissionGranted = false
            return false
        }

        let micStatus: Bool
        if #available(iOS 17.0, *) {
            micStatus = await AVAudioApplication.requestRecordPermission()
        } else {
            micStatus = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        permissionGranted = micStatus
        return micStatus
    }

    // MARK: - Start Listening

    func startListening() {
        guard let recognizer, recognizer.isAvailable else { return }

        // Stop any existing session
        stopListening()

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session setup failed: \(error.localizedDescription)")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                self.transcript = result.bestTranscription.formattedString
            }

            if error != nil || (result?.isFinal ?? false) {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionTask = nil
                self.isListening = false
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
            transcript = ""
        } catch {
            print("Audio engine failed to start: \(error.localizedDescription)")
        }
    }

    // MARK: - Stop Listening

    @discardableResult
    func stopListening() -> String {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
        return transcript
    }
}
