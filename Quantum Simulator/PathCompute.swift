//
//  PathCompute.swift
//  Quantum Simulator
//
//  Created by Casey Duckering on 2017-10-09.
//  Copyright © 2017 Casey Duckering. All rights reserved.
//

import Foundation
import Metal


enum PathComputeError: Swift.Error {
    case InitError(msg: String)
    case InvalidCircuit(_: String)
    case StateError(_: String)
    case GpuError(_: String)
}

func log2Floor(_ val: Int) -> Int {
    // When val <= 0, returns 0
    // When val > 0, returns floor(log2(val))
    var val = val
    for i in 0... {
        if val <= 1 {
            return i
        }
        val >>= 1
    }
    return 0
}

class PathCompute {
    var verbose: Int
    // Long-lived Metal objects: device, queue, etc.
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let library: MTLLibrary
    let pathPipelineState: MTLComputePipelineState
    let checkPipelineState: MTLComputePipelineState
    let sumPipelineStateList: [MTLComputePipelineState]

    // Per-circuit Metal objects: buffers

    // Kernel capabilities
    // TODO: Increase number of state bits and measured bits
    let maxStateBits = 32
    let maxMeasureBits = 32

    // Static thread configuration
    let maxSumStages: Int  // Limited by the number of sum kernels
    let maxHadamardCount = 28  // Show a warning when calculating more
    let numPathsPerThread = 1 << 8  // Also set in shader
    let numSumsPerThread = 1 << 6  // Also set in shader
    let numConcurrentPathThreads = 1 << 16  // Around 1<<17 is optimal
    let numPathsAtATime: Int

    // Circuit and calculation state
    var circuit: CircuitDetails?
    var circuitGates = [GateInstance]()
    var gpuTime: Double = 0

    init(verbose: Int) throws {
        self.verbose = verbose
        if verbose >= 1 {
            let devices = MTLCopyAllDevices()
            print("Number of devices = \(devices.count)")
        }

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw PathComputeError.InitError(msg: "Metal is not supported on this device")
        }
        self.device = device
        //self.device = devices[devices.count - 1]  // Use a different device

        // Make command queue
        guard let commandQueue = device.makeCommandQueue() else {
            throw PathComputeError.InitError(msg: "Could not make command queue")
        }
        self.commandQueue = commandQueue

        // Load the kernel functions and create pipelines
        library = device.makeDefaultLibrary()!
        let pathKernel = library.makeFunction(name: "pathKernel")!
        pathPipelineState = try! device.makeComputePipelineState(function: pathKernel)
        let checkKernel = library.makeFunction(name: "completionCheckKernel")!
        checkPipelineState = try! device.makeComputePipelineState(function: checkKernel)
        var pList = [MTLComputePipelineState]()
        while true {
            let i = pList.count
            guard let sumKernel = library.makeFunction(name: String(format: "sumKernel%d", i)) else {
                break
            }
            // Create pipeline
            let sumPipelineState = try! device.makeComputePipelineState(function: sumKernel)
            pList.append(sumPipelineState)
        }
        sumPipelineStateList = pList
        maxSumStages = sumPipelineStateList.count

        if verbose >= 1 {
            print("GPU pipeline info: threads per threadgroup = \(pathPipelineState.maxTotalThreadsPerThreadgroup), execution width = \(pathPipelineState.threadExecutionWidth)")
        }

        numPathsAtATime = numConcurrentPathThreads * numPathsPerThread
    }

    func prepareCircuit(_ circuit: CircuitDetails) throws {
        if circuit.measureIndexList.count <= 0 {
            throw PathComputeError.InvalidCircuit("The circuit contains no measurements")
        }
        if circuit.measureIndexList.count > maxMeasureBits {
            throw PathComputeError.InvalidCircuit("The circuit contains more measurements than this program can handle (\(circuit.measureIndexList.count) > \(maxMeasureBits))")
        }
        if circuit.bitCount > maxStateBits {
            throw PathComputeError.InvalidCircuit("The circuit uses more bits than this program can handle (\(circuit.bitCount) > \(maxStateBits))")
        }
        let numSumStages = calculateSumDepth(paths: 1 << circuit.hadamardCount).count - 1
        if numSumStages > maxSumStages {
            throw PathComputeError.InvalidCircuit("Too many sum stages (\(numSumStages) > \(maxSumStages))")
        }

        self.circuit = circuit
        self.circuitGates = [GateInstance](circuit.gates)
        self.circuitGates.append(GateInstance.init())
    }

    func warnUserAboutCircuitSize() {
        guard let circuit = circuit else { return }
        if circuit.hadamardCount > maxHadamardCount {
            print("Warning: There are too many Hadamard gates (\(circuit.hadamardCount) > \(maxHadamardCount)).  The simulation may take a long time.")
            print("Press Enter to continue.")
            let _ = readLine()
        }
    }

    private func calculateSumDepth(paths: Int) -> [Int] {
        var numValsPerStage = [Int]()
        numValsPerStage.append(paths / numPathsPerThread)
        while numValsPerStage.last! > 0 {
            numValsPerStage.append(numValsPerStage.last! / numSumsPerThread)
        }
        let _ = numValsPerStage.popLast()
        return numValsPerStage
    }

    func computeBitProbability(measureBitIndex: Int, measureMatchEarlier: Int,
                               delayBeforeRunning: Bool) throws -> Float {
        guard let circuit = circuit else { throw PathComputeError.StateError("prepareCircuit() was not called") }

        // Only cound Hadamard gates that come before and might affect the measurement
        let hadamardCount = circuit.measureIndexList[measureBitIndex].1
        let numGates = circuit.measureIndexList[measureBitIndex].0+1
        // Calculate thread configuration
        let numPathsNeeded = 1 << hadamardCount
        let numPaths = max(numPathsNeeded, numPathsAtATime)
        let numPathDispatches = numPaths / numPathsAtATime
        let numConcurrentSums = numConcurrentPathThreads / numSumsPerThread

        // Calculate depth of sums
        let numValsPerStage = calculateSumDepth(paths: numPaths)
        let numSumStages = numValsPerStage.count - 1
        assert(numSumStages <= maxSumStages, "Too many sum stages")  // Already checked earlier

        // Calculate helper values for kernel
        let restOfChoicesLength = log2Floor(numPathDispatches * numConcurrentPathThreads)
        var numGatesCommon = numGates
        var c = 0
        for (i, gate) in circuitGates.enumerated() {
            if gate.useChoice {
                c += 1
            }
            if c > restOfChoicesLength {
                numGatesCommon = i  // Don't include current gate
                break
            }
        }

        // Create kernel inputs
        let gateArray: [GateInstance] = circuitGates
        let measureConfigArray = (0..<1).map { (_) -> MeasureConfig in
            return MeasureConfig.init(numGates: CInt(numGates),
                                      numGatesCommon: CInt(min(numGatesCommon, numGates)),
                                      matchMask: CUnsignedInt(~(~Int(0) << measureBitIndex)),
                                      matchMeasure: CUnsignedInt(measureMatchEarlier),
                                      restOfChoicesLength: CInt(restOfChoicesLength),
                                      didCalculationFinish: 0)
        }
        let dispatchConfigArray = (0..<numPathDispatches).map { (i) -> DispatchConfig in
            return DispatchConfig.init(restOfChoices: CUnsignedInt(i * numConcurrentPathThreads))
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
                options: ((i == numSumStages) ? .storageModeManaged : .storageModePrivate))!
            sumPairBufList.append(sumPairBuf)
        }

        // Kernel outputs
        let sumPairArrayLast = UnsafeBufferPointer<SumPair>(
            start: sumPairBufList.last!.contents().bindMemory(
                to: SumPair.self,
                capacity: numValsPerStage.last! * MemoryLayout<SumPair>.stride),
            count: numValsPerStage.last!)
        let measureConfigOutput = UnsafeBufferPointer<MeasureConfig>(
            start: measureConfigBuf!.contents().bindMemory(
                to: MeasureConfig.self,
                capacity: measureConfigArray.count * MemoryLayout<MeasureConfig>.stride),
            count: measureConfigArray.count)

        // Connect buffers to kernel
        encoder.setBuffer(measureConfigBuf, offset: 0, index: 0)
        encoder.setBuffer(dispatchConfigBuf, offset: 0, index: 1)
        encoder.setBuffer(gateBuf, offset: 0, index: 2)
        let sumBufferIndex = 3
        for i in 0..<numSumStages+1 {
            encoder.setBuffer(sumPairBufList[i], offset: 0, index: sumBufferIndex + i)
        }

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
        func dispatchCompletionCheck() {
            // Dispatch path kernel
            encoder.setComputePipelineState(checkPipelineState)
            encoder.setBufferOffset(0 * MemoryLayout<MeasureConfig>.stride, index: 0)
            let tgSize = MTLSize.init(
                width: 1,
                height: 1, depth: 1)
            let numThreadGroups = MTLSize.init(width: 1, height: 1, depth: 1)
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
        dispatchCompletionCheck()

        // Finish encoding
        encoder.endEncoding()

        // Start running on GPU
        if verbose >= 1 {
            print("\nRunning on GPU")
        }
        if verbose >= 2 || delayBeforeRunning {
            // Delay so the message can be displayed before the UI freezes during GPU compute
            fflush(stdout)
            usleep(200_000)
        }

        // Track GPU run duration
        self.gpuTime = Double.nan
        var startTime: UInt64 = 1
        var endTime: UInt64 = 0
        commandBuffer.addScheduledHandler { (cmdBuf) in
            startTime = mach_absolute_time()
        }
        commandBuffer.addCompletedHandler {
            [unowned self] (cmdBuf) in
            endTime = mach_absolute_time()
            self.gpuTime = Double(endTime - startTime) / Double(NSEC_PER_SEC)
        }

        // Run
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // After completion
        if verbose >= 1 {
            print("GPU time: \(self.gpuTime) seconds")
        }

        if measureConfigOutput[0].didCalculationFinish != measureConfigOutput[0].numGates {
            throw PathComputeError.GpuError("Computation was canceled by the OS (ran out of time)")
        }

        // Final sum
        var sum = vector_float4()
        for subSum in sumPairArrayLast {
            sum += subSum.val01
        }
        if verbose >= 2 {
            print("Sum:")
            for subSum in sumPairArrayLast {
                print("    \(subSum)")
            }
        }

        // Calculate real measurement probabilities
        let pZero = sum.x * sum.x + sum.y * sum.y  // sum.xy * conj(sum.xy)
        let pOne  = sum.z * sum.z + sum.w * sum.w
        let probZero = pZero / (pZero + pOne)  // Normalize probabilities
        let probOne = pOne / (pZero + pOne)
        if verbose >= 1 {
            print("")
            let s = sum / Float(numPaths / numPathsNeeded)
            print("Sum of all paths: zero = \(s.x) + \(s.y) i, one = \(s.z) + \(s.w) i")
            print("Probability of measureing zero: \(probZero)")
            print("Probability of measureing one:  \(probOne)")
        }

        return probZero
    }
}
