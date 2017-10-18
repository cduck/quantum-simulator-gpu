//
//  main.swift
//  Quantum Simulator
//
//  Created by Casey Duckering on 2017-10-09.
//  Copyright © 2017 Casey Duckering. All rights reserved.
//

let cFilePath = ""
//let cFilePath = "/Users/cduck/dev/Quantum/simulation/simple.circuit"
//let cFilePath = "/Users/cduck/dev/Quantum/simulation/test.circuit"
//let cFilePath = "/Users/cduck/dev/Quantum/simulation/hadamard32.circuit"

func main(verbose: Int, shots: Int) {
    var filePath = cFilePath
    var verbose = verbose
    var shots = shots

    let args = CommandLine.arguments
    if filePath == "" {
        if args.count <= 1 {
            print("Usage: \(args.count > 0 ? args[0] : "$0") circuit-file")
            return
        }
        filePath = args[1]
    }
    if args.count > 2 {
        if let v = Int(args[2]) {
            verbose = v
        }
    }
    if args.count > 3 {
        if let s = Int(args[3]) {
            shots = s
        }
    }
    guard let circuit = loadCircuit(filePath: filePath, verbose: verbose >= 3) else {
        return
    }
    do {
        let gpu = try PathCompute(verbose: verbose-1)
        if shots == 1 {
            let (measVal, measProb) = try computeEntireMeasurement(gpu: gpu, circuit: circuit, verbose: verbose)
            if verbose >= 1 {
                print("")
            }
            let hexStr = String(format: "%0\((circuit.measureIndexList.count+15)/16)x", measVal)
            let binStr = binaryString(val: measVal, bitCount: circuit.measureIndexList.count, unknownMask: 0)
            print("Measurement: 0x\(hexStr), \(measVal), 0b\(binStr)")
            print("Probability of this value: \(measProb)")
        }

        if shots > 1 {
            print("Running \(shots) times\n")
            var counts = (0..<(1<<circuit.measureIndexList.count)).map({ (_) -> Float in return 0 })
            for i in 0..<shots {
                let (measVal, measProb) = try computeEntireMeasurement(gpu: gpu, circuit: circuit, verbose: verbose-1)
                counts[measVal] += 1 / Float(shots)

                if verbose >= 1 {
                    let hexStr = String(format: "%\((circuit.measureIndexList.count+15)/16)x", measVal)
                    let binStr = binaryString(val: measVal, bitCount: circuit.measureIndexList.count, unknownMask: 0)
                    print("Measurement: 0x\(hexStr), \(measVal), 0b\(binStr) (p = \(measProb))")
                    print("Counts (shots=\(i+1)): \(counts)")
                }
            }
            print("\nFinal Counts: \(counts)")
        }
    } catch PathComputeError.InitError(let msg) {
        print("Init error: \(msg)")
    } catch PathComputeError.InvalidCircuit(let msg) {
        print("Circuit error: \(msg)")
    } catch PathComputeError.StateError(let msg) {
        print("State error: \(msg)")
    } catch PathComputeError.GpuError(let msg) {
        print("GPU error: \(msg)")
    } catch {
        print("Error: \(error)")
    }
}

func computeEntireMeasurement(gpu: PathCompute, circuit: CircuitDetails, verbose: Int) throws -> (Int, Float) {
    try gpu.prepareCircuit(circuit)
    gpu.warnUserAboutCircuitSize()

    var startTime = mach_absolute_time()
    var measureValue = 0
    var totalProb: Float = 1
    for (measureBitIndex, (gateIndex, _)) in
            circuit.measureIndexList.enumerated() {
        let probZero = try gpu.computeBitProbability(
            measureBitIndex: measureBitIndex,
            measureMatchEarlier: measureValue,
            delayBeforeRunning: verbose >= 1)
        if probZero.isNaN {
            print("Error: No paths match previous measurements")
            return (measureValue, 0)
        }
        let bitVal = randomBit(probZero: probZero)
        let bitProb = bitVal == 0 ? probZero : 1 - probZero
        totalProb *= bitProb
        measureValue |= bitVal << measureBitIndex
        if verbose >= 1 {
            let bitIndex = circuit.gates[gateIndex].primaryBit
            print("Measurement \(measureBitIndex): qubit \(bitIndex) = \(bitVal) (with probability of \(bitProb))")
            let binStr = binaryString(val: measureValue,
                                      bitCount: circuit.measureIndexList.count,
                                      unknownMask: (~0) << (measureBitIndex + 1))
            print("Current value: 0b\(binStr)")
        }
    }
    let endTime = mach_absolute_time()
    var totalTime = Double(endTime - startTime) / Double(NSEC_PER_SEC)
    if verbose >= 1 {
        print("\nTotal measurement time: \(totalTime) seconds")
    }
    return (measureValue, totalProb)
}

func binaryString(val: Int, bitCount: Int, unknownMask: Int) -> String {
    var valStr = ""
    for i in (0..<bitCount).reversed() {
        if (unknownMask >> i) & 0x1 == 0x1 {
            valStr.append("?")
        } else {
            valStr.append((val >> i) & 0x1 == 0x1 ? "1" : "0")
        }
    }
    return valStr
}

func randomBit(probZero: Float) -> Int {
    let randInt: UInt32 = arc4random()
    let cutoff = UInt64(probZero * Float(UInt64(1) << 32))
    return UInt64(randInt) < cutoff ? 0 : 1
}


main(verbose: 1, shots: 1)
