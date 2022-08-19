//
//  ContentView.swift
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
import MotorControl

struct ContentView: View {
    @StateObject var viewModel: ViewModel = .init()
    
    var body: some View {
        LazyVStack(spacing: 16) {
            ForEach(MotorControlIdentifier.allCases, id: \.rawValue) { name in
                Button(name.rawValue) {
                    viewModel.current = .init(try! name.instantiateAssessmentState())
                }
            }
        }
        .fullScreenCover(isPresented: $viewModel.isPresented) {
            AssessmentListener(viewModel)
        }
    }
    
    class ViewModel : ObservableObject {
        @Published var isPresented: Bool = false
        var current: AssessmentState? {
            didSet {
                isPresented = (current != nil)
            }
        }
    }
    
    struct AssessmentListener : View {
        @ObservedObject var viewModel: ViewModel
        @ObservedObject var state: AssessmentState
        
        init(_ viewModel: ViewModel) {
            self.viewModel = viewModel
            self.state = viewModel.current!
        }
        
        var body: some View {
            MotorControlAssessmentView(state)
                .onChange(of: state.status) { newValue in
                    print("assessment status = \(newValue)")
                    
                    // In a real use-case this is where you might save and upload data
                    if newValue == .readyToSave {
                        do {
                            let data = try state.result.jsonEncodedData()
                            let output = String(data: data, encoding: .utf8)!
                            print("assessment result = \n\(output)\n")
                        }
                        catch {
                            assertionFailure("Failed to encode result: \(error)")
                        }
                    }
                    
                    // Exit
                    guard newValue >= .finished else { return }
                    viewModel.isPresented = false
                    viewModel.current = nil
                }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

extension Bundle {
    static let module: Bundle = .main
}
