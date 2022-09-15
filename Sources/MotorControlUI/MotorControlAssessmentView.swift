//
//  MotorControlAssessmentView.swift
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
import AssessmentModel
import AssessmentModelUI
import JsonModel
import SharedMobileUI
import MotorControl

extension MotorControlAssessmentView : AssessmentDisplayView {
    public static func instantiateAssessmentState(_ identifier: String, config: Data?, restoredResult: Data?, interruptionHandling: InterruptionHandling?) throws -> AssessmentState {
        guard let taskId = MotorControlIdentifier(rawValue: identifier)
        else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "This view does not support \(identifier)"))
        }
        return try taskId.instantiateAssessmentState()
    }
}

/// Displays an assessment built using the views and model objects defined within this library.
public struct MotorControlAssessmentView : View {
    @StateObject var viewModel: MotorControlAssessmentViewModel = .init()
    @ObservedObject var assessmentState: AssessmentState
    //TODO: Decide whether or not we want this Aaron Rabara 8/25/22
    //@State var didResignActive = false
    
    public init(_ assessmentState: AssessmentState) {
        self.assessmentState = assessmentState
    }
    
    public var body: some View {
        AssessmentWrapperView<StepView>(assessmentState, viewModel: viewModel)
    }
    
    struct StepView : View, StepFactoryView {
        @EnvironmentObject var pagedNavigation: PagedNavigationViewModel
        @ObservedObject var state: StepState
        
        init(_ state: StepState) {
            self.state = state
        }
        
        var body: some View {
            stepView()
                .onAppear {
                    // Always hide the progress view
                    pagedNavigation.progressHidden = true
                }
        }
        
        @ViewBuilder
        private func stepView() -> some View {
            if let questionState = state as? QuestionState,
               questionState.step is ChoiceQuestionStep {
                ChoiceQuestionStepView(questionState)
            }
            else if let step = state.step as? CompletionStep {
                CompletionStepView(step)
            }
            else if state.step is CountdownStep {
                CountdownStepView(state)
                    .surveyTintColor(.textForeground)
            }
            else if state.step is OverviewStep {
                OverviewView(nodeState: state)
            }
            else if let nodeState = state as? MotorControlInstructionState {
                InstructionView(nodeState: nodeState)
            }
            else if let nodeState = state as? MotionSensorStepState {
                MotionSensorStepView(state: nodeState)
            }
            else {
                VStack {
                    Spacer()
                    Text(state.id)
                    Spacer()
                    SurveyNavigationView()
                }
            }
        }
    }
}

//TODO: Decide whether or not we want this Aaron Rabara 8/25/22
//struct AppBackgroundListener : ViewModifier {
//    @EnvironmentObject var assessmentState: AssessmentState
//    @State var didResignActive = false
//
//    func body(content: Content) -> some View {
//        content
//            .alert(isPresented: $didResignActive) {
//                Alert(title: Text("This activity has been interrupted and cannot continue.", bundle: .module),
//                      message: nil,
//                      dismissButton: .default(Text("OK", bundle: .module), action: {
//                    assessmentState.status = .continueLater
//                }))
//            }
//        #if os(iOS)
//            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
//                didResignActive = true
//            }
//        #endif
//    }
//}

struct MotorControlAssessmentPreview : View {
    let assessmentState: AssessmentState
    
    init(_ identifier: MotorControlIdentifier) {
        assessmentState = try! identifier.instantiateAssessmentState()
    }
    
    var body: some View {
        MotorControlAssessmentView(assessmentState)
    }
}

struct MotorControlAssessmentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MotorControlAssessmentPreview(.tremor)
            MotorControlAssessmentPreview(.kineticTremor)
                .preferredColorScheme(.dark)
        }
    }
}

extension AssessmentObject {
    convenience init(previewStep: Step) {
        self.init(identifier: previewStep.identifier, children: [previewStep])
    }
}


enum ImagePlacement : String, Codable, CaseIterable {
    case topBackground
}

extension ImageInfo {
    var placement: ImagePlacement {
        (self as? ImagePlacementInfo)?.placementHint.flatMap { .init(rawValue: $0) } ?? .topBackground
    }
}
