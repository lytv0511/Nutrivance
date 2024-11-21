//
//  NutritionExtractorWrapper.mm
//  Nutrivance
//
//  Created by Vincent Leong on 11/19/24.
//

#import "NutritionExtractorWrapper.h"
#import <Metal/Metal.h>
#import <CoreML/CoreML.h>
#import <Vision/Vision.h>
// Change the include path to match your project structure
#include "../NutritionExtractor/lib/utils/gpu_nms.h"

@implementation NutritionExtractorWrapper {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _device = MTLCreateSystemDefaultDevice();
        _commandQueue = [_device newCommandQueue];
    }
    return self;
}

- (NSArray *)detectNutritionTable:(UIImage *)image {
    // Convert image to pixel buffer
    CVPixelBufferRef pixelBuffer = [self pixelBufferFromImage:image];
    
    // Process image using Metal for GPU acceleration
    id<MTLBuffer> inputBuffer = [self prepareInputBuffer:pixelBuffer];
    
    // Perform table detection
    NSArray *detections = [self detectTables:inputBuffer];
    
    CVPixelBufferRelease(pixelBuffer);
    return detections;
}

- (CVPixelBufferRef)pixelBufferFromImage:(UIImage *)image {
    CGImageRef cgImage = image.CGImage;
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    
    NSDictionary *options = @{
        (NSString*)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
    };
    
    CVPixelBufferRef pixelBuffer = NULL;
    CVPixelBufferCreate(kCFAllocatorDefault,
                       width,
                       height,
                       kCVPixelFormatType_32ARGB,
                       (__bridge CFDictionaryRef)options,
                       &pixelBuffer);
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(baseAddress,
                                               width,
                                               height,
                                               8,
                                               CVPixelBufferGetBytesPerRow(pixelBuffer),
                                               colorSpace,
                                               kCGImageAlphaNoneSkipFirst);
    
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
    
    CGColorSpaceRelease(colorSpace);
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    return pixelBuffer;
}

- (id<MTLBuffer>)prepareInputBuffer:(CVPixelBufferRef)pixelBuffer {
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    
    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    
    id<MTLBuffer> buffer = [_device newBufferWithBytes:baseAddress
                                              length:height * bytesPerRow
                                             options:MTLResourceStorageModeShared];
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    return buffer;
}

- (NSArray *)detectTables:(id<MTLBuffer>)inputBuffer {
    id<MTLComputePipelineState> pipelineState = [self createComputePipeline];
    
    // Create output buffer
    id<MTLBuffer> outputBuffer = [_device newBufferWithLength:inputBuffer.length
                                                    options:MTLResourceStorageModeShared];
    
    // Set up command buffer and encoder
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
    
    [computeEncoder setComputePipelineState:pipelineState];
    [computeEncoder setBuffer:inputBuffer offset:0 atIndex:0];
    [computeEncoder setBuffer:outputBuffer offset:0 atIndex:1];
    
    MTLSize gridSize = MTLSizeMake(inputBuffer.length / sizeof(float), 1, 1);
    MTLSize threadGroupSize = MTLSizeMake(pipelineState.maxTotalThreadsPerThreadgroup, 1, 1);
    [computeEncoder dispatchThreads:gridSize threadsPerThreadgroup:threadGroupSize];
    
    [computeEncoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
    
    return [self processDetectionResults:outputBuffer];
}


- (id<MTLComputePipelineState>)createComputePipeline {
    NSError *error = nil;
    id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];
    id<MTLFunction> kernelFunction = [defaultLibrary newFunctionWithName:@"detectTablesKernel"];
    id<MTLComputePipelineState> pipelineState = [_device newComputePipelineStateWithFunction:kernelFunction error:&error];
    
    if (!pipelineState) {
        NSLog(@"Failed to create pipeline state: %@", error);
    }
    
    return pipelineState;
}

- (NSArray *)processDetectionResults:(id<MTLBuffer>)buffer {
    float *data = (float *)[buffer contents];
    NSMutableArray *results = [NSMutableArray array];
    
    // Process detection results
    size_t numElements = buffer.length / sizeof(float);
    for (size_t i = 0; i < numElements; i += 4) {
        if (data[i + 4] > 0.5) { // Confidence threshold
            NSDictionary *detection = @{
                @"x": @(data[i]),
                @"y": @(data[i + 1]),
                @"width": @(data[i + 2]),
                @"height": @(data[i + 3]),
                @"confidence": @(data[i + 4])
            };
            [results addObject:detection];
        }
    }
    
    return results;
}

@end
