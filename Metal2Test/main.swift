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

    // Load the kernel functions and create pipelines
    let library = device.makeDefaultLibrary()!
    let pathKernel = library.makeFunction(name: "pathKernel")!
    let pathPipelineState = try! device.makeComputePipelineState(function: pathKernel)
    var sumPipelineStateList = [MTLComputePipelineState]()
    while true {
        let i = sumPipelineStateList.count
        guard let sumKernel = library.makeFunction(name: String(format: "sumKernel%d", i)) else {
            break
        }
        // Create pipeline
        let sumPipelineState = try! device.makeComputePipelineState(function: sumKernel)
        sumPipelineStateList.append(sumPipelineState)
    }
    let maxSumStages = sumPipelineStateList.count

    // Problem-specific calculations
    let numPaths = 1 << 32  // Don't set this too high (more than 32) or the OS might crash
    let numBits = 16
    let numPathsPerThread = 1 << 8  // Also set in shader
    let numSumsPerThread = 1 << 6  // Also set in shader
    let numConcurrentPathThreads = 1 << 16  // 1<<17 is optimal
    let numPathsAtATime = numConcurrentPathThreads * numPathsPerThread
    let numPathDispatches = numPaths / numPathsAtATime
    let numConcurrentSums = numConcurrentPathThreads / numSumsPerThread

    // Calculate depth of sums
    var numValsPerStage = [Int]()
    numValsPerStage.append(numPaths / numPathsPerThread)
    while numValsPerStage.last! > 0 {
        numValsPerStage.append(numValsPerStage.last! / numSumsPerThread)
    }
    let _ = numValsPerStage.popLast()
    let numSumStages = numValsPerStage.count - 1
    if numSumStages > maxSumStages {
        print("Too many sum stages: \(numSumStages) > \(maxSumStages)")
        return
    }

    // Create kernel inputs
    let gateArray = [
        GateInstance.init(type: 0, primaryBit: 0, controlBit: 1, control2Bit: 2),
        GateInstance.init(type: 0, primaryBit: 1, controlBit: 1, control2Bit: 2),
        GateInstance.init(type: 0, primaryBit: 2, controlBit: 1, control2Bit: 2),
        GateInstance.init(type: 0, primaryBit: 3, controlBit: 1, control2Bit: 2),
    ]
    let measureConfigArray = (0..<1).map { (_) -> MeasureConfig in
        return MeasureConfig.init(numGates: CInt(gateArray.count))
    }
    let dispatchConfigArray = (0..<numPathDispatches).map { (i) -> DispatchConfig in
        return DispatchConfig.init(restOfChoices: CUnsignedInt(i))
    }

    // Setup buffer, encoder
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let encoder = commandBuffer.makeComputeCommandEncoder()!

    // Setup buffers
    let measureConfigBuf = device.makeBuffer(bytes: UnsafeRawPointer(measureConfigArray),
                                             length: MemoryLayout<MeasureConfig>.stride * measureConfigArray.count,
                                             options: .storageModeManaged)
    let dispatchConfigBuf = device.makeBuffer(bytes: UnsafeRawPointer(dispatchConfigArray),
                                              length: MemoryLayout<DispatchConfig>.stride * dispatchConfigArray.count,
                                              options: .storageModeManaged)
    let gateBuf = device.makeBuffer(bytes: UnsafeRawPointer(gateArray),
                                    length: MemoryLayout<GateInstance>.stride * gateArray.count,
                                    options: .storageModeManaged)
    var sumPairBufList = [MTLBuffer]()
    for i in 0..<numSumStages+1 {
        let bufferMaxSlots = numConcurrentPathThreads
        let numSlots = min(bufferMaxSlots, numValsPerStage[i])
        let sumPairBuf = device.makeBuffer(
            length: MemoryLayout<SumPair>.stride * numSlots,
            options: ((i == numSumStages) ? .storageModeShared : .storageModePrivate))!
        sumPairBufList.append(sumPairBuf)
    }

    // Kernel outputs
    let sumPairArrayLast = UnsafeBufferPointer<SumPair>(
        start: sumPairBufList.last!.contents().bindMemory(
            to: SumPair.self,
            capacity: numValsPerStage.last! * MemoryLayout<SumPair>.stride),
        count: numValsPerStage.last!)

    // Connect buffers to kernel
    encoder.setBuffer(measureConfigBuf, offset: 0, index: 0)
    encoder.setBuffer(dispatchConfigBuf, offset: 0, index: 1)
    encoder.setBuffer(gateBuf, offset: 0, index: 2)
    let sumBufferIndex = 3
    for i in 0..<numSumStages+1 {
        encoder.setBuffer(sumPairBufList[i], offset: 0, index: sumBufferIndex + i)
    }

    //print("Pipeline info: per threadgroup=\(pathPipelineState.maxTotalThreadsPerThreadgroup), execution width=\(pathPipelineState.threadExecutionWidth), memory length=\(pathPipelineState.staticThreadgroupMemoryLength)")
    func dispatchPath(dispatchIndex: Int) {
        // Dispatch path kernel
        encoder.setComputePipelineState(pathPipelineState)
        encoder.setBufferOffset(dispatchIndex * MemoryLayout<DispatchConfig>.stride, index: 1)
        //encoder.setBufferOffset(0, index: sumBufferIndex)
        let tgSize = MTLSize.init(
            width: min(pathPipelineState.maxTotalThreadsPerThreadgroup, numConcurrentPathThreads),
            height: 1, depth: 1)
        let numThreadGroups = MTLSize.init(
            width: numConcurrentPathThreads / tgSize.width,
            height: 1, depth: 1)
        encoder.dispatchThreadgroups(numThreadGroups, threadsPerThreadgroup: tgSize)
    }
    func dispatchSumAtStage(stage: Int, numInputs: Int, outputOffset: Int) {
        // Dispatch sum kernel
        encoder.setComputePipelineState(sumPipelineStateList[stage])
        encoder.setBufferOffset(0 * MemoryLayout<SumPair>.stride, index: sumBufferIndex + stage)
        encoder.setBufferOffset(outputOffset * MemoryLayout<SumPair>.stride, index: sumBufferIndex + stage + 1)
        let numThreads = numInputs / numSumsPerThread
        let tgSize = MTLSize.init(
            width: min(sumPipelineStateList[stage].maxTotalThreadsPerThreadgroup, numThreads),
            height: 1, depth: 1)
        let numThreadGroups = MTLSize.init(
            width: numThreads / tgSize.width,
            height: 1, depth: 1)
        encoder.dispatchThreadgroups(numThreadGroups, threadsPerThreadgroup: tgSize)
    }

    // Dispatch path and sum kernels in sequence
    func dispatchRecursive(depth: Int, dispatchIndex: Int) -> Int {
        if depth <= 0 {
            dispatchPath(dispatchIndex: dispatchIndex)
            return dispatchIndex + 1
        } else {
            var dispatchIndex = dispatchIndex
            let numLoops = max(min(numValsPerStage[depth - 1] / numConcurrentPathThreads, numSumsPerThread), 1)
            let numSumInputs = min(numValsPerStage[depth - 1], numConcurrentPathThreads)
            for i in 0..<numLoops {
                dispatchIndex = dispatchRecursive(depth: depth - 1,
                                                  dispatchIndex: dispatchIndex)
                dispatchSumAtStage(stage: depth - 1,
                                   numInputs: numSumInputs,
                                   outputOffset: i * numConcurrentSums)
            }
            return dispatchIndex
        }
    }
    let numElementsSummed = dispatchRecursive(depth: numSumStages, dispatchIndex: 0)
    assert(numElementsSummed == numPathDispatches, "Dispatch schedule logic error")

    // Start running on GPU
    encoder.endEncoding()
    let startTime = mach_absolute_time()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    let endTime = mach_absolute_time()
    let duration = Double(endTime - startTime) / Double(NSEC_PER_SEC)

    // After completion
    print("\nGPU time: \(duration) seconds")

    // Final sum
    var sum = vector_float4()
    print("Sum:")
    for subSum in sumPairArrayLast {
        print("    \(subSum)")
        sum += subSum.val01
    }

    // Kernel outputs

    /*let sumPairArrays = sumPairBufList.map { (buf) -> UnsafeBufferPointer<SumPair> in
        return UnsafeBufferPointer<SumPair>(
            start: buf.contents().bindMemory(
                to: SumPair.self,
                capacity: buf.length),
            count: buf.length / MemoryLayout<SumPair>.stride)
    }
    for arr in sumPairArrays {
        print("""
        Next buffer:
            \(arr[0])
            \(arr[1])
            \(arr[2])
            \(arr[3])
            \(arr[4])
            ...
            \(arr[arr.count/4])
            \(arr[arr.count/4+1])
            \(arr[arr.count/4+2])
            \(arr[arr.count/4+3])
            ...
            \(arr[arr.count/2-2])
            \(arr[arr.count/2-1])
            \(arr[arr.count/2])
            \(arr[arr.count/2+1])
            \(arr[arr.count/2+2])
            ...
            \(arr[arr.count/4*3-3])
            \(arr[arr.count/4*3-2])
            \(arr[arr.count/4*3-1])
            \(arr[arr.count/4*3])
            ...
            \(arr[arr.count-4])
            \(arr[arr.count-3])
            \(arr[arr.count-2])
            \(arr[arr.count-1])
        """)
    }*/

    print("""
    \nResult: \(sum)
    """)
}


print("\nStart\n")
main();
print("\nFinished\n")
