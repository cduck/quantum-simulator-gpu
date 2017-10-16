//
//  main.swift
//  Metal2Test
//
//  Created by Casey Duckering on 2017-10-09.
//  Copyright © 2017 Casey Duckering. All rights reserved.
//

import Foundation
import Metal
import simd


//let alignedUniformsSize = (MemoryLayout<Uniforms>.size & ~0xFF) + 0x100

func main() {
    let devices = MTLCopyAllDevices()
    print("Number of devices = \(MTLCopyAllDevices().count)")

    guard let device = MTLCreateSystemDefaultDevice() else {
        print("Metal is not supported on this device")
        return
    }
    //let device = devices[devices.count - 1]  // Use last device

    // Make command queue
    let commandQueue = device.makeCommandQueue()!

    // Setup the pipeline
    let library = device.makeDefaultLibrary()
    let kernelFunction = library?.makeFunction(name: "pathKernel")!

    let pipelineState = try! device.makeComputePipelineState(function: kernelFunction!)

    // Setup buffer, encoder
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let encoder = commandBuffer.makeComputeCommandEncoder()!
    encoder.setComputePipelineState(pipelineState)

    // Problem-specific calculations
    let numPaths = 1 << 10  // Max 31
    let numBits = 16
    let groupSize = 1 << 5  // 1 << 17

    // Create kernel inputs
    let gateArray = [
        GateInstance.init(type: 0, primaryBit: 0, controlBit: 1, control2Bit: 2),
        GateInstance.init(type: 0, primaryBit: 1, controlBit: 1, control2Bit: 2),
        GateInstance.init(type: 0, primaryBit: 2, controlBit: 1, control2Bit: 2),
        GateInstance.init(type: 0, primaryBit: 3, controlBit: 1, control2Bit: 2)
    ]
    var groupConfig = GroupConfig.init(numGates: CInt(gateArray.count), restOfChoices: 99)

    // Setup buffers
    let groupConfigBuf = device.makeBuffer(bytes: &groupConfig, length: MemoryLayout<GroupConfig>.size, options: .storageModeManaged)
    let gateBuf = device.makeBuffer(bytes: UnsafeRawPointer(gateArray), length: MemoryLayout<GateInstance>.stride * gateArray.count, options: .storageModeManaged)
    // TODO: Change storage mode to private
    let sumPairBuf = device.makeBuffer(length: MemoryLayout<SumPair>.stride * groupSize, options: .storageModeShared)!

    // Kernel outputs
    let sumPairArray = UnsafeBufferPointer<SumPair>(start: sumPairBuf.contents().bindMemory(to: SumPair.self, capacity: MemoryLayout<SumPair>.stride * groupSize), count: groupSize)

    // Connect buffers to kernel
    encoder.setBuffer(groupConfigBuf, offset: 0, index: 0)
    encoder.setBuffer(gateBuf, offset: 0, index: 1)
    encoder.setBuffer(sumPairBuf, offset: 0, index: 2)

    // Dispatch
    print("Pipeline info: per threadgroup=\(pipelineState.maxTotalThreadsPerThreadgroup), execution width=\(pipelineState.threadExecutionWidth), memory length=\(pipelineState.staticThreadgroupMemoryLength)")
    let tgSize = MTLSize.init(
        width: min(pipelineState.maxTotalThreadsPerThreadgroup, groupSize),
       height: 1, depth: 1)
    let numThreadGroups = MTLSize.init(
        width: groupSize / tgSize.width,
        height: 1, depth: 1)
    encoder.dispatchThreadgroups(numThreadGroups, threadsPerThreadgroup: tgSize)
    encoder.endEncoding()

    // Commit entire command buffer
    commandBuffer.commit()

    // After completed
    commandBuffer.waitUntilCompleted()

    print("""
    \nResult:
    \(sumPairArray[0])
    \(sumPairArray[1])
    \(sumPairArray[2])
    \(sumPairArray[3])
    \(sumPairArray[4])
    \(sumPairArray[5])
    """)
}


print("\nStart\n")
main();
print("\nFinished\n")
