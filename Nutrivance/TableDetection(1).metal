//
//  TableDetection.metal
//  Nutrivance
//
//  Created by Vincent Leong on 11/20/24.
//

#include <metal_stdlib>
using namespace metal;

kernel void detectTablesKernel(device float* input [[buffer(0)]],
                             device float* output [[buffer(1)]],
                             uint index [[thread_position_in_grid]]) {
    // Table detection logic
    output[index] = input[index];
}
