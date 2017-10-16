//
//  Shaders.metal
//  Metal2Test
//
//  Created by Casey Duckering on 2017-10-14.
//  Copyright © 2017 Casey Duckering. All rights reserved.
//

#include <metal_stdlib>
#include <simd/simd.h>

#import "ShaderTypes.h"

using namespace metal;


kernel void
pathKernel(constant MeasureConfig &measureConfig [[buffer(0)]],
           constant DispatchConfig &dispatchConfig [[buffer(1)]],
           constant GateInstance *gates [[buffer(2)]],
           device   SumPair *sumOutput [[buffer(3)]],
           uint     id [[thread_position_in_grid]])
{
    SumPair sumTotal = SumPair { float4(0, 0, 0, 0) };

    const constexpr int numPathsPerThread = 1 << 8;
    for (int p=0; p < numPathsPerThread; p++) {
        int a = dispatchConfig.restOfChoices;
        for (int i=0; i < measureConfig.numGates; i++) {
            a += gates[i].primaryBit;
        }
        sumTotal.val01 += float4(1.0f, a, 0.0f, dispatchConfig.restOfChoices);
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

