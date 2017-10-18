//
//  ShaderTypes.h
//  Quantum Simulator
//
//  Created by Casey Duckering on 2017-10-14.
//  Copyright © 2017 Casey Duckering. All rights reserved.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>


typedef struct {
    vector_float2 phase;
    unsigned char primaryBit;
    unsigned char controlBit;
    unsigned char control2Bit;
    bool useChoice : 1;
    bool doToggle : 1;
    bool doMeasure : 1;
    
} GateInstance;


typedef struct {
    int numGates;
    int numGatesCommon;
    unsigned int matchMask;  // TODO: Longer state
    unsigned int matchMeasure;
    int restOfChoicesLength;  // Not used right now
    int didCalculationFinish;
} MeasureConfig;


typedef struct {
    unsigned int restOfChoices;
} DispatchConfig;


typedef struct {
    vector_float4 val01;
} SumPair;


/*void initCircuitDataNum(int numGates);
void initCircuitDataGate(int i,
                         unsigned short type,
                         unsigned short primaryBit,
                         unsigned short controlBit,
                         unsigned short control2Bit);
void initGroupConfig(unsigned int restOfChoices);
void init*/


#endif /* ShaderTypes_h */
