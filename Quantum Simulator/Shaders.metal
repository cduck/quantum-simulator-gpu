//
//  Shaders.metal
//  Quantum Simulator
//
//  Created by Casey Duckering on 2017-10-14.
//  Copyright © 2017 Casey Duckering. All rights reserved.
//

#include <metal_stdlib>
#include <simd/simd.h>

#import "ShaderTypes.h"

using namespace metal;


float2 complexProduct(float2 a, float2 b) {
    return float2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

kernel void
pathKernel(constant MeasureConfig &measureConfig [[buffer(0)]],
           constant DispatchConfig &dispatchConfig [[buffer(1)]],
           constant GateInstance *gates [[buffer(2)]],
           device   SumPair *sumOutput [[buffer(3)]],
           uint     id [[thread_position_in_grid]])
{
    SumPair sumTotal = SumPair { float4(0, 0, 0, 0) };

    // Calculate many paths per kernel thread to increase overall speed
    const constexpr int expPathsPerThread = 8;
    const constexpr int numPathsPerThread = 1 << expPathsPerThread;
    for (int p=0; p < numPathsPerThread; p++) {

        // Calcualte a single path through the gates
        uint choices = (((dispatchConfig.restOfChoices ^ id) << expPathsPerThread) | p);
        uint matchMask = measureConfig.matchMask;  // TODO: Larger measurements
        uint matchMeasure = measureConfig.matchMeasure;
        uint state = 0;  // TODO: Larger state
        float2 pathPhase = float2(1.0f, 0.0f);
        bool measurementsMatch = true;
        bool lastMeasurement = false;

        for (int i=0; i < measureConfig.numGates; i++) {
            // Apply a single gate
            //GateInstance gate = gates[i];
            #define gate (gates[i])
            bool choice = choices & 0x1;
            if (gate.useChoice) { choices >>= 1; }  // Consume choice from list
            bool primaryVal = (state >> gate.primaryBit) & 0x1;
            bool doToggle = gate.doToggle;
            bool addPhase = primaryVal;
            // TODO: Support SWAP and CSWAP gates
            if ((gate.controlBit == 255  || ((state >> gate.controlBit)  & 0x1)) &&
                (gate.control2Bit == 255 || ((state >> gate.control2Bit) & 0x1))) {
                if (gate.useChoice) {
                    addPhase = addPhase && choice;
                    if (choice) {
                        state |= 0x1 << gate.primaryBit;  // Turn on bit
                    } else {
                        state ^= primaryVal << gate.primaryBit;  // Turn off bit
                    }
                }
                if (doToggle) {
                    state ^= 0x1 << gate.primaryBit;
                }
                if (addPhase) {
                    // Add phase by multiplying complex numbers
                    pathPhase = complexProduct(pathPhase, gate.phase);
                }
            }
            if (gate.doMeasure) {
                // Read bit value
                lastMeasurement = (state >> gate.primaryBit) & 0x1;
                // If mask, check that this measurement matches the desired measurement
                if (matchMask & 0x1) {
                    measurementsMatch = measurementsMatch && lastMeasurement == (matchMeasure & 0x1);
                }
                matchMask >>= 1;
                matchMeasure >>= 1;
            }
        }
        
        // Make measurement of this path, adding the result to the total sum
        if (measurementsMatch) {
            if (lastMeasurement) {
                // Measure one
                sumTotal.val01 += float4(0.0f, 0.0f, pathPhase);
            } else {
                // Measure zero
                sumTotal.val01 += float4(pathPhase, 0.0f, 0.0f);
            }
        } else {
            // Previous measurement did not match, don't add to sum
        }
    }

    sumOutput[id] = sumTotal;
}



// General sum kernel
void sumKernel(device SumPair *inputArray,
               device SumPair *sumOutput,
               uint   id)
{
    const constexpr int numSumsPerThread = 1 << 6;
    device SumPair *start = inputArray + numSumsPerThread * id;

    SumPair total = SumPair { float4(0, 0, 0, 0) };
    for (int i=0; i < numSumsPerThread; i++) {
        total.val01 += start[i].val01;
    }

    sumOutput[id] = total;
}

// Define a sum kernel specific to each sum stage
#define SUM_KERNEL_STAGE(STAGE) \
kernel void \
sumKernel ## STAGE(device SumPair *inputArray [[buffer(STAGE + 3)]], \
                   device SumPair *sumOutput [[buffer(STAGE + 4)]], \
                   uint   id [[thread_position_in_grid]]) { \
    sumKernel(inputArray, sumOutput, id); \
}
SUM_KERNEL_STAGE(0)
SUM_KERNEL_STAGE(1)
SUM_KERNEL_STAGE(2)
SUM_KERNEL_STAGE(3)
SUM_KERNEL_STAGE(4)
SUM_KERNEL_STAGE(5)
SUM_KERNEL_STAGE(6)
SUM_KERNEL_STAGE(7)


// Simple kernel that just copies a value
// This kernel is scheduled at the end of actual computation and its result
// is used to check that the OS did not kill the GPU
kernel void
completionCheckKernel(device MeasureConfig &measureConfig [[buffer(0)]]) {
    measureConfig.didCalculationFinish = measureConfig.numGates;
}

