//
//  NutritionExtractorWrapper.h
//  Nutrivance
//
//  Created by Vincent Leong on 11/19/24.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>

@interface NutritionExtractorWrapper : NSObject

- (instancetype)init;
- (NSArray *)detectNutritionTable:(UIImage *)image;
- (CVPixelBufferRef)pixelBufferFromImage:(UIImage *)image;
- (id<MTLBuffer>)prepareInputBuffer:(CVPixelBufferRef)pixelBuffer;
- (id<MTLComputePipelineState>)createComputePipeline;
- (NSArray *)processDetectionResults:(id<MTLBuffer>)buffer;

@end

