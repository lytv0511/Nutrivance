//
//  gpu_nms.cpp
//  Nutrivance
//
//  Created by Vincent Leong on 11/19/24.
//

#include "gpu_nms.h"

GPUNonMaxSuppression::GPUNonMaxSuppression() {
    _device = MTLCreateSystemDefaultDevice();
    _commandQueue = [_device newCommandQueue];
}

std::vector<float> GPUNonMaxSuppression::process(const std::vector<float>& boxes, float thresh) {
    NSUInteger bufferSize = boxes.size() * sizeof(float);
//    id<MTLBuffer> inputBuffer = [_device newBufferWithBytes:boxes.data() length:bufferSize options:MTLResourceStorageModeShared];
    id<MTLBuffer> outputBuffer = [_device newBufferWithLength:bufferSize options:MTLResourceStorageModeShared];
    
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
    
    [computeEncoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
    
    std::vector<float> results(boxes.size());
    memcpy(results.data(), [outputBuffer contents], bufferSize);
    return results;
}
