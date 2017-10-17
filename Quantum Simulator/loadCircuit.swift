//
//  loadCircuit.swift
//  Quantum Simulator
//
//  Created by Casey Duckering on 2017-10-16.
//  Copyright © 2017 Casey Duckering. All rights reserved.
//

import Foundation
import simd

/*
 typedef struct {
 vector_float2 phase;
 unsigned char primaryBit;
 unsigned char controlBit;
 unsigned char control2Bit;
 bool useChoice : 1;
 bool doToggle : 1;
 bool doMeasure : 1;
 } GateInstance;
 */
/*struct GateInstance {
    let phase: float2
    let primaryBit: Int
    let controlBit: Int
    let control2Bit: Int
    let useChoice: Bool
    let doToggle: Bool
    let doMeasure: Bool
}*/

enum ParseCircuitError: Error {
    case InvalidSyntaxArg
    case InvalidSyntaxParam
    case InvalidGateParamCount
    case InvalidGateArgCount
}

struct CircuitDetails {
    let gates: [GateInstance]
    let hadamardCount: Int
    let measureIndexList: [Int]
}

let NO_CONTROL = CUnsignedChar(255)
let M_PIf: Float = 3.14159265358979323846
func complexExponentPhase(angle: Float) -> float2 {
    let real = cos(angle)
    let imag = sin(angle)
    return float2(real, imag)
}
func complexExponentPhaseFraction2(k: Int) -> float2 {
    // Use exact numbers when possible
    if k < 1 { return float2(0, 0) }
    else if k == 1 { return float2(-1, 0) }
    else if k == 2 { return float2(0, 1) }
    else {
        let frac = Float(0x1 << (k - 1))
        return complexExponentPhase(angle: M_PIf / frac)
    }
}
let gateInitializers: Dictionary<String, ([Float],[Int]) throws -> GateInstance> = [
    "M": { (params, args) throws -> GateInstance in
        if params.count != 0 { throw ParseCircuitError.InvalidGateParamCount }
        if args.count != 1 { throw ParseCircuitError.InvalidGateParamCount }
        return GateInstance.init(phase: float2(1, 0),
                                 primaryBit: CUnsignedChar(args[0]),
                                 controlBit: NO_CONTROL,
                                 control2Bit: NO_CONTROL,
                                 useChoice: false,
                                 doToggle: false,
                                 doMeasure: true)
    },
    "H": { (params, args) throws -> GateInstance in
        if params.count != 0 { throw ParseCircuitError.InvalidGateParamCount }
        if args.count != 1 { throw ParseCircuitError.InvalidGateParamCount }
        return GateInstance.init(phase: float2(-1, 0),
                                 primaryBit: CUnsignedChar(args[0]),
                                 controlBit: NO_CONTROL,
                                 control2Bit: NO_CONTROL,
                                 useChoice: true,
                                 doToggle: false,
                                 doMeasure: false)
    },
    "I": { (params, args) throws -> GateInstance in
        //if params.count != 0 { throw ParseCircuitError.InvalidGateParamCount }
        //if args.count != 1 { throw ParseCircuitError.InvalidGateParamCount }
        return GateInstance.init(phase: float2(1, 0),
                                 primaryBit: 0,
                                 controlBit: NO_CONTROL,
                                 control2Bit: NO_CONTROL,
                                 useChoice: false,
                                 doToggle: false,
                                 doMeasure: false)
    },
    "X": { (params, args) throws -> GateInstance in
        if params.count != 0 { throw ParseCircuitError.InvalidGateParamCount }
        if args.count != 1 { throw ParseCircuitError.InvalidGateParamCount }
        return GateInstance.init(phase: float2(1, 0),
                                 primaryBit: CUnsignedChar(args[0]),
                                 controlBit: NO_CONTROL,
                                 control2Bit: NO_CONTROL,
                                 useChoice: false,
                                 doToggle: true,
                                 doMeasure: false)
    },
    "Y": { (params, args) throws -> GateInstance in
        if params.count != 0 { throw ParseCircuitError.InvalidGateParamCount }
        if args.count != 1 { throw ParseCircuitError.InvalidGateParamCount }
        return GateInstance.init(phase: float2(-1, 0),
                                 primaryBit: CUnsignedChar(args[0]),
                                 controlBit: NO_CONTROL,
                                 control2Bit: NO_CONTROL,
                                 useChoice: false,
                                 doToggle: true,
                                 doMeasure: false)
    },
    "Z": { (params, args) throws -> GateInstance in
        if params.count != 0 { throw ParseCircuitError.InvalidGateParamCount }
        if args.count != 1 { throw ParseCircuitError.InvalidGateParamCount }
        return GateInstance.init(phase: float2(-1, 0),
                                 primaryBit: CUnsignedChar(args[0]),
                                 controlBit: NO_CONTROL,
                                 control2Bit: NO_CONTROL,
                                 useChoice: false,
                                 doToggle: false,
                                 doMeasure: false)
    },
    "S": { (params, args) throws -> GateInstance in
        if params.count != 0 { throw ParseCircuitError.InvalidGateParamCount }
        if args.count != 1 { throw ParseCircuitError.InvalidGateParamCount }
        return GateInstance.init(phase: float2(0, 1),
                                 primaryBit: CUnsignedChar(args[0]),
                                 controlBit: NO_CONTROL,
                                 control2Bit: NO_CONTROL,
                                 useChoice: false,
                                 doToggle: false,
                                 doMeasure: false)
    },
    "SD": { (params, args) throws -> GateInstance in
        if params.count != 0 { throw ParseCircuitError.InvalidGateParamCount }
        if args.count != 1 { throw ParseCircuitError.InvalidGateParamCount }
        return GateInstance.init(phase: float2(0, -1),
                                 primaryBit: CUnsignedChar(args[0]),
                                 controlBit: NO_CONTROL,
                                 control2Bit: NO_CONTROL,
                                 useChoice: false,
                                 doToggle: false,
                                 doMeasure: false)
    },
    "T": { (params, args) throws -> GateInstance in
        if params.count != 0 { throw ParseCircuitError.InvalidGateParamCount }
        if args.count != 1 { throw ParseCircuitError.InvalidGateParamCount }
        return GateInstance.init(phase: complexExponentPhaseFraction2(k: 3),
                                 primaryBit: CUnsignedChar(args[0]),
                                 controlBit: NO_CONTROL,
                                 control2Bit: NO_CONTROL,
                                 useChoice: false,
                                 doToggle: false,
                                 doMeasure: false)
    },
    "TD": { (params, args) throws -> GateInstance in
        if params.count != 0 { throw ParseCircuitError.InvalidGateParamCount }
        if args.count != 1 { throw ParseCircuitError.InvalidGateParamCount }
        return GateInstance.init(phase: -complexExponentPhaseFraction2(k: 3),
                                 primaryBit: CUnsignedChar(args[0]),
                                 controlBit: NO_CONTROL,
                                 control2Bit: NO_CONTROL,
                                 useChoice: false,
                                 doToggle: false,
                                 doMeasure: false)
    },
    "R": { (params, args) throws -> GateInstance in
        if params.count != 1 { throw ParseCircuitError.InvalidGateParamCount }
        if args.count != 1 { throw ParseCircuitError.InvalidGateParamCount }
        return GateInstance.init(phase: complexExponentPhase(angle: params[0]),
                                 primaryBit: CUnsignedChar(args[0]),
                                 controlBit: NO_CONTROL,
                                 control2Bit: NO_CONTROL,
                                 useChoice: false,
                                 doToggle: false,
                                 doMeasure: false)
    },
    "RK": { (params, args) throws -> GateInstance in
        if params.count != 1 { throw ParseCircuitError.InvalidGateParamCount }
        if args.count != 1 { throw ParseCircuitError.InvalidGateParamCount }
        return GateInstance.init(phase: complexExponentPhaseFraction2(k: Int(params[0])),
                                 primaryBit: CUnsignedChar(args[0]),
                                 controlBit: NO_CONTROL,
                                 control2Bit: NO_CONTROL,
                                 useChoice: false,
                                 doToggle: false,
                                 doMeasure: false)
    },
    "RKD": { (params, args) throws -> GateInstance in
        if params.count != 1 { throw ParseCircuitError.InvalidGateParamCount }
        if args.count != 1 { throw ParseCircuitError.InvalidGateParamCount }
        return GateInstance.init(phase: -complexExponentPhaseFraction2(k: Int(params[0])),
                                 primaryBit: CUnsignedChar(args[0]),
                                 controlBit: NO_CONTROL,
                                 control2Bit: NO_CONTROL,
                                 useChoice: false,
                                 doToggle: false,
                                 doMeasure: false)
    },
    // TODO: Implement SWAP and others
    /*"SWAP": { (params, args) throws -> GateInstance in
        if params.count != 1 { throw ParseCircuitError.InvalidGateParamCount }
        if args.count != 1 { throw ParseCircuitError.InvalidGateParamCount }
        return GateInstance.init(phase: float2(0, 0),
                                 primaryBit: CUnsignedChar(args[0]),
                                 controlBit: ???,
                                 control2Bit: NO_CONTROL,
                                 useChoice: false,
                                 doToggle: false,
                                 doMeasure: false)
    },*/
]
func parseCircuitString(circuitStr: String) throws -> [GateInstance] {
    var circuit = [GateInstance]()
    for line in circuitStr.components(separatedBy: .newlines) {
        let leftRight = line.components(separatedBy: "(")
        if leftRight.count < 2 { continue; }
        let right = leftRight[1].components(separatedBy: ")")
        if right.count < 2 { continue; }
        let argStrs = right[0].components(separatedBy: ",")
        let argNums = try argStrs.map({ (argStr) throws -> Int in
            if let arg = Int(argStr.trimmingCharacters(in: .whitespaces)) { return arg }
            else { throw ParseCircuitError.InvalidSyntaxArg }
        })
        let nameParam = leftRight[0].components(separatedBy: "_")
        let nameStr = nameParam[0].uppercased()
        let paramNums = try nameParam[1...].map({ (paramStr) throws -> Float in
            if let param = Float(paramStr) { return param }
            else { throw ParseCircuitError.InvalidSyntaxParam }
        })
        if let initFunc = gateInitializers[nameStr] {
            let gate = try initFunc(paramNums, argNums)
            circuit.append(gate)
            continue
        }
        if nameStr.count >= 3 && nameStr.starts(with: "CC") {
            let index = nameStr.index(after: nameStr.index(after: nameStr.startIndex))
            let subStr = String(nameStr[index...])
            if let initFunc = gateInitializers[subStr] {
                var gate = try initFunc(paramNums, [Int](argNums.suffix(from: 2)))
                gate.controlBit = CUnsignedChar(argNums[0])
                gate.control2Bit = CUnsignedChar(argNums[1])
                circuit.append(gate)
                continue
            }
        }
        if nameStr.count >= 2 && nameStr.starts(with: "C") {
            let index = nameStr.index(after: nameStr.startIndex)
            let subStr = String(nameStr[index...])
            if let initFunc = gateInitializers[subStr] {
                var gate = try initFunc(paramNums, [Int](argNums.suffix(from: 1)))
                gate.controlBit = CUnsignedChar(argNums[0])
                circuit.append(gate)
                continue
            }
        }
        print("Warning: Unknown gate \"\(nameStr)\"")
        continue
    }
    return circuit
}

func loadCircuit(filePath: String) -> CircuitDetails? {
    do {
        let fileContents = try String(contentsOfFile: filePath)
        do {
            let gates = try parseCircuitString(circuitStr: fileContents)
            let circuit = computeCircuitDetails(gates: gates)
            print("Circuit (# hadamard=\(circuit.hadamardCount), # measure=\(circuit.measureIndexList.count):")
            for gate in circuit.gates {
                print("    \(gate)")
            }
            return circuit
        } catch {
            print("Error parsing file")
        }
    } catch {
        print("Error opening file")
    }
    return nil
}

func computeCircuitDetails(gates: [GateInstance]) -> CircuitDetails {
    var hadamardCount = 0
    var measureIndexList = [Int]()
    for (i, gate) in gates.enumerated() {
        if gate.useChoice {
            hadamardCount += 1
        }
        if gate.doMeasure {
            measureIndexList.append(i)
        }
    }
    return CircuitDetails(gates: gates, hadamardCount: hadamardCount, measureIndexList: measureIndexList)
}

