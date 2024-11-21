//
//  gpu_nms.hpp
//  Nutrivance
//
//  Created by Vincent Leong on 11/19/24.
//

#ifndef GPU_NMS_HPP
#define GPU_NMS_HPP

#include <vector>
#import <Metal/Metal.h>

class GPUNonMaxSuppression {
private:
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;

public:
    GPUNonMaxSuppression();
    std::vector<float> process(const std::vector<float>& boxes, float thresh);
};

#endif

