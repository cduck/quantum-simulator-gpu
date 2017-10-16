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
pathKernel(constant GroupConfig &groupConfig [[buffer(0)]],
           constant GateInstance *gates [[buffer(1)]],
           device   SumPair *sumOutput [[buffer(2)]],
           uint     gid [[thread_position_in_grid]])
{
    int a = 0;
    for (int i=0; i<groupConfig.numGates; i++) {
        a += gates[i].primaryBit;
    }
    sumOutput[gid].val01 = float4(1.0f, gid, a, groupConfig.restOfChoices);
}

//kernel void
//sumKernel(

