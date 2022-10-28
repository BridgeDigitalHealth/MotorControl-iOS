//
//  MotionSensorViewModels.swift
//
//  Copyright © 2022 Sage Bionetworks. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
// 1.  Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// 2.  Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation and/or
// other materials provided with the distribution.
//
// 3.  Neither the name of the copyright holder(s) nor the names of any contributors
// may be used to endorse or promote products derived from this software without
// specific prior written permission. No license is granted to the trademarks of
// the copyright holders even if such marks are included in this software.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

import SwiftUI
import AssessmentModelUI
import AssessmentModel
import MobilePassiveData
import MotionSensor
import JsonModel
import ResultModel

/// State object for motion sensor steps
class MotionSensorStepViewModel : AbstractMotionControlState {
    var motionConfig: MotionSensorNodeObject { node as! MotionSensorNodeObject }
    let voicePrompter: TextToSpeechSynthesizer = .init()
    let spokenInstructions: [Int : String]
    var instructionCache: Set<Int> = []
    let recorder: MotionRecorder
    weak var branchState: BranchState!
    
    @Published var secondCount: Int = 0
    @Published var countdown: CGFloat {
        didSet {
            secondCount = Int(countdown)
        }
    }
    @Published var isPaused : Bool = false {
        didSet {
            guard recorder.status >= .starting else { return }
            if isPaused {
                recorder.pause()
            }
            else {
                recorder.resume()
            }
        }
    }
    
    init(_ motionConfig: MotionSensorNodeObject, assessmentState: AssessmentState, branchState: BranchState) {
        if assessmentState.outputDirectory == nil {
            assessmentState.outputDirectory = createOutputDirectory()
        }
        self.recorder = .init(configuration: motionConfig,
                              outputDirectory: assessmentState.outputDirectory!,
                              initialStepPath: "\(assessmentState.node.identifier)/\(branchState.node.identifier)",
                              sectionIdentifier: branchState.node.identifier)
        let whichHand = branchState.node.hand()
        let replacementString = whichHand?.handReplacementString() ?? "NULL"
        self.spokenInstructions = motionConfig.spokenInstructions?.mapValues { text in
            text.replacingOccurrences(of: formattedTextPlaceHolder, with: replacementString)
        } ?? [:]
        self.countdown = motionConfig.duration
        super.init(motionConfig, parentId: branchState.id, whichHand: whichHand)
        self.branchState = branchState
    }
    
    func speak(at timeInterval: TimeInterval, completion: (() -> Void)? = nil) {
        let key = Int(min(timeInterval, motionConfig.duration))
        guard !instructionCache.contains(key), let instruction = spokenInstructions[key]
        else {
            completion?()
            return
        }
        instructionCache.insert(key)
        voicePrompter.speak(text: instruction) { _, _ in
            completion?()
        }
    }
    
    @MainActor
    func resetCountdown() {
        recorder.clock.reset()
        countdown = motionConfig.duration
        instructionCache.removeAll()
        // TODO: syoung 10/05/2022 Flush the recorder file?
    }
    
    @MainActor
    func startRecorder() {
        guard recorder.status == .idle else { return }
        Task {
            do {
                try await recorder.start()
            }
            catch {
                recorder.clock.reset()
                let result = ErrorResultObject(identifier: node.identifier, error: error)
                branchState.branchNodeResult.asyncResults = [result]
            }
        }
    }
    
    @MainActor
    func updateCountdown() -> (currentTime: SecondDuration, isFinished: Bool)? {
        guard !isPaused, countdown > 0
        else {
            return nil
        }
        let time = recorder.clock.runningDuration()
        countdown = max(.zero, motionConfig.duration - time)
        return (time, countdown == .zero)
    }
    
    func stop() async {
        // stop the recorder and speak the final instruction and *then*
        // return from this method once both those have finished.
        async let result = stopRecorder()
        await withCheckedContinuation { completion in
            speak(at: motionConfig.duration) {
                completion.resume()
            }
        }
        if let motionResult = await result {
            branchState.branchNodeResult.asyncResults = [motionResult]
        }
    }
        
    func stopRecorder() async -> ResultData? {
        guard recorder.status == .running else { return nil }
        // Wrap stopping the recorder to catch the thrown error (if any).
        do {
            return try await recorder.stop()
        }
        catch {
            return ErrorResultObject(identifier: node.identifier, error: error)
        }
    }
}

/// View model for a tremor step
final class TremorStepViewModel : MotionSensorStepViewModel {
}

/// View model for a tapping step
final class TappingStepViewModel : MotionSensorStepViewModel {
    
    var tappingResult : TappingResultObject {
        get { self.result as! TappingResultObject }
        set { self.result = newValue }
    }
    var initialTapOccurred: Bool { recorder.status > .idle }
    var previousButton: TappingButtonIdentifier? = nil
    
    @Published var tapCount: Int = 0 {
        didSet {
            tappingResult.tapCount = tapCount
        }
    }

    override init(_ motionConfig: MotionSensorNodeObject, assessmentState: AssessmentState, branchState: BranchState) {
        super.init(motionConfig, assessmentState: assessmentState, branchState: branchState)
        self.tappingResult.hand = whichHand
    }

    @MainActor
    func tappedScreen(currentButton: TappingButtonIdentifier,
                             location: CGPoint,
                             duration: TimeInterval) {
        guard recorder.clock.runningDuration() < motionConfig.duration, initialTapOccurred
        else {
            return
        }
        // use a call-through method so that the unit tests will pass w/o starting the recorder
        addTappingSample(currentButton: currentButton, location: location, duration: duration)
    }
    
    @MainActor
    func addTappingSample(currentButton: TappingButtonIdentifier,
                          location: CGPoint,
                          duration: TimeInterval) {
        let sample: TappingSample = .init(uptime: SystemClock.uptime() - duration,
                                          timestamp: max(recorder.clock.runningDuration() - duration, .zero),
                                          stepPath: recorder.currentStepPath,
                                          buttonIdentifier: currentButton,
                                          location: location,
                                          duration: duration)
        // Update the tap count if the button is *not* the "none" case and either the previous button is nil
        // or the previous button matches this button.
        tappingResult.samples.append(sample)
        
        guard currentButton != .none, previousButton != currentButton
        else {
            return
        }
        tapCount += 1
        previousButton = currentButton
    }
}

fileprivate func createOutputDirectory() -> URL {
    URL(fileURLWithPath: UUID().uuidString, isDirectory: true, relativeTo: FileManager.default.temporaryDirectory)
}
